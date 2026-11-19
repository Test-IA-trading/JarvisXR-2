"""Exercise the compiled Windows companion with an isolated local Ollama stand-in."""
from __future__ import annotations

import http.client
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class StandIn(BaseHTTPRequestHandler):
    requests: list[dict] = []

    def log_message(self, *_):
        pass

    def reply(self, status, value):
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/api/tags":
            return self.reply(404, {})
        self.reply(200, {"models": [{"name": "qwen3:8b"}]})

    def do_POST(self):
        if self.path != "/api/chat":
            return self.reply(404, {})
        value = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.requests.append(value)
        prompt = value["messages"][-1]["content"]
        if prompt == "erreur du modèle":
            return self.reply(503, {"error": "stand-in"})
        self.reply(200, {"done": True, "message": {"role": "assistant", "content": "Déjà reçu : " + prompt[:40]}})


@unittest.skipUnless(sys.platform == "win32", "requires the Windows Framework compiler")
class ChatSmoke(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            model = ThreadingHTTPServer(("127.0.0.1", 11434), StandIn)
        except OSError as error:
            raise unittest.SkipTest("The test Ollama port is already in use; leave the existing service alone.") from error
        cls.addClassCleanup(model.server_close)
        threading.Thread(target=model.serve_forever, daemon=True).start()
        cls.addClassCleanup(model.shutdown)
        tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(tmp.cleanup)
        env = dict(os.environ, LOCALAPPDATA=tmp.name, CI="1")
        subprocess.run(
            ["cmd.exe", "/d", "/c", "Demarrer-Jarvis.cmd", "--build-only"], cwd=ROOT, env=env,
            check=True, timeout=90,
        )
        exe = Path(tmp.name, "JarvisXR", "Companion", "JarvisXR-Chat.exe")
        log_path = Path(tmp.name, "session.txt")
        with log_path.open("wb") as log:
            process = subprocess.Popen([str(exe), "--pc", "--no-browser"], env=env, stdout=log, stderr=subprocess.STDOUT)

        def stop():
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=8)
        cls.addClassCleanup(stop)
        for _ in range(160):
            output = log_path.read_text(encoding="utf-8", errors="replace")
            match = re.search(r"Code : ([A-F0-9]{4}(?:-[A-F0-9]{4}){3})", output)
            if match:
                cls.code = match.group(1).replace("-", "")
                return
            if process.poll() is not None:
                break
            time.sleep(0.1)
        raise AssertionError("Companion did not start: " + output)

    def request(self, path, value=None, code=None, origin=None):
        connection = http.client.HTTPConnection("127.0.0.1", 8765, timeout=8)
        try:
            headers = {"Content-Type": "application/json", "X-Jarvis-Code": code or self.code}
            if origin:
                headers["Origin"] = origin
            body = json.dumps(value, ensure_ascii=False).encode("utf-8") if value is not None else None
            connection.request("GET" if value is None else "POST", path, body, headers)
            response = connection.getresponse()
            data = response.read().decode("utf-8")
            return response.status, json.loads(data) if "application/json" in response.getheader("Content-Type") else data
        finally:
            connection.close()

    def test_session(self):
        self.assertIn("Ouvrir la conversation", self.request("/")[1])
        for path in ["/chat.js", "/app.css"]:
            self.assertEqual(self.request(path)[0], 200)
        self.assertEqual(self.request("/api/session", {}), (200, {"model": "qwen3:8b"}))
        wrong = ("1" if self.code[0] == "0" else "0") + self.code[1:]
        self.assertEqual(self.request("/api/session", {}, code=wrong)[0], 401)
        self.assertEqual(self.request("/api/session", {}, origin="https://example.invalid")[0], 403)
        self.assertEqual(self.request("/api/pull", {})[0], 404)

    def test_conversation_payload(self):
        turns = [{"role": "user", "content": "Retiens Léa"}, {"role": "assistant", "content": "Compris"},
                 {"role": "user", "content": "Quel prénom ?"}]
        status, result = self.request("/api/chat", {"messages": turns})
        self.assertEqual((status, result["reply"]), (200, "Déjà reçu : Quel prénom ?"))
        call = StandIn.requests[-1]
        self.assertEqual(call["messages"][1:], turns)
        self.assertEqual((call["model"], call["think"], call["stream"]), ("qwen3:8b", False, False))
        self.assertEqual(call["options"], {"num_ctx": 4096, "num_predict": 512})
        self.assertNotIn("tools", call)

    def test_limits_and_recovery(self):
        for message in [{"role": "system", "content": "instruction"}, {"role": "user", "content": "x" * 2001}]:
            self.assertEqual(self.request("/api/chat", {"messages": [message]})[0], 400)
        turns = [{"role": "user", "content": "x" * 1900}, {"role": "assistant", "content": "y" * 2600},
                 {"role": "user", "content": "nouvelle question"}]
        self.assertEqual(self.request("/api/chat", {"messages": turns})[0], 200)
        self.assertEqual(StandIn.requests[-1]["messages"][1:], turns[-1:])
        for prompt, expected in [("erreur du modèle", 502), ("reprise", 200)]:
            self.assertEqual(self.request("/api/chat", {"messages": [{"role": "user", "content": prompt}]})[0], expected)


if __name__ == "__main__":
    unittest.main()
