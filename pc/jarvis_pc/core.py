"""What the PC Jarvis does with a request, whether it comes from its microphone, its
keyboard or the iPhone: exact commands first, then the brain with what Jarvis knows."""
from __future__ import annotations

import threading
from collections import deque
from datetime import datetime, timezone

from .brain import OllamaBrain
from .memory import Memory
from .router import Answer, Router


class JarvisCore:
    def __init__(self, settings, memory: Memory, brain: OllamaBrain, router: Router, speaker=None):
        self.settings = settings
        self.memory = memory
        self.brain = brain
        self.router = router
        self.speaker = speaker
        self.history: deque = deque(maxlen=6)
        self.inbox: list[dict] = []  # messages waiting for the iPhone
        self.lock = threading.Lock()
        self.timers: list[threading.Timer] = []

    def handle(self, text: str, source: str = "pc", on_text=None) -> Answer:
        answer = self.router.route(text)
        if answer is None:
            try:
                spoken = self.brain.ask(text, list(self.history), self.memory.context_lines(), on_text=on_text)
            except Exception as error:  # noqa: BLE001 — explained to the user instead
                spoken = str(error) if isinstance(error, RuntimeError) else "Le cerveau du PC a rencontré une erreur. Réessayez."
            answer = Answer(spoken, data={"brain": self.brain.active_model() or ""})
        self.history.append({"user": text, "assistant": answer.spoken})
        self._side_effects(answer)
        return answer

    def ask_brain(self, question: str, history: list[dict], context: list[str], on_text=None) -> str:
        """An open question from the iPhone: the PC's brain, with what both know."""
        merged = self.memory.context_lines() + [line for line in context if line not in self.memory.context_lines()]
        return self.brain.ask(question, history, merged, on_text=on_text)

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
