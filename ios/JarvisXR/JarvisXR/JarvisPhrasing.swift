import Foundation

/// Free phrasing → the plain wording Jarvis's commands know, so the user need not learn
/// one sentence per command:
///
///     « Est-ce que tu pourrais m'ouvrir YouTube, s'il te plaît ? »  → « ouvre-moi YouTube ? »
///     « J'aimerais que tu appelles Paul »                           → « appelle Paul »
///     « Tu peux me dire ce qu'est l'arrêt Blanco ? »                → « qu'est-ce que l'arrêt Blanco ? »
///
/// Only the start of the sentence is rewritten (politeness is dropped anywhere); the rest
/// keeps the user's own words, accents and capitals. When nothing is recognised, the text
/// comes back unchanged. Jarvis PC applies the same rules (pc/jarvis_pc/phrasing.py).
enum JarvisPhrasing {
    /// Infinitive → imperative (« tu peux ouvrir… » → « ouvre… »).
    static let infinitives: [String: String] = [
        "ouvrir": "ouvre", "lancer": "lance", "démarrer": "démarre", "demarrer": "demarre", "appeler": "appelle",
        "téléphoner": "téléphone", "telephoner": "telephone", "rappeler": "rappelle", "envoyer": "envoie",
        "écrire": "écris", "ecrire": "ecris", "dire": "dis", "mettre": "mets", "remettre": "remets", "montrer": "montre",
        "afficher": "affiche", "chercher": "cherche", "rechercher": "recherche", "trouver": "trouve", "jouer": "joue",
        "lire": "lis", "relire": "relis", "prendre": "prends", "noter": "note", "calculer": "calcule", "donner": "donne",
        "faire": "fais", "régler": "règle", "regler": "regle", "programmer": "programme", "allumer": "allume",
        "éteindre": "éteins", "eteindre": "eteins", "fermer": "ferme", "arrêter": "arrête", "arreter": "arrete",
        "supprimer": "supprime", "effacer": "efface", "ajouter": "ajoute", "créer": "crée", "creer": "cree",
        "enregistrer": "enregistre", "traduire": "traduis", "convertir": "convertis", "compter": "compte",
        "expliquer": "explique", "raconter": "raconte", "parler": "parle", "aller": "va", "passer": "passe",
        "regarder": "regarde", "vérifier": "vérifie", "verifier": "verifie", "annuler": "annule", "reprendre": "reprends",
        "préparer": "prépare", "preparer": "prepare", "répéter": "répète", "repeter": "repete", "prévenir": "préviens",
        "prevenir": "previens", "demander": "demande", "indiquer": "indique", "couper": "coupe", "activer": "active",
        "désactiver": "désactive", "desactiver": "desactive", "baisser": "baisse", "monter": "monte",
        "augmenter": "augmente", "résumer": "résume", "resumer": "resume", "définir": "définis", "definir": "definis",
        "souvenir": "souviens", "rappeller": "rappelle",
    ]

    /// Second person subjunctive → imperative (« j'aimerais que tu appelles… » → « appelle… »).
    static let subjunctives: [String: String] = [
        "ouvres": "ouvre", "lances": "lance", "démarres": "démarre", "demarres": "demarre", "appelles": "appelle",
        "téléphones": "téléphone", "telephones": "telephone", "rappelles": "rappelle", "envoies": "envoie",
        "écrives": "écris", "ecrives": "ecris", "dises": "dis", "mettes": "mets", "montres": "montre",
        "affiches": "affiche", "cherches": "cherche", "recherches": "recherche", "trouves": "trouve", "joues": "joue",
        "lises": "lis", "prennes": "prends", "notes": "note", "calcules": "calcule", "donnes": "donne", "fasses": "fais",
        "règles": "règle", "programmes": "programme", "allumes": "allume", "éteignes": "éteins", "eteignes": "eteins",
        "fermes": "ferme", "arrêtes": "arrête", "arretes": "arrete", "supprimes": "supprime", "effaces": "efface",
        "ajoutes": "ajoute", "crées": "crée", "enregistres": "enregistre", "traduises": "traduis", "expliques": "explique",
        "racontes": "raconte", "parles": "parle", "ailles": "va", "passes": "passe", "regardes": "regarde",
        "vérifies": "vérifie", "verifies": "verifie", "annules": "annule", "prépares": "prépare", "répètes": "répète",
        "préviennes": "préviens", "demandes": "demande", "indiques": "indique", "coupes": "coupe", "actives": "active",
        "désactives": "désactive", "baisses": "baisse", "résumes": "résume", "souviennes": "souviens",
    ]

    /// Verbs that only carry the question: « je voudrais savoir quelle heure il est ».
    static let droppedVerbs: Set<String> = ["savoir", "connaître", "connaitre"]

    private static let asking = "(?:quel|quelle|quels|quelles|qui|combien|comment|pourquoi|où|ou|quand|si|s'|ce que|ce qu'|ce qui|est-ce|est ce|c'est|qu'est)"
    private static let possessive = "(?!(?:mon|ma|mes|ton|ta|tes|votre|vos|notre|nos)\\b)"

    /// The patterns are constants checked by JarvisPhrasingTests; one that would not
    /// compile is left out rather than stopping the app.
    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let politeness = regex("[\\s,]*\\b(?:s'il (?:te|vous) pla[iî]t|stp|svp|please)\\b[\\s,]*")
    private static let trailingThanks = regex("[\\s,]+merci(?: beaucoup| bien)?\\s*([.!?]*)\\s*$")

    /// (pattern, replacement), applied in this order at the start of the request.
    static let startPatterns: [(String, String)] = [
        // « Jarvis, … », « Dis Jarvis, … » (the router knows it, but the hedges come after it).
        ("^(?:(?:dis|hey|ok|okay|eh)\\s+)?jarvis\\b[\\s,.:;!?]*", ""),
        ("^(?:alors|bon|bah|ben|euh+|heu+|hum+|écoute|écoutez|ecoute|ecoutez|dis donc|tiens)\\b[\\s,.:;!?]+", ""),
        // « dis-moi quel temps il fait » → « quel temps il fait »
        ("^(?:dis|dites)[- ]moi\\s+(?=\(asking))", ""),
        // « tu sais quelle heure il est ? » → « quelle heure il est ? »
        ("^(?:est[- ]ce (?:que |qu'))?(?:tu sais|vous savez|sais[- ]tu|savez[- ]vous)\\s+(?=\(asking))", ""),
        // Questions about a subject, in the wording Wikipédia's rule knows.
        ("^(?:ce qu'est|ce que sont)\\s+\(possessive)", "qu'est-ce que "),
        ("^(?:qu'est[- ]ce que c'est|ce que c'est)(?:\\s+que|\\s+qu')?[\\s,]+\(possessive)(?=\\S)", "qu'est-ce que "),
        ("^(?:ça|ca) veut dire quoi\\s+", "que veut dire "),
        ("^qui c'est\\s+", "qui est "),
        ("^(?:tu connais|connais[- ]tu|vous connaissez|connaissez[- ]vous)\\s+(?!(?:mon|ma|mes|quel|quelle|qui|combien|comment|pourquoi)\\b)", "parle-moi de "),
        ("^(?:que|qu'est[- ]ce que tu) sais[- ]?(?:tu)? (?:de|du|des|sur)\\s+(?!moi\\b)", "parle-moi de "),
        // Same commands, other words.
        ("^(?:va|allez|rends[- ]toi) sur\\s+", "ouvre "),
        ("^(?:préviens|previens|informe|avertis) (?!moi\\b)(\\S+(?: \\S+)?) (que|qu')", "dis à $1 $2"),
        ("^(?:fais savoir|fait savoir|réponds|reponds) (?:à|a) ", "dis à "),
        ("^(?:envoie|envoies|envoyer|écris|ecris)(?:[- ](?:lui|leur))? un (?:texto|sms|imessage|petit message|petit mot|mot)\\b", "envoie un message"),
        ("^envoie (?:à|a) (?=\\S)", "envoie un message à "),
        ("^(?:passe|fais|lance)(?:[- ]moi)? un (?:coup de fil|coup de téléphone|coup de telephone|appel) (?:à|a|au) ", "appelle "),
    ]

    private static let startRules: [(NSRegularExpression, String)] = startPatterns.compactMap { rule in
        regex(rule.0).map { ($0, rule.1) }
    }

    static let hedgePattern: String = [
        "^(?:est[- ]ce (?:que |qu'))?",
        "(?:(?:tu|vous) (?:peux|pourrais|pouvez|pourriez|veux bien|voudrais bien|voulez bien|voudriez bien|saurais|sauriez|dois|devrais)",
        "|(?:peux|pourrais|veux|voudrais|saurais)[- ]tu|(?:pouvez|pourriez|voulez|voudriez|sauriez)[- ]vous",
        "|(?:c'est|ce serait|ça serait|ca serait|il est|est-il|serait-il) possible (?:de |d')",
        "|(?:je voudrais|je voudrai|j'aimerais|j'aimerai|je veux|j'ai envie)(?: bien)?(?: que (?:tu|vous))?",
        "|(?:il faudrait|faudrait|il faut|il faudra|faut)(?: que (?:tu|vous))?",
        "|j'ai besoin (?:que (?:tu|vous)|de|d')",
        "|merci (?:de|d'))",
        "[\\s,]*(?:juste |vite |rapidement |simplement |bien |encore )?",
        "(?:(me |m'|te |t'|nous )\\s*)?",
        "([a-zàâäçéèêëîïôöûùüÿœ]+)",
    ].joined()

    private static let hedge = regex(hedgePattern)

    /// Every pattern compiles (checked by the tests: a broken one would be skipped silently).
    static var allPatternsCompile: Bool {
        startRules.count == startPatterns.count && hedge != nil && politeness != nil && trailingThanks != nil
    }

    /// The request in the plain wording of the commands, or `text` itself.
    static func rewrite(_ text: String) -> String {
        let original = collapse(text.replacingOccurrences(of: "’", with: "'"))
        var value = original
        if let politeness {
            value = replace(politeness, in: value, with: " ")
        }
        value = withoutThanks(collapse(value))
        value = collapse(value)
        for _ in 0..<5 {
            let before = value
            for (pattern, template) in startRules {
                value = trimLeading(replace(pattern, in: value, with: template))
            }
            value = rewriteHedge(value)
            if value == before { break }
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?")).isEmpty ? original : value
    }

    static func imperative(of verb: String, pronoun: String) -> String? {
        let lowered = verb.lowercased()
        let object = pronoun.trimmingCharacters(in: .whitespaces).lowercased()
        if droppedVerbs.contains(lowered) && object.isEmpty { return "" }
        guard let base = infinitives[lowered] ?? subjunctives[lowered] else { return nil }
        if base == "souviens" {
            // « tu peux te souvenir que… » → « souviens-toi que… »
            return object == "te" || object == "t'" ? "souviens-toi" : nil
        }
        switch object {
        case "me", "m'": return base + "-moi"
        case "nous": return base + "-nous"
        case "te", "t'": return nil
        default: return base
        }
    }

    private static func rewriteHedge(_ text: String) -> String {
        let ns = text as NSString
        guard let hedge, let match = hedge.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return text }
        let pronounRange = match.range(at: 1)
        let pronoun = pronounRange.location == NSNotFound ? "" : ns.substring(with: pronounRange)
        let verb = ns.substring(with: match.range(at: 2))
        guard let imperative = imperative(of: verb, pronoun: pronoun) else { return text }
        let rest = trimLeading(ns.substring(from: match.range.location + match.range.length))
        return imperative.isEmpty ? rest : "\(imperative) \(rest)".trimmingCharacters(in: .whitespaces)
    }

    /// « Ouvre YouTube, merci ! » → « Ouvre YouTube ! »; « Non merci » stays.
    private static func withoutThanks(_ text: String) -> String {
        let ns = text as NSString
        guard let trailingThanks,
              let match = trailingThanks.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return text }
        let before = ns.substring(to: match.range.location)
        guard before.split(separator: " ").count >= 2 else { return text }
        let punctuationRange = match.range(at: 1)
        let punctuation = punctuationRange.location == NSNotFound ? "" : ns.substring(with: punctuationRange)
        return punctuation.isEmpty ? before : "\(before) \(punctuation)"
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }

    private static func trimLeading(_ text: String) -> String {
        String(text.drop { $0 == " " || $0 == "," })
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
