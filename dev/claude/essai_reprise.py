"""Vérifier le rappel d'une consigne par Qwen dans trois sessions Claude Code neuves."""
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODEL = "qwen3:8b"
LOCAL_HOST = "http://127.0.0.1:11434"
QUESTION = ("Quel est le repère de reprise de cet essai Jarvis ? "
            "Réponds uniquement par sa valeur, ou INCONNU si elle n'est pas indiquée.")


def answer(command, project, profile):
    env = dict(os.environ, OLLAMA_HOST=LOCAL_HOST, CLAUDE_CONFIG_DIR=str(profile),
               CLAUDE_CODE_DISABLE_AUTO_MEMORY="1", CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1")
    run = subprocess.run(
        [*command, "launch", "claude", "--model", MODEL, "--", "-p",
         "--no-session-persistence", "--strict-mcp-config", "--setting-sources", "project",
         "--tools", "", "--permission-mode", "default", "--max-turns", "1",
         "--output-format", "json", "--", QUESTION],
        cwd=project, env=env, stdin=subprocess.DEVNULL, capture_output=True,
        encoding="utf-8", errors="replace", timeout=300,
    )
    if run.returncode:
        detail = (run.stderr.strip() or run.stdout.strip()).splitlines()
        raise ValueError(detail[-1][:300] if detail else f"Code de sortie {run.returncode}")
    # Le lanceur peut annoncer le démarrage avant le résultat JSON de Claude Code.
    for line in reversed(run.stdout.splitlines()):
        try:
            result = json.loads(line)
        except ValueError:
            continue
        if isinstance(result, dict) and result.get("type") == "result":
            if (result.get("subtype") == "success" and result.get("is_error") is False
                    and isinstance(result.get("result"), str)):
                return result["result"].strip()
            raise ValueError("Claude Code signale un échec de la session.")
    raise ValueError("Le lanceur n’a renvoyé aucun résultat JSON de Claude Code.")


def evaluate(command):
    initial, revised = ("JRV-" + secrets.token_hex(8).upper() for _ in range(2))
    scenarios = [
        ("Fiche sans repère", "", "INCONNU"),
        ("Décision enregistrée", f"Le repère de reprise est {initial}.", initial),
        ("Décision corrigée", f"Le repère de reprise est {revised}.", revised),
    ]
    checks = []
    with tempfile.TemporaryDirectory(prefix="jarvis-reprise-") as temp:
        base = Path(temp)
        project = base / "projet"
        project.mkdir()
        shutil.copyfile(ROOT / "CLAUDE.md", project / "CLAUDE.md")
        for index, (label, decision, expected) in enumerate(scenarios):
            # Seule la fiche du projet porte la valeur. La question est identique.
            (project / "AGENTS.md").write_text("# Essai Jarvis\n" + decision + "\n", encoding="utf-8")
            profile = base / f"profil-{index}"
            profile.mkdir()
            response = answer(command, project, profile)
            checks.append((label, response == expected))
    return checks


def main():
    ollama = shutil.which("ollama")
    if not ollama:
        raise ValueError("Ollama est introuvable sur cette machine.")
    binary = "claude.exe" if os.name == "nt" else "claude"
    fallbacks = [Path.home() / ".local/bin" / binary, Path.home() / ".claude/local" / binary]
    if not shutil.which("claude") and not any(path.is_file() for path in fallbacks):
        raise ValueError("Claude Code est introuvable sur cette machine.")
    listed = subprocess.run([ollama, "list"], env=dict(os.environ, OLLAMA_HOST=LOCAL_HOST),
                            capture_output=True, text=True, errors="replace", timeout=20)
    if listed.returncode:
        raise ValueError("Ollama local ne répond pas. Ouvre Ollama sur le PC qui héberge Qwen.")
    if not any(line.split()[:1] == [MODEL] for line in listed.stdout.splitlines()):
        raise ValueError(f"Ollama ne trouve pas {MODEL} parmi les modèles installés.")
    print("Trois sessions locales vont répondre à la même question.", flush=True)
    checks = evaluate([ollama])
    for label, passed in checks:
        print(f"{label} — {'réussi' if passed else 'échoué'}")
    return 0 if all(passed for _, passed in checks) else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f"Essai incomplet. {error}")
