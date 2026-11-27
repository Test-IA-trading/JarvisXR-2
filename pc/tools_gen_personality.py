"""Writes ios/JarvisXR/JarvisXR/JarvisPersonality.swift from pc/jarvis_pc/personality.py,
so that the iPhone's brain gets exactly the same personality rules as the PC's.

    pc\\.venv\\Scripts\\python pc\\tools_gen_personality.py
"""
from pathlib import Path

from jarvis_pc import personality as p


def swift(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


TEMPLATE = '''import Foundation

/// Jarvis's personality (docs/specs/personnalite.md), the same rules as Jarvis PC
/// (pc/jarvis_pc/personality.py, from which this file is written by
/// pc/tools_gen_personality.py; pc/tests check that both say exactly the same): a British
/// butler's courtesy and dry humour, in French with « vous » and « Monsieur » used
/// sparingly. Given to the brain as compact rules, never as canned lines.
enum JarvisPersonality {{
    /// Intensities validated by the owner (percent): preferences, not quotas.
    static let profile: [String: Int] = [{profile}]

    static let identity = {identity}
    static let address = {address}
    static let humour = {humour}
    static let serious = {serious}
    static let initiative = {initiative}
    static let honesty = {honesty}
    static let correction = {correction}
    static let adaptation = {adaptation}
    static let lengthSimple = {simple}
    static let lengthNormal = {normal}
    static let lengthComplex = {complex}

    static let seriousWords = [{words}]

    /// A serious subject (health, danger, distress): no irony at all.
    static func isSerious(_ text: String) -> Bool {{
        let folded = " " + text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased().replacingOccurrences(of: "-", with: " ") + " "
        return seriousWords.contains {{ folded.contains(" " + $0) }}
    }}

    /// The personality lines of the system prompt for one request.
    static func rules(for question: String) -> [String] {{
        let words = question.split(whereSeparator: {{ !$0.isLetter && !$0.isNumber }}).count
        let length = words > 25 ? lengthComplex : words <= 6 ? lengthSimple : lengthNormal
        return [identity, address, isSerious(question) ? serious : humour, length, initiative, honesty, correction, adaptation]
    }}
}}
'''


def render() -> str:
    return TEMPLATE.format(
        profile=", ".join(f"{swift(k)}: {v}" for k, v in p.PROFILE.items()),
        identity=swift(p.IDENTITY), address=swift(p.ADDRESS), humour=swift(p.HUMOUR), serious=swift(p.SERIOUS),
        initiative=swift(p.INITIATIVE), honesty=swift(p.HONESTY), correction=swift(p.CORRECTION), adaptation=swift(p.ADAPTATION),
        simple=swift(p.LENGTH["simple"]), normal=swift(p.LENGTH["normale"]), complex=swift(p.LENGTH["complexe"]),
        words=", ".join(swift(w) for w in p.SERIOUS_WORDS),
    )


TARGET = Path(__file__).resolve().parent.parent / "ios" / "JarvisXR" / "JarvisXR" / "JarvisPersonality.swift"

if __name__ == "__main__":
    TARGET.write_text(render(), encoding="utf-8", newline="\n")
    print(f"écrit : {TARGET}")
