import Foundation

/// A French noun with the grammar Jarvis needs to speak about it: gender, elision and
/// past-participle agreement (« la tasse s'est déplacée », « je ne le vois plus »).
struct VisionFrenchNoun: Equatable, Sendable {
    let singular: String
    let isFeminine: Bool
    /// « l'ordinateur », « l'horloge » ; false for an aspirated h (« le hot-dog »).
    let elides: Bool

    init(_ singular: String, feminine: Bool, elides: Bool? = nil) {
        self.singular = singular
        self.isFeminine = feminine
        self.elides = elides ?? Self.startsWithVowelSound(singular)
    }

    /// « une tasse », « un livre ».
    var indefinite: String { (isFeminine ? "une " : "un ") + singular }

    /// « la tasse », « le livre », « l'ordinateur portable ».
    var definite: String {
        if elides { return "l'" + singular }
        return (isFeminine ? "la " : "le ") + singular
    }

    /// « La tasse ».
    var capitalizedDefinite: String { definite.capitalizedFirstLetter }

    /// « de tasse », « d'ordinateur portable » (after a negation: « je n'ai pas vu de tasse »).
    var partitiveAfterNegation: String { elides ? "d'" + singular : "de " + singular }

    /// Object pronoun before a consonant: « je ne la vois plus ».
    var objectPronoun: String { isFeminine ? "la" : "le" }

    /// Subject pronoun: « elle est à droite ».
    var subjectPronoun: String { isFeminine ? "elle" : "il" }

    /// Agrees a past participle with the noun: « déplacé » → « déplacée ».
    func agreed(_ participle: String) -> String { isFeminine ? participle + "e" : participle }

    private static func startsWithVowelSound(_ value: String) -> Bool {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        guard let first = folded.first else { return false }
        return "aeiouh".contains(first)
    }
}

/// French names for the 80 classes of the on-device detector, and the words people use
/// when they ask about them (« Où est mon mug ? »). Pure data: no camera, no storage.
enum VisionFrenchVocabulary {
    static let nouns: [String: VisionFrenchNoun] = [
        "person": VisionFrenchNoun("personne", feminine: true),
        "bicycle": VisionFrenchNoun("vélo", feminine: false),
        "car": VisionFrenchNoun("voiture", feminine: true),
        "motorbike": VisionFrenchNoun("moto", feminine: true),
        "aeroplane": VisionFrenchNoun("avion", feminine: false),
        "bus": VisionFrenchNoun("bus", feminine: false),
        "train": VisionFrenchNoun("train", feminine: false),
        "truck": VisionFrenchNoun("camion", feminine: false),
        "boat": VisionFrenchNoun("bateau", feminine: false),
        "traffic light": VisionFrenchNoun("feu de circulation", feminine: false),
        "fire hydrant": VisionFrenchNoun("bouche d'incendie", feminine: true),
        "stop sign": VisionFrenchNoun("panneau stop", feminine: false),
        "parking meter": VisionFrenchNoun("parcmètre", feminine: false),
        "bench": VisionFrenchNoun("banc", feminine: false),
        "bird": VisionFrenchNoun("oiseau", feminine: false),
        "cat": VisionFrenchNoun("chat", feminine: false),
        "dog": VisionFrenchNoun("chien", feminine: false),
        "horse": VisionFrenchNoun("cheval", feminine: false),
        "sheep": VisionFrenchNoun("mouton", feminine: false),
        "cow": VisionFrenchNoun("vache", feminine: true),
        "elephant": VisionFrenchNoun("éléphant", feminine: false),
        "bear": VisionFrenchNoun("ours", feminine: false),
        "zebra": VisionFrenchNoun("zèbre", feminine: false),
        "giraffe": VisionFrenchNoun("girafe", feminine: true),
        "backpack": VisionFrenchNoun("sac à dos", feminine: false),
        "umbrella": VisionFrenchNoun("parapluie", feminine: false),
        "handbag": VisionFrenchNoun("sac à main", feminine: false),
        "tie": VisionFrenchNoun("cravate", feminine: true),
        "suitcase": VisionFrenchNoun("valise", feminine: true),
        "frisbee": VisionFrenchNoun("frisbee", feminine: false),
        "skis": VisionFrenchNoun("paire de skis", feminine: true),
        "snowboard": VisionFrenchNoun("snowboard", feminine: false),
        "sports ball": VisionFrenchNoun("ballon", feminine: false),
        "kite": VisionFrenchNoun("cerf-volant", feminine: false),
        "baseball bat": VisionFrenchNoun("batte de baseball", feminine: true),
        "baseball glove": VisionFrenchNoun("gant de baseball", feminine: false),
        "skateboard": VisionFrenchNoun("skateboard", feminine: false),
        "surfboard": VisionFrenchNoun("planche de surf", feminine: true),
        "tennis racket": VisionFrenchNoun("raquette de tennis", feminine: true),
        "bottle": VisionFrenchNoun("bouteille", feminine: true),
        "wine glass": VisionFrenchNoun("verre à pied", feminine: false),
        "cup": VisionFrenchNoun("tasse", feminine: true),
        "fork": VisionFrenchNoun("fourchette", feminine: true),
        "knife": VisionFrenchNoun("couteau", feminine: false),
        "spoon": VisionFrenchNoun("cuillère", feminine: true),
        "bowl": VisionFrenchNoun("bol", feminine: false),
        "banana": VisionFrenchNoun("banane", feminine: true),
        "apple": VisionFrenchNoun("pomme", feminine: true),
        "sandwich": VisionFrenchNoun("sandwich", feminine: false),
        "orange": VisionFrenchNoun("orange", feminine: true),
        "broccoli": VisionFrenchNoun("brocoli", feminine: false),
        "carrot": VisionFrenchNoun("carotte", feminine: true),
        "hot dog": VisionFrenchNoun("hot-dog", feminine: false, elides: false),
        "pizza": VisionFrenchNoun("pizza", feminine: true),
        "donut": VisionFrenchNoun("beignet", feminine: false),
        "cake": VisionFrenchNoun("gâteau", feminine: false),
        "chair": VisionFrenchNoun("chaise", feminine: true),
        "sofa": VisionFrenchNoun("canapé", feminine: false),
        "pottedplant": VisionFrenchNoun("plante en pot", feminine: true),
        "bed": VisionFrenchNoun("lit", feminine: false),
        "diningtable": VisionFrenchNoun("table", feminine: true),
        "toilet": VisionFrenchNoun("cuvette de toilettes", feminine: true),
        "tvmonitor": VisionFrenchNoun("écran", feminine: false),
        "laptop": VisionFrenchNoun("ordinateur portable", feminine: false),
        "mouse": VisionFrenchNoun("souris", feminine: true),
        "remote": VisionFrenchNoun("télécommande", feminine: true),
        "keyboard": VisionFrenchNoun("clavier", feminine: false),
        "cell phone": VisionFrenchNoun("téléphone", feminine: false),
        "microwave": VisionFrenchNoun("micro-ondes", feminine: false),
        "oven": VisionFrenchNoun("four", feminine: false),
        "toaster": VisionFrenchNoun("grille-pain", feminine: false),
        "sink": VisionFrenchNoun("évier", feminine: false),
        "refrigerator": VisionFrenchNoun("réfrigérateur", feminine: false),
        "book": VisionFrenchNoun("livre", feminine: false),
        "clock": VisionFrenchNoun("horloge", feminine: true),
        "vase": VisionFrenchNoun("vase", feminine: false),
        "scissors": VisionFrenchNoun("paire de ciseaux", feminine: true),
        "teddy bear": VisionFrenchNoun("ours en peluche", feminine: false),
        "hair drier": VisionFrenchNoun("sèche-cheveux", feminine: false),
        "toothbrush": VisionFrenchNoun("brosse à dents", feminine: true)
    ]

    /// Everyday words for the same objects, written without accents (the speech text is
    /// folded the same way before matching).
    static let extraAliases: [String: [String]] = [
        "cup": ["mug", "gobelet", "verre", "tasse a cafe"],
        "wine glass": ["verre a vin"],
        "bottle": ["gourde", "flacon"],
        "book": ["bouquin", "cahier", "carnet"],
        "cell phone": ["portable", "smartphone", "iphone", "mobile"],
        "laptop": ["ordinateur", "ordi", "pc", "macbook"],
        "person": ["quelqu'un", "homme", "femme", "enfant"],
        "chair": ["fauteuil", "tabouret"],
        "diningtable": ["bureau"],
        "tvmonitor": ["television", "tele", "moniteur"],
        "bowl": ["saladier"],
        "spoon": ["cuiller"],
        "backpack": ["sac"],
        "handbag": ["sac"],
        "pottedplant": ["plante", "plante verte", "pot de fleur"],
        "clock": ["pendule", "reveil"],
        "scissors": ["ciseaux"],
        "teddy bear": ["peluche", "nounours", "doudou"],
        "cat": ["chaton"],
        "dog": ["chiot"],
        "sports ball": ["balle"]
    ]

    /// The French noun for a detector identifier; an unknown identifier keeps its own name.
    static func noun(for classIdentifier: String) -> VisionFrenchNoun {
        nouns[classIdentifier] ?? VisionFrenchNoun(classIdentifier, feminine: false)
    }

    /// Detector identifiers named in an already normalized French sentence, in the order
    /// they are spoken. « Où est la tasse sur la table » gives the cup first; a longer name
    /// wins over the shorter one it contains (« verre à pied » over « verre »).
    static func classesMentioned(in normalizedText: String) -> [String] {
        let padded = " \(normalizedText) "
        var hits: [(start: Int, end: Int, identifier: String)] = []
        for (identifier, words) in aliasIndex {
            for word in words {
                var searchStart = padded.startIndex
                while let range = padded.range(of: " \(word) ", range: searchStart..<padded.endIndex) {
                    let start = padded.distance(from: padded.startIndex, to: range.lowerBound)
                    hits.append((start: start, end: start + word.count + 2, identifier: identifier))
                    // Words share their separating space, so the next search starts on it.
                    searchStart = padded.index(before: range.upperBound)
                }
            }
        }
        hits.sort {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end > $1.end }
            return $0.identifier < $1.identifier
        }
        var coveredUntil = -1
        var acceptedRange: (start: Int, end: Int)?
        var result: [String] = []
        for hit in hits {
            // A hit inside an accepted longer name (« verre » in « verre à pied ») is skipped;
            // the next word legitimately starts on the previous word's trailing space, and one
            // word naming two classes (« sac ») keeps both.
            let sameWord = acceptedRange.map { $0.start == hit.start && $0.end == hit.end } ?? false
            if hit.start < coveredUntil - 1 && !sameWord { continue }
            coveredUntil = hit.end
            acceptedRange = (start: hit.start, end: hit.end)
            if !result.contains(hit.identifier) {
                result.append(hit.identifier)
            }
        }
        return result
    }

    /// « Trouve la tasse », « Cherche mon téléphone », « Où est la bouteille ? » : the detector
    /// class to look for, from an already normalized sentence. Nil without a search verb or a
    /// known object.
    static func findTarget(inNormalized normalizedText: String) -> String? {
        let padded = " \(normalizedText) "
        let searchWords = [
            " cherche ", " cherches ", " chercher ", " trouve ", " trouves ", " trouver ", " retrouve ",
            " localise ", " ou est ", " ou sont ", " ou se trouve ", " montre moi "
        ]
        guard searchWords.contains(where: { padded.contains($0) }) else { return nil }
        return classesMentioned(in: normalizedText).first
    }

    /// Normalized names per identifier, plurals included.
    static let aliasIndex: [String: [String]] = {
        var index: [String: [String]] = [:]
        for (identifier, noun) in nouns {
            var words = [noun.singular] + (extraAliases[identifier] ?? [])
            words = words.map { JarvisFrenchCommandRouter.normalize($0) }.filter { !$0.isEmpty }
            let plurals = words.compactMap { word -> String? in
                guard let last = word.last, last != "s", last != "x" else { return nil }
                return word + "s"
            }
            index[identifier] = Array(Set(words + plurals)).sorted()
        }
        return index
    }()
}

extension SpatialRegion {
    /// « de la gauche », « du centre », « de la droite ».
    var frenchFromPhrase: String {
        switch self {
        case .left: return "de la gauche"
        case .center: return "du centre"
        case .right: return "de la droite"
        }
    }

    /// « vers la gauche », « vers le centre », « vers la droite ».
    var frenchTowardPhrase: String {
        switch self {
        case .left: return "vers la gauche"
        case .center: return "vers le centre"
        case .right: return "vers la droite"
        }
    }
}
