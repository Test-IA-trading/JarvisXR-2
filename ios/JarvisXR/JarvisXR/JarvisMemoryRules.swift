import Foundation

/// The rules with which Jarvis learns from what the user says (pc/jarvis_pc/knowledge.py),
/// written from the Python by pc/tools_gen_personality.py so that the iPhone and the PC
/// learn the same way (pc/tests check both are identical). Patterns apply to the folded
/// text (lowercase, no accents, « œ » → « oe »).
enum JarvisMemoryRules {
    static let stopwords: Set<String> = ["a", "au", "aux", "avec", "bien", "c", "ca", "ce", "ces", "cet", "cette", "comment", "d", "de", "des", "dis", "du", "elle", "elles", "en", "est", "est-ce", "et", "etre", "eu", "faire", "fait", "il", "ils", "j", "jarvis", "je", "l", "la", "le", "les", "leur", "lui", "m", "ma", "mais", "me", "mes", "moi", "moins", "mon", "n", "ne", "ni", "nos", "notre", "nous", "on", "ou", "par", "pas", "peut", "peux", "plus", "pour", "qu", "que", "quel", "quelle", "quelles", "quels", "qui", "quoi", "s", "sa", "se", "ses", "si", "son", "sont", "sur", "t", "ta", "te", "tes", "toi", "ton", "tres", "tu", "un", "une", "veux", "vos", "votre", "vous", "y"]

    /// (pattern, kind, template with {0} and {1} for the user's own words).
    static let learning: [(pattern: String, kind: String, template: String)] = [
        ("\\bje (?:prefere|prefererais) (.+)", "preference", "L'utilisateur préfère {0}."),
        ("\\bj'(?:aime|adore) (?:bien )?(.+)", "preference", "L'utilisateur aime {0}."),
        ("\\bje (?:n'aime|deteste) (?:pas )?(.+)", "preference", "L'utilisateur n'aime pas {0}."),
        ("\\bappelle[ -]moi (.+)", "preference", "L'utilisateur veut être appelé {0}."),
        ("\\bj'habite (?:a |au |en |aux )?(.+)", "fait", "L'utilisateur habite {0}."),
        ("\\bje (?:vis|demeure) (?:a |au |en |aux )(.+)", "fait", "L'utilisateur habite {0}."),
        ("\\bje travaille (.+)", "fait", "L'utilisateur travaille {0}."),
        ("\\bje suis (?:ne|nee) (.+)", "fait", "L'utilisateur est né {0}."),
        ("\\bmon anniversaire (?:est|c'est) (.+)", "fait", "L'anniversaire de l'utilisateur est {0}."),
        ("\\b(?:mon|ma|mes) ([^\\W\\d_][\\w' ]{2,30}?) (?:s'appelle|s'appellent|est|sont) (.+)", "fait", "{0} de l'utilisateur : {1}."),
        ("\\b((?:tous les|chaque) (?:matins?|soirs?|jours?|lundis?|mardis?|mercredis?|jeudis?|vendredis?|samedis?|dimanches?),? je .+)", "habitude", "Habitude de l'utilisateur : « {0} »."),
        ("\\b((?:d'habitude|en general|souvent),? je .+)", "habitude", "Habitude de l'utilisateur : « {0} »."),
        ("\\b(?:reponds|parle)[ -]moi (.+)", "preference", "L'utilisateur veut des réponses {0}."),
    ]

    /// « Non, c'est 1873 » after an answer: a correction (the words after it are group 1).
    static let correction = "^[ ?!.]*(?:non|mais non|pas du tout|c'est faux|faux|tu te trompes|ce n'est pas ca|c'est pas ca)\\b[ ,.!]*(.*)"
}
