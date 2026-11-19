"""Run Token Optimizer's report on the project's Claude instructions only."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

REVISION = "f450eb6f3cf496e8cefc08500d88510394c4c4e8"
RELEASE = "v5.13.73"
REPOSITORY = "https://github.com/alexgreensh/token-optimizer.git"
SCRIPTS = Path("skills/token-optimizer/scripts")
FINGERPRINT = "20eabccece73c649cec6bca1b0157cee98482d98da939cae4b577204c7ee11bf"


def verified(path):
    digest = hashlib.sha256()
    for file in sorted(path.rglob("*"), key=lambda item: item.relative_to(path).as_posix()):
        if file.is_symlink():
            raise ValueError(f"Lien inattendu dans les scripts : {file.name}")
        if file.is_file():
            relative = file.relative_to(path).as_posix().encode("utf-8")
            digest.update(relative + b"\0" + hashlib.sha256(file.read_bytes()).digest())
    if digest.hexdigest() != FINGERPRINT:
        raise ValueError("Le dossier de scripts ne correspond pas à la version vérifiée de Token Optimizer.")
    return path.resolve()


def cached_scripts():
    base = Path(os.environ.get("LOCALAPPDATA") or os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    parent = base / "JarvisXR" / "token-optimizer"
    target = parent / REVISION
    if target.exists():
        return verified(target / SCRIPTS)
    if not shutil.which("git"):
        raise ValueError("Git est nécessaire au premier audit. Un dossier existant peut être fourni avec --scripts.")
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=parent) as stage:
        checkout = Path(stage) / "source"
        env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        git = ["git", "-c", "core.autocrlf=false", "-c", f"core.hooksPath={Path(stage) / 'no-hooks'}"]

        def run(*args, directory=None):
            return subprocess.run([*git, *args], cwd=directory, env=env, check=True,
                                  stdout=subprocess.PIPE, text=True, timeout=150).stdout.strip()

        run("clone", "--quiet", "--depth=1", "--filter=blob:none", "--no-checkout",
            "--branch", RELEASE, REPOSITORY, str(checkout))
        if run("rev-parse", "HEAD", directory=checkout) != REVISION:
            raise ValueError("Le tag reçu ne correspond pas au commit attendu.")
        run("sparse-checkout", "set", "--no-cone", "/skills/token-optimizer/scripts/", directory=checkout)
        run("checkout", "--quiet", "--detach", REVISION, directory=checkout)
        source = verified(checkout / SCRIPTS)
        bundle = Path(stage) / "bundle"
        destination = bundle / SCRIPTS
        destination.parent.mkdir(parents=True)
        source.rename(destination)
        try:
            bundle.rename(target)
        except OSError:
            if not target.is_dir():
                raise
    return verified(target / SCRIPTS)


def measure(project, scripts):
    project = project.resolve()
    with tempfile.TemporaryDirectory(prefix="jarvis-budget-") as temporary:
        root = Path(temporary)
        home, sample, work = root / "home", root / "projet", root / "temp"
        (home / ".claude").mkdir(parents=True)
        sample.mkdir()
        work.mkdir()
        found = False
        for name in ("CLAUDE.md", ".claude/CLAUDE.md"):
            source = project / name
            if source.is_file() and source.resolve().is_relative_to(project):
                dest = sample / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                content = source.read_text(encoding="utf-8")
                if name == "CLAUDE.md" and "@AGENTS.md" in content.splitlines():
                    shared = project / "AGENTS.md"
                    if not shared.is_file() or not shared.resolve().is_relative_to(project):
                        raise ValueError("La fiche AGENTS.md importée est introuvable dans ce projet.")
                    content = re.sub(r"^@AGENTS\.md$", lambda _: shared.read_text(encoding="utf-8").rstrip(),
                                     content, flags=re.MULTILINE)
                dest.write_text(content, encoding="utf-8")
                found = True
        if not found:
            raise ValueError("Aucun fichier CLAUDE.md à mesurer dans ce projet.")
        env = {key: os.environ[key] for key in ("PATH", "SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "LANG") if key in os.environ}
        env.update(HOME=str(home), USERPROFILE=str(home), APPDATA=str(home / "roaming"),
                   LOCALAPPDATA=str(home / "local"), CLAUDE_CONFIG_DIR=str(home / ".claude"),
                   XDG_CONFIG_HOME=str(home / "config"), XDG_CACHE_HOME=str(home / "cache"),
                   TMP=str(work), TEMP=str(work), TMPDIR=str(work), LANG="C.UTF-8")
        report = subprocess.run([sys.executable, "-E", "-s", "-B", "-X", "utf8", str(scripts / "measure.py"),
                                 "--runtime", "claude", "report"], cwd=sample, env=env,
                                capture_output=True, text=True, encoding="utf-8", timeout=45)
        if report.returncode:
            detail = report.stderr.strip().splitlines()
            raise ValueError("Le diagnostic a échoué. " + (detail[-1] if detail else f"Code {report.returncode}"))
        counts = re.findall(r"^\s*claude_md_\S+\s+([\d,]+) tokens\b", report.stdout, re.MULTILINE)
        if not counts:
            raise ValueError("Le rapport ne contient pas de mesure des instructions du projet.")
        return sum(int(n.replace(",", "")) for n in counts)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scripts", type=Path, help="Scripts déjà extraits de la version vérifiée.")
    parser.add_argument("--projet", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    try:
        scripts = verified(args.scripts) if args.scripts else cached_scripts()
        print(f"Instructions CLAUDE.md : {measure(args.projet, scripts)} tokens estimés (Token Optimizer {RELEASE}).")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
