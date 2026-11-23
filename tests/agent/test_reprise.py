from pathlib import Path
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "dev" / "claude"))
import essai_reprise as recall


# Ce processus imite le format de sortie de la CLI. Il ne fait aucune inférence.
CLI = """\
import json, os, pathlib, re, sys
p = pathlib.Path
args = sys.argv[1:]
assert args[:5] == ['launch', 'claude', '--model', 'qwen3:8b', '--']
assert args[args.index('--tools') + 1] == ''
assert '--no-session-persistence' in args and '--strict-mcp-config' in args
assert args[args.index('--setting-sources') + 1] == 'project'
assert os.environ['OLLAMA_HOST'] == 'http://127.0.0.1:11434'
assert os.environ['CLAUDE_CODE_DISABLE_AUTO_MEMORY'] == '1'
profile = p(os.environ['CLAUDE_CONFIG_DIR'])
assert profile.is_dir() and not any(profile.iterdir())
(profile / 'utilise').touch()
matches = re.findall(r'^@([A-Za-z0-9._/-]+)$', p('CLAUDE.md').read_text(encoding='utf-8'), re.MULTILINE)
assert matches == ['AGENTS.md']
decision = re.search(r'JRV-[0-9A-F]{16}', p(matches[0]).read_text(encoding='utf-8'))
assert not re.search(r'JRV-[0-9A-F]{16}', ' '.join(args))
value = decision.group() if decision else 'INCONNU'
mode = os.environ.get('JARVIS_TEST_MODE')
if mode == 'inventer' and not decision:
    value = 'JRV-INVENTE'
elif mode == 'perime' and decision:
    cache = p('precedent')
    if cache.exists():
        value = cache.read_text()
    else:
        cache.write_text(value)
elif mode == 'absent':
    print('Lanceur prêt.')
    sys.exit(0)
print('Lanceur prêt.')
print(json.dumps({'type': 'result', 'subtype': 'success', 'is_error': mode == 'erreur', 'result': value}))
"""


class RepriseTests(unittest.TestCase):
    def simulate(self, mode="normal"):
        with tempfile.TemporaryDirectory() as work, patch.dict(os.environ, JARVIS_TEST_MODE=mode):
            program = Path(work) / "cli.py"
            program.write_text(CLI, encoding="utf-8")
            return [ok for _, ok in recall.evaluate([sys.executable, str(program)])]

    def test_trois_sessions_neuves(self):
        self.assertEqual(self.simulate(), [True, True, True])

    def test_reponse_inventee_sans_fiche(self):
        self.assertEqual(self.simulate("inventer"), [False, True, True])

    def test_ancienne_decision_apres_correction(self):
        self.assertEqual(self.simulate("perime"), [True, True, False])

    def test_erreur_applicative_malgre_un_code_de_sortie_nul(self):
        with self.assertRaisesRegex(ValueError, "échec"):
            self.simulate("erreur")

    def test_sortie_incomplete(self):
        with self.assertRaisesRegex(ValueError, "aucun résultat"):
            self.simulate("absent")
