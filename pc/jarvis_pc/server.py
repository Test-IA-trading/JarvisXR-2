"""The PC Jarvis's door for the iPhone: a small HTTP server (port 8765) on the home Wi-Fi
and on Tailscale. Every request but /v1/health needs the pairing code shown on the PC.
Ollama itself stays closed to the network: the iPhone only talks to this server."""
from __future__ import annotations

import hmac
import json
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import __version__

MAX_BODY = 64 * 1024


def is_tailscale(address: str) -> bool:
    """Tailscale gives each device an address in 100.64.0.0/10."""
    parts = address.split(".")
    return len(parts) == 4 and parts[0] == "100" and parts[1].isdigit() and 64 <= int(parts[1]) <= 127


def local_addresses() -> list[str]:
    """IPv4 addresses the iPhone can reach, for the pairing screen and Bonjour: the home
    network's first (the interface of the default route), then Tailscale's. The virtual
    switches of Hyper-V, WSL or Docker (often 172.x) are left out: the iPhone cannot reach them."""
    addresses = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addresses.add(info[4][0])
    except OSError:
        pass
    primary = None
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("192.0.2.1", 9))  # no packet is sent: only picks the outgoing interface
        primary = probe.getsockname()[0]
        probe.close()
    except OSError:
        pass
    chosen = [primary] if primary and not primary.startswith(("127.", "169.254.", "0.")) else []
    chosen += sorted(a for a in addresses if is_tailscale(a) and a not in chosen)
    if not chosen:
        chosen = sorted(a for a in addresses if not a.startswith(("127.", "169.254.")))
    return chosen


class JarvisServer:
    def __init__(self, core, settings, host: str = "0.0.0.0", port: int | None = None):
        self.core = core
        self.settings = settings
        self.httpd = ThreadingHTTPServer((host, port if port is not None else settings.port), self._handler())
        self.httpd.daemon_threads = True
        self.zeroconf = None

    @property
    def port(self) -> int:
        return self.httpd.server_address[1]

    def start(self, advertise: bool = True) -> None:
        threading.Thread(target=self.httpd.serve_forever, name="jarvis-server", daemon=True).start()
        if advertise:
            self._advertise()

    def stop(self) -> None:
        if self.zeroconf is not None:
            try:
                self.zeroconf.unregister_all_services()
                self.zeroconf.close()
            except Exception:  # noqa: BLE001
                pass
        self.httpd.shutdown()
        self.httpd.server_close()

    def _advertise(self) -> None:
        """« Jarvis PC » on the home network (Bonjour), so the iPhone finds it by itself."""
        try:
            from zeroconf import ServiceInfo, Zeroconf
        except ImportError:
            return
        addresses = [socket.inet_aton(a) for a in local_addresses() if not a.startswith("169.254.")]
        if not addresses:
            return
        info = ServiceInfo("_jarvis._tcp.local.", "Jarvis PC._jarvis._tcp.local.", addresses=addresses, port=self.port,
                           properties={"v": __version__})
        try:
            self.zeroconf = Zeroconf()
            self.zeroconf.register_service(info)
        except Exception:  # noqa: BLE001 — Bonjour is a convenience, the address can be typed
            self.zeroconf = None

    def voice(self):
        """The PC's voice (the one Jarvis speaks with here, or the same settings without speakers)."""
        if self.core.speaker is not None:
            return self.core.speaker
        if getattr(self, "_voice", None) is None:
            from .voice import Speaker

            self._voice = Speaker(self.settings.voice_speaker, self.settings.voice_length_scale, model=self.settings.piper_voice,
                                  sentence_silence=self.settings.voice_sentence_silence)
        return self._voice

    def memory_payload(self) -> dict:
        """The shared notes and first name, plus Jarvis's durable memories and the ones deleted on the PC."""
        payload = self.core.memory.snapshot()
        payload["knowledge"] = self.core.knowledge.export() + [{"id": i, "deleted": True} for i in self.core.forgotten[-50:]]
        return payload

    def _handler(self):
        server = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.0"  # a streamed answer ends when the connection closes

            def log_message(self, format, *args):  # noqa: A002 — quiet console
                return

            def _authorized(self) -> bool:
                header = self.headers.get("Authorization", "")
                code = header[7:] if header.startswith("Bearer ") else ""
                return hmac.compare_digest(code.strip().upper(), server.settings.pairing_code.upper())

            def _json(self, status: int, payload: dict) -> None:
                body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _body(self) -> dict | None:
                length = int(self.headers.get("Content-Length") or 0)
                if length <= 0 or length > MAX_BODY:
                    return None
                try:
                    data = json.loads(self.rfile.read(length).decode("utf-8"))
                except (ValueError, UnicodeDecodeError):
                    return None
                return data if isinstance(data, dict) else None

            def do_GET(self):  # noqa: N802
                if self.path == "/v1/health":
                    paired = self._authorized()
                    payload = {"name": "Jarvis PC", "version": __version__, "paired": paired}
                    if paired:
                        payload["model"] = server.core.brain.active_model()
                        payload["voice"] = True  # /v1/tts: the iPhone may speak with the PC's voice
                    return self._json(200, payload)
                if not self._authorized():
                    return self._json(401, {"error": "Code d'appairage manquant ou faux."})
                if self.path == "/v1/memory":
                    return self._json(200, server.memory_payload())
                if self.path == "/v1/inbox":
                    return self._json(200, {"messages": server.core.take_inbox()})
                return self._json(404, {"error": "Inconnu."})

            def do_POST(self):  # noqa: N802
                if not self._authorized():
                    return self._json(401, {"error": "Code d'appairage manquant ou faux."})
                data = self._body()
                if data is None:
                    return self._json(400, {"error": "Requête illisible."})
                if self.path == "/v1/ask":
                    return self._ask(data)
                if self.path == "/v1/command":
                    text = str(data.get("text", "")).strip()
                    if not text:
                        return self._json(400, {"error": "Texte vide."})
                    answer = server.core.handle(text, source="iphone")
                    return self._json(200, {"spoken": answer.spoken, "display": answer.display, "data": answer.data})
                if self.path == "/v1/memory":
                    server.core.memory.merge(data)
                    # Jarvis's long-term memory travels with the notes (docs/specs/personnalite.md §6).
                    server.core.knowledge.merge(data.get("knowledge") or [])
                    return self._json(200, server.memory_payload())
                if self.path == "/v1/tts":
                    # Jarvis's PC voice for the iPhone: one sentence as WAV (docs/specs/voix.md §7).
                    text = str(data.get("text", "")).strip()[:600]
                    if not text:
                        return self._json(400, {"error": "Texte vide."})
                    try:
                        audio = server.voice().wav_bytes(text)
                    except Exception as error:  # noqa: BLE001 — the iPhone falls back to its own voice
                        return self._json(503, {"error": f"Voix du PC indisponible : {error}"})
                    self.send_response(200)
                    self.send_header("Content-Type", "audio/wav")
                    self.send_header("Content-Length", str(len(audio)))
                    self.end_headers()
                    self.wfile.write(audio)
                    return None
                if self.path == "/v1/say":
                    text = str(data.get("text", "")).strip()
                    if text:
                        server.core.notify(text)
                    return self._json(200, {"ok": bool(text)})
                return self._json(404, {"error": "Inconnu."})

            def _ask(self, data: dict) -> None:
                question = str(data.get("question", "")).strip()
                if not question:
                    return self._json(400, {"error": "Question vide."})
                history = [t for t in data.get("history", []) if isinstance(t, dict)][-6:]
                context = [str(c) for c in data.get("context", []) if isinstance(c, str)][:12]
                # « iphone »: the brain may answer « COMMANDE: appelle Paul » for the iPhone to run.
                commands = data.get("commands") if data.get("commands") == "iphone" else None
                self.send_response(200)
                self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
                self.end_headers()

                def send(payload: dict) -> None:
                    self.wfile.write((json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8"))
                    self.wfile.flush()

                try:
                    answer = server.core.ask_brain(question, history, context, on_text=lambda partial: send({"partial": partial}),
                                                   commands=commands)
                    send({"final": answer, "tokens_per_second": round(server.core.brain.last_tokens_per_second, 1)})
                except (BrokenPipeError, ConnectionResetError):
                    return
                except Exception as error:  # noqa: BLE001 — the iPhone falls back to its own brain
                    send({"error": str(error)})

        return Handler
