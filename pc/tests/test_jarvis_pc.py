"""PC Jarvis: everything that runs without a network, a microphone or Ollama."""
import json
import math
import urllib.error
import urllib.request
from datetime import datetime

import pytest

from jarvis_pc import wake
from jarvis_pc.brain import SentenceStreamer, clean, system_prompt
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

    def ask(self, question, history=None, context=None, on_text=None, timeout=300):
        if on_text:
            on_text("Bonjour.")
            on_text("Bonjour. Je suis Jarvis.")
        return "Bonjour. Je suis Jarvis."


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
