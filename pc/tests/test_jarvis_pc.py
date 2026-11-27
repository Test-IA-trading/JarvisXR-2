"""PC Jarvis: everything that runs without a network, a microphone or Ollama."""
import json
import math
import urllib.error
import urllib.request
from datetime import datetime

import pytest

from jarvis_pc import apps, internet, phrasing, research, wake
from jarvis_pc.brain import PC_COMMANDS, SentenceStreamer, clean, command_in, may_be_command, system_prompt
from jarvis_pc.claps import Detector
from jarvis_pc.core import JarvisCore
from jarvis_pc.memory import Memory
from jarvis_pc.router import Router
from jarvis_pc.server import JarvisServer

NOW = datetime(2026, 11, 25, 15, 40)


class FakeSettings:
    pairing_code = "TEST-CODE"
    port = 0
    internet = False
    city = ""

    def save(self):
        pass


class FakeBrain:
    last_tokens_per_second = 50.0

    def active_model(self):
        return "faux-modele"

    def ask(self, question, history=None, context=None, on_text=None, timeout=300, commands=None):
        if on_text:
            on_text("Bonjour.")
            on_text("Bonjour. Je suis Jarvis.")
        return "Bonjour. Je suis Jarvis."


class CommandBrain(FakeBrain):
    """Rewords every request into the same command, as Qwen does for free phrasing."""

    def __init__(self, reply):
        self.reply = reply
        self.asked = []

    def ask(self, question, history=None, context=None, on_text=None, timeout=300, commands=None):
        self.asked.append({"question": question, "commands": commands, "context": list(context or [])})
        reply = self.reply if commands else "Voici une vraie réponse."
        if on_text:
            on_text(reply[:4])
            on_text(reply)
        return reply


@pytest.fixture
def memory(tmp_path):
    return Memory(tmp_path / "memory.json")


@pytest.fixture
def router(memory):
    opened = []
    router = Router(memory, FakeSettings(), opener=opened.append, browser=opened.append)
    router.opened = opened
    return router


def spoken(router, phrase):
    answer = router.route(phrase, now=NOW)
    return answer.spoken if answer else None


def test_exact_answers_match_the_iphone(router):
    assert spoken(router, "Combien font 128 fois 46 ?") == "128 fois 46 égale 5888."
    assert spoken(router, "Intégrale de 0 à 1 de x au carré") == "L'intégrale de 0 à 1 de x² vaut 1/3, soit environ 0,333."
    assert spoken(router, "Convertis 10 miles en kilomètres") == "10 miles font 16,09 kilomètres."
    assert spoken(router, "Combien de jours avant Noël ?") == "Noël est dans 30 jours, le vendredi 25 décembre 2026."
    assert spoken(router, "Quelle heure est-il ?") == "Il est 15 h 40."
    assert spoken(router, "Quel jour sommes-nous ?") == "Nous sommes le mercredi 25 novembre 2026."


def test_name_and_notes_are_kept(router, memory):
    assert spoken(router, "Je m'appelle tony") == "Enchanté, Tony. Je m'en souviendrai."
    assert spoken(router, "Bonjour Jarvis") == "Bonjour Tony ! Je vous écoute."
    assert spoken(router, "Jarvis, souviens-toi que j'aime le café noir") == "C'est noté."
    assert memory.latest_notes() == ["j'aime le café noir"]
    assert "café noir" in spoken(router, "Qu'est-ce que tu sais sur moi ?")
    assert spoken(router, "Oublie mon prénom").startswith("C'est oublié")
    assert memory.name is None


def test_the_pc_opens_apps_sites_and_searches(router):
    assert spoken(router, "Ouvre Spotify") == "J'ouvre Spotify."
    assert spoken(router, "Ouvre YouTube") == "J'ouvre YouTube."
    assert spoken(router, "Cherche la recette des crêpes sur Internet") == "Je cherche « la recette des crêpes » sur Internet."
    assert router.opened[:2] == ["spotify:", "https://www.youtube.com"]
    assert router.opened[2].endswith("la%20recette%20des%20cr%C3%AApes")


def test_free_phrasing_becomes_the_commands_wording():
    """The owner's test (25/11): Jarvis understood only one wording per command."""
    cases = {
        "Est-ce que tu pourrais m'ouvrir YouTube, s'il te plaît ?": "ouvre-moi YouTube ?",
        "Jarvis, tu peux appeler maman ?": "appelle maman ?",
        "J'aimerais que tu appelles Paul": "appelle Paul",
        "Je voudrais que tu me rappelles d'acheter du pain": "rappelle-moi d'acheter du pain",
        "Tu peux me dire quelle heure il est ?": "quelle heure il est ?",
        "Je voudrais savoir quel temps il fait": "quel temps il fait",
        "Pourrais-tu me donner la météo ?": "donne-moi la météo ?",
        "Dis-moi ce qu'est l'arrêt Blanco": "qu'est-ce que l'arrêt Blanco",
        "Qu'est-ce que c'est, l'arrêt Blanco ?": "qu'est-ce que l'arrêt Blanco ?",
        "Tu connais l'arrêt Blanco ?": "parle-moi de l'arrêt Blanco ?",
        "Préviens Marie que je serai en retard": "dis à Marie que je serai en retard",
        "Envoie un texto à Paul pour lui dire que j'arrive": "envoie un message à Paul pour lui dire que j'arrive",
        "Va sur leboncoin.fr": "ouvre leboncoin.fr",
        "Tu peux te souvenir que je bois mon café noir ?": "souviens-toi que je bois mon café noir ?",
        "Ouvre YouTube, merci beaucoup !": "Ouvre YouTube !",
        "Euh, est-ce que tu peux mettre un minuteur de 10 minutes": "mets un minuteur de 10 minutes",
        "Tu peux m'appeler Tony": "appelle-moi Tony",
    }
    for said, routed in cases.items():
        assert phrasing.rewrite(said) == routed, said
    for unchanged in ["Pourquoi le ciel est-il bleu ?", "Je veux dormir", "Merci", "Non merci", "Bonjour Jarvis", "Jarvis",
                      "Tu connais mon nom ?", "Tu m'entends ?", "C'est quoi mon prénom ?", "Qu'est-ce que tu sais sur moi ?"]:
        assert phrasing.rewrite(unchanged) == unchanged, unchanged


def test_the_pc_opens_what_is_asked_however_it_is_said(router):
    for phrase in ["Ouvre You Tube", "ouvre youtube.com", "Ouvre la page YouTube", "Tu peux ouvrir YouTube ?", "Va sur YouTube",
                   "Est-ce que tu pourrais m'ouvrir YouTube s'il te plaît", "Lance le site de YouTube", "Mets YouTube", "Ouvre Youtub"]:
        router.opened.clear()
        assert spoken(router, phrase) == "J'ouvre YouTube.", phrase
        assert router.opened == ["https://www.youtube.com"], phrase
    assert spoken(router, "Ouvre l'application Spotify") == "J'ouvre Spotify."
    assert spoken(router, "Ouvre mes téléchargements") == "J'ouvre vos Téléchargements."
    assert spoken(router, "Ouvre Photoshop").startswith("Je ne trouve pas « Photoshop » parmi les applications du PC")
    assert router.opened[-1] == "https://duckduckgo.com/?q=%21ducky%20Photoshop"
    assert spoken(router, "Mets Lofi Girl sur YouTube") == "Je cherche « Lofi Girl » sur YouTube."
    assert router.opened[-1] == "https://www.youtube.com/results?search_query=Lofi%20Girl"
    assert router.route("Mets de la musique", now=NOW) is None, "for the brain"
    assert router.route("Ouvre le truc", now=NOW) is None


def test_the_start_menu_apps_are_found():
    catalog = apps.Catalog(loader=lambda: [("Microsoft Word", "Microsoft.Office.WINWORD.EXE.15"), ("WhatsApp", "WhatsAppDesktop!App"),
                                           ("Calculatrice", "Microsoft.WindowsCalculator!App")])
    assert catalog.find("Word") == ("Microsoft Word", "shell:AppsFolder\\Microsoft.Office.WINWORD.EXE.15")
    assert catalog.find("l'application WhatsApp") == ("WhatsApp", "shell:AppsFolder\\WhatsAppDesktop!App"), "the app before the site"
    assert catalog.find("la calculatrice") == ("la Calculatrice", "shell:AppsFolder\\Microsoft.WindowsCalculator!App")
    assert catalog.find("leboncoin point fr") == ("leboncoin", "https://www.leboncoin.fr")
    assert catalog.find("monsite.fr") == ("monsite.fr", "https://monsite.fr")
    assert apps.Catalog(loader=lambda: 1 / 0).find("YouTube")[1] == "https://www.youtube.com", "a failing Start menu is no problem"


def test_the_brain_turns_free_requests_into_commands(memory):
    settings = FakeSettings()
    opened = []
    router = Router(memory, settings, opener=opened.append, browser=opened.append)
    brain = CommandBrain("COMMANDE: ouvre YouTube")
    core = JarvisCore(settings, memory, brain, router)
    heard = []
    answer = core.handle("J'ai envie de regarder des vidéos de chats", on_text=heard.append)
    assert answer.spoken == "J'ouvre YouTube." and opened == ["https://www.youtube.com"]
    assert heard == [], "« COMMANDE: … » is never spoken"
    assert brain.asked[0]["commands"] == PC_COMMANDS
    # A rewording that is no command: the brain answers for real.
    core = JarvisCore(settings, memory, CommandBrain("COMMANDE: danse la salsa"), router)
    assert core.handle("Fais-moi danser").spoken == "Voici une vraie réponse."
    assert command_in("COMMANDE: « appelle Paul »") == "appelle Paul"
    assert command_in("Commande : ouvre Word\nautre ligne") == "ouvre Word"
    assert command_in("Comme vous voulez.") is None
    assert may_be_command("COM") and may_be_command("COMMANDE: ou") and not may_be_command("Comme")


def test_knowledge_questions_bring_wikipedia(memory, monkeypatch):
    class Online(FakeSettings):
        internet = True

    looked_up = []

    def fake_wikipedia(subject, sentences=2):
        looked_up.append(subject)
        return ("Arrêt Blanco", "L'arrêt Blanco (8 février 1873) est un arrêt du Tribunal des conflits.")

    monkeypatch.setattr(internet, "wikipedia", fake_wikipedia)
    brain = CommandBrain("Voici une vraie réponse.")
    core = JarvisCore(Online(), memory, brain, Router(memory, Online(), opener=lambda _: None, browser=lambda _: None))
    assert core.handle("Qu'est-ce que c'est, l'arrêt Blanco ?").spoken == "Voici une vraie réponse."
    assert "Extrait de Wikipédia sur « Arrêt Blanco » : L'arrêt Blanco est un arrêt du Tribunal des conflits." in brain.asked[0]["context"]
    for question in ["Dis-moi ce qu'est l'arrêt Blanco", "Tu connais l'arrêt Blanco ?", "Explique-moi l'arrêt Blanco",
                     "C'est quoi l'arrêt Blanco ?", "Qu'est-ce que l'arrêt Blanco ?"]:
        assert research.knowledge_subject(question) == "l'arrêt Blanco", question
    for other in ["Qui est-ce ?", "C'est quoi ton prénom ?", "Pourquoi le ciel est bleu ?", "Explique-moi comment faire des crêpes"]:
        assert research.knowledge_subject(other) is None, other
    core.research("C'est quoi l'arrêt Blanco ?")
    assert looked_up == ["l'arrêt Blanco"], "one lookup per subject"


def test_addresses_for_the_iphone_leave_virtual_switches_out():
    from jarvis_pc.server import is_tailscale

    assert is_tailscale("100.101.12.3") and not is_tailscale("100.20.1.1") and not is_tailscale("172.17.80.1")


def test_timers_and_messages_for_the_phone(router):
    timer = router.route("Mets un minuteur de 5 minutes", now=NOW)
    assert timer.data == {"timer_seconds": 300, "timer_label": "5 minutes"}
    message = router.route("Envoie sur mon téléphone que je rentre à 19 h", now=NOW)
    assert message.data == {"to_phone": "je rentre à 19 h"}


def test_open_questions_go_to_the_brain(router):
    assert router.route("Pourquoi le ciel est-il bleu ?", now=NOW) is None
    assert router.route("Raconte-moi une histoire de pirates", now=NOW) is None


def test_memory_merges_with_the_iphone(memory):
    memory.add_note("note du PC")
    merged = memory.merge({"name": "Tony", "name_updated": "2099-01-01T00:00:00+00:00",
                           "notes": [{"id": "iphone-1", "text": "note de l'iPhone", "created": "2026-11-25T10:00:00+00:00"}]})
    assert merged["name"] == "Tony"
    assert {n["text"] for n in merged["notes"]} == {"note du PC", "note de l'iPhone"}
    again = memory.merge({"notes": [{"id": "iphone-1", "text": "note de l'iPhone"}]})
    assert len(again["notes"]) == 2, "a note is never duplicated"
    assert any("Tony" in line for line in memory.context_lines())


def test_memory_reads_the_iphones_formats(memory):
    """The iPhone sends its ids in capitals and its dates with « Z »."""
    pc_note = memory.add_note("note du PC")
    merged = memory.merge({"notes": [
        {"id": pc_note["id"].upper(), "text": "note du PC", "created": "2026-11-25T08:00:00Z"},
        {"id": "AAAAAAAA-1111-4A4A-9B9B-123456789ABC", "text": "plus récente", "created": "2099-01-01T00:00:00Z"},
    ]})
    assert [n["text"] for n in merged["notes"]] == ["plus récente", "note du PC"], "same note, newest first"
    memory.set_name("Tony")
    memory.merge({"name": "Pepper", "name_updated": "2001-01-01T00:00:00Z"})
    assert memory.name == "Tony", "an older first name does not win"
    memory.merge({"name": "Pepper", "name_updated": "2099-01-01T00:00:00Z"})
    assert memory.name == "Pepper"


def test_wake_word_like_the_iphone():
    assert wake.command("Jarvis, quelle heure est-il ?") == "quelle heure est-il"
    assert wake.command("Quelle heure est-il, Jarvis ?") == "Quelle heure est-il"
    assert wake.command("Hey Jarvis") == ""
    assert wake.command("On regardait un film") is None


def test_wake_word_survives_what_whisper_writes():
    """Mis-hearings seen on the real PC (25/11): « Dis Jarvis » run together, a letter off."""
    assert wake.command("Dijardvis, met un minuteur de 10 minutes.") == "met un minuteur de 10 minutes"
    assert wake.command("Jarvos, quelle heure est-il ?") == "quelle heure est-il"
    assert wake.command("J'arvis, ouvre Spotify") == "ouvre Spotify"
    assert wake.command("Rendez-vous sur le parvis de la gare") is None
    assert wake.command("J'invite mes amis demain soir.") is None
    assert wake.command("Il est ravi de venir") is None
    assert wake.command("J'arrive dans cinq minutes") is None


def test_brain_text_is_clean_for_the_voice():
    assert clean("<think>calculs</think>La réponse est \\( e^x (x - 1) + C \\).") == "La réponse est e^x (x - 1) + C ."
    assert clean("**Bonjour** !\n- un\n- deux") == "Bonjour ! un deux"
    streamer = SentenceStreamer()
    assert streamer.new_sentences("Bonjour. Je suis", False) == ["Bonjour."]
    assert streamer.new_sentences("Bonjour. Je suis Jarvis.", True) == ["Je suis Jarvis."]
    prompt = system_prompt(["La personne qui te parle s'appelle Tony."], now=NOW)
    assert "mercredi 25 novembre 2026" in prompt and "Tony" in prompt and "sans LaTeX" in prompt
    assert "Vouvoie" in prompt, "Jarvis says « vous », as on the iPhone"


def _room(seconds, level=0.002, seed=12345):
    state = seed
    samples = []
    for _ in range(int(seconds * 48000)):
        state = (state * 1103515245 + 12345) % 2147483648
        samples.append((state / 2147483648 * 2 - 1) * level)
    return samples


def _clap(signal, at, seed=99):
    state, start = seed, int(at * 48000)
    for k in range(int(0.25 * 48000)):
        if start + k >= len(signal):
            break
        state = (state * 1103515245 + 12345) % 2147483648
        burst = 0.5 * math.exp(-k / 144) if k < 1440 else 0.0
        signal[start + k] += (burst + 0.03 * math.exp(-k / 3840)) * (state / 2147483648 * 2 - 1)


def test_double_clap_like_the_iphone():
    signal = _room(2.0)
    _clap(signal, 0.6)
    _clap(signal, 0.95)
    detector = Detector(48000)
    hits = sum(detector.ingest(signal[i:i + 1024]) for i in range(0, len(signal), 1024))
    assert hits == 1
    single = _room(2.0)
    _clap(single, 0.6)
    detector = Detector(48000)
    assert not any(detector.ingest(single[i:i + 1024]) for i in range(0, len(single), 1024))


@pytest.fixture
def server(memory):
    settings = FakeSettings()
    core = JarvisCore(settings, memory, FakeBrain(), Router(memory, settings, opener=lambda _: None, browser=lambda _: None))
    server = JarvisServer(core, settings, host="127.0.0.1", port=0)
    server.start(advertise=False)
    yield server
    server.stop()


def _call(server, path, payload=None, code="TEST-CODE"):
    headers = {"Content-Type": "application/json"}
    if code:
        headers["Authorization"] = "Bearer " + code
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(f"http://127.0.0.1:{server.port}{path}", data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8")


def test_server_needs_the_pairing_code(server):
    status, body = _call(server, "/v1/health", code=None)
    assert status == 200 and json.loads(body)["paired"] is False
    assert _call(server, "/v1/command", {"text": "Combien font 3 fois 7 ?"}, code="FAUX")[0] == 401
    assert _call(server, "/v1/memory", code=None)[0] == 401


def test_server_runs_commands_and_streams_the_brain(server):
    status, body = _call(server, "/v1/command", {"text": "Combien font 3 fois 7 ?"})
    assert status == 200 and json.loads(body)["spoken"] == "3 fois 7 égale 21."
    status, body = _call(server, "/v1/ask", {"question": "Bonjour ?", "history": [], "context": ["contexte de l'iPhone"]})
    lines = [json.loads(line) for line in body.splitlines()]
    assert status == 200
    assert lines[0] == {"partial": "Bonjour."}
    assert lines[-1]["final"] == "Bonjour. Je suis Jarvis."


def test_server_shares_memory_and_the_phone_inbox(server):
    status, body = _call(server, "/v1/memory", {"name": "Tony", "name_updated": "2099-01-01T00:00:00+00:00", "notes": []})
    assert status == 200 and json.loads(body)["name"] == "Tony"
    _call(server, "/v1/command", {"text": "Envoie sur mon téléphone que le dîner est prêt"})
    status, body = _call(server, "/v1/inbox")
    assert [m["text"] for m in json.loads(body)["messages"]] == ["que le dîner est prêt"] or \
        [m["text"] for m in json.loads(body)["messages"]] == ["le dîner est prêt"]
    assert json.loads(_call(server, "/v1/inbox")[1])["messages"] == [], "a message is delivered once"
