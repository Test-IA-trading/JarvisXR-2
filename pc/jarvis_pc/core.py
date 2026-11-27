"""What the PC Jarvis does with a request, whether it comes from its microphone, its
keyboard or the iPhone: exact commands first, then the brain with what Jarvis knows.
The brain may also reword a free request into a command (« COMMANDE: ouvre YouTube »),
which is then run like the user's own words."""
from __future__ import annotations

import re
import threading
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from . import internet, research
from .knowledge import Knowledge
from .brain import IPHONE_COMMANDS, PC_COMMANDS, OllamaBrain, command_in, may_be_command
from .memory import Memory
from .phrasing import rewrite as phrasing_of
from .router import Answer, Router


def guarded(on_text):
    """Forwards the text written so far, except while it may be « COMMANDE: … »."""
    if on_text is None:
        return None

    def forward(partial: str) -> None:
        if not may_be_command(partial):
            on_text(partial)

    return forward


class JarvisCore:
    def __init__(self, settings, memory: Memory, brain: OllamaBrain, router: Router, speaker=None, knowledge: Knowledge | None = None):
        self.settings = settings
        self.memory = memory
        # Jarvis's long-term memory, next to the shared notes (« Mémoire Jarvis », an Obsidian vault).
        self.knowledge = knowledge or Knowledge(memory.path.parent / "Mémoire Jarvis")
        router.knowledge = self.knowledge
        self.brain = brain
        self.router = router
        self.speaker = speaker
        self.history: deque = deque(maxlen=6)
        self.inbox: list[dict] = []  # messages waiting for the iPhone
        self.lock = threading.Lock()
        self.timers: list[threading.Timer] = []
        self._research_cache: dict[str, list[str]] = {}
        self.forgotten: list[str] = []  # deleted memories, told to the iPhone at the next sync

    def handle(self, text: str, source: str = "pc", on_text=None) -> Answer:
        self.last_sources = []
        answer = self._forget(text) or self.router.route(text)
        if answer is None:
            answer = self._brain_answer(text, on_text)
        self.after_turn(text, answer.spoken, self.last_sources)
        if answer.data.get("brain") is None:
            # A command: the brain's history shows it as one, so « et Netflix ? » becomes « COMMANDE: ouvre Netflix »
            # instead of an imitated « Je lance… » that does nothing.
            self.history.append({"user": text, "assistant": "COMMANDE: " + answer.data.get("command", phrasing_of(text))})
        else:
            self.history.append({"user": text, "assistant": answer.spoken})
        self._side_effects(answer)
        return answer

    def _forget(self, text: str) -> Answer | None:
        """« Oublie que j'aime le café »: the matching memory is deleted, on both devices at the next sync."""
        match = re.match(r"(?i)^\s*(?:jarvis[ ,]*)?(?:oublie|efface)(?: que| ce que je t'ai dit sur)? (.{3,})", text.strip())
        if not match or re.match(r"(?i)(mon nom|mon prénom|mon prenom)", match.group(1)):
            return None
        removed = self.knowledge.forget(match.group(1))
        if removed is None:
            return Answer("Je n'ai rien retenu de tel, Monsieur.", data={"command": "oublie"})
        self.forgotten.append(removed["id"])
        return Answer("C'est oublié : " + removed["text"], data={"command": "oublie"})

    def after_turn(self, question: str, answer: str, sources: list[str]) -> None:
        """Learns from the exchange in the background (the answer is never delayed): what the user
        said about themselves, a correction of the previous answer, a verified answer to keep."""
        previous = next((turn["user"] for turn in reversed(self.history) if turn.get("user") != question), None)
        if re.match(r"(?i)^\s*(?:jarvis[ ,]*)?(?:oublie|efface)", question):
            return  # « Oublie que j'aime le café » is not learned again

        def work() -> None:
            try:
                self.knowledge.learn(question, answer, previous_question=previous)
                if sources:
                    self.knowledge.cache_answer(question, answer, sources)
            except (OSError, ValueError):
                pass

        threading.Thread(target=work, daemon=True).start()

    def _brain_answer(self, text: str, on_text) -> Answer:
        found = self.research(text)
        context = self.memory.context_lines() + self.knowledge.context_lines(text) + found
        try:
            spoken = self.brain.ask(text, list(self.history), context, on_text=guarded(on_text), commands=PC_COMMANDS)
        except Exception as error:  # noqa: BLE001 — explained to the user instead
            if found:
                source, text = re.match(r"Extrait de (.+?)(?: sur « .* »)? : (.*)", found[0], re.S).groups()
                return Answer(f"D'après {source} : {text}", data={"internet": "wikipedia" if source == "Wikipédia" else "web", "brain": ""})
            spoken = str(error) if isinstance(error, RuntimeError) else "Le cerveau du PC a rencontré une erreur. Réessayez."
            return Answer(spoken, data={"brain": ""})
        command = command_in(spoken)
        if command is not None:
            rerouted = self.router.route(command)
            if rerouted is not None:
                rerouted.data.setdefault("command", command)
                return rerouted
            # The rewording is no command Jarvis knows: a real answer, without commands this time.
            try:
                spoken = self.brain.ask(text, list(self.history), context, on_text=on_text)
            except Exception:  # noqa: BLE001
                spoken = ""
            if not spoken or command_in(spoken) is not None:
                spoken = "Je ne sais pas encore faire cela sur le PC."
        self.last_sources = found
        return Answer(spoken, data={"brain": self.brain.active_model() or ""})

    def ask_brain(self, question: str, history: list[dict], context: list[str], on_text=None, commands: str | None = None) -> str:
        """An open question from the iPhone: the PC's brain, with what both know. With
        `commands="iphone"`, an action comes back as « COMMANDE: … » for the iPhone to run."""
        merged = self.memory.context_lines() + [line for line in context if line not in self.memory.context_lines()]
        found = self.research(question, merged)
        merged += self.knowledge.context_lines(question) + found
        extra = IPHONE_COMMANDS if commands == "iphone" else None
        spoken = self.brain.ask(question, history, merged, on_text=guarded(on_text) if extra else on_text, commands=extra)
        if command_in(spoken) is None:
            self.history.append({"user": question, "assistant": spoken})
            self.after_turn(question, spoken, found)
        return spoken

    def research(self, question: str, context: list[str] | tuple = ()) -> list[str]:
        """What several free sources say about the subject of « Qu'est-ce que… ? » when Internet is
        on: Wikipédia, the English article on the same subject, then DuckDuckGo's first results (the
        page's own text when it opens; none when DuckDuckGo asks for a human check). The brain keeps
        what they agree on and names them."""
        if not getattr(self.settings, "internet", False):
            return []
        subject = research.knowledge_subject(question)
        if not subject:
            # A question about today's world (« Qui a gagné le match hier ? »): the web, fresh each time.
            query = research.web_query(question)
            return [line for line in self._web(query) if line not in context] if query else []
        key = subject.lower()
        if key not in self._research_cache:
            with ThreadPoolExecutor(max_workers=2) as pool:
                wiki, web = pool.submit(self._wikipedia, subject), pool.submit(self._web, subject)
                self._research_cache[key] = wiki.result() + web.result()
        has_wikipedia = any(line.startswith("Extrait de Wikipédia") for line in context)  # the iPhone sent it already
        return [line for line in self._research_cache[key]
                if line not in context and not (has_wikipedia and line.startswith("Extrait de Wikipédia"))]

    @staticmethod
    def _wikipedia(subject: str) -> list[str]:
        try:
            found = internet.wikipedia(subject, sentences=6)
        except (OSError, ValueError):
            return []
        text = re.sub(r"\s*\([^()]*\)", "", found[1]).strip() if found else ""
        if not (found and text):
            return []
        lines = [f"Extrait de Wikipédia sur « {found[0]} » : {text}"]
        try:
            english = internet.english_wikipedia(found[0])
        except (OSError, ValueError):
            english = None
        if english:
            lines.append(f"Extrait de Wikipedia en anglais sur « {english[0]} » : " + re.sub(r"\s*\([^()]*\)", "", english[1]).strip())
        return lines

    @staticmethod
    def _web(subject: str, sources: int = 3) -> list[str]:
        try:
            results = [r for r in internet.web_search(subject, limit=sources + 2) if "wikipedia.org" not in r[0]][:sources]
        except (OSError, ValueError):
            return []

        def excerpt(result: tuple[str, str, str]) -> str:
            site, url, snippet = result
            try:
                found = research.passage(internet.page_text(url), subject)
            except (OSError, ValueError, UnicodeError):
                found = ""
            return f"Extrait de {site} : {found if len(found) > len(snippet) else snippet}"

        with ThreadPoolExecutor(max_workers=sources) as pool:
            return list(pool.map(excerpt, results))

    def _side_effects(self, answer: Answer) -> None:
        seconds = answer.data.get("timer_seconds")
        if seconds:
            label = answer.data.get("timer_label", "")
            timer = threading.Timer(seconds, lambda: self.notify(f"Le minuteur de {label} est terminé."))
            timer.daemon = True
            timer.start()
            self.timers.append(timer)
        message = answer.data.get("to_phone")
        if message:
            with self.lock:
                self.inbox.append({"text": message, "created": datetime.now(timezone.utc).isoformat(timespec="seconds")})

    def take_inbox(self) -> list[dict]:
        with self.lock:
            messages, self.inbox = self.inbox, []
        return messages

    def notify(self, text: str) -> None:
        print(f"Jarvis : {text}")
        if self.speaker is not None:
            threading.Thread(target=self.speaker.say, args=(text,), daemon=True).start()
