import Foundation

/// Math notation, written and spoken. The local brain and the calculator write formulas
/// (x³/3 + C, √2, 1/2); the French voice would read « x trois barre oblique trois ». These
/// helpers turn LaTeX into plain notation for the screen, and notation into words for
/// the voice. They only touch clear math patterns: « Wi-Fi », « km/h », dates and times
/// are left as they are.
enum JarvisSpokenMath {
    private static let superscriptDigits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]

    static func superscript(_ value: Int) -> String {
        let digits = String(abs(value)).compactMap { character -> Character? in
            guard let digit = character.wholeNumberValue else { return nil }
            return superscriptDigits[digit]
        }
        return (value < 0 ? "⁻" : "") + String(digits)
    }

    // MARK: Screen: LaTeX → plain notation

    /// Turns the LaTeX a small model sometimes writes (\frac{x^3}{3}, \int, $…$) into plain
    /// notation (x³/3, ∫), and small integer exponents into superscripts (x^2 → x²).
    static func plainMath(_ text: String) -> String {
        var value = text
        if value.contains("\\") || value.contains("$") {
            for token in ["$$", "$", "\\(", "\\)", "\\[", "\\]", "\\left", "\\right", "\\displaystyle"] {
                value = value.replacingOccurrences(of: token, with: "")
            }
            var previous = ""
            while previous != value {
                previous = value
                value = value.replacingRegex(#"\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}"#) { wrap($0[1]) + "/" + wrap($0[2]) }
                value = value.replacingRegex(#"\\sqrt\{([^{}]*)\}"#) { "√" + wrap($0[1]) }
                value = value.replacingRegex(#"\\(?:text|mathrm|mathit|operatorname)\{([^{}]*)\}"#) { $0[1] }
                value = value.replacingRegex(#"\^\{([^{}]*)\}"#) { "^" + wrap($0[1]) }
                value = value.replacingRegex(#"_\{([^{}]*)\}"#) { "_" + $0[1] }
            }
            let symbols: [(String, String)] = [
                ("\\int", "∫"), ("\\cdot", "×"), ("\\times", "×"), ("\\div", "÷"), ("\\pi", "π"), ("\\infty", "∞"),
                ("\\leq", "≤"), ("\\geq", "≥"), ("\\neq", "≠"), ("\\le", "≤"), ("\\ge", "≥"), ("\\ne", "≠"),
                ("\\approx", "≈"), ("\\pm", "±"), ("\\sin", "sin"), ("\\cos", "cos"), ("\\tan", "tan"),
                ("\\ln", "ln"), ("\\log", "log"), ("\\exp", "exp"), ("\\,", " "), ("\\;", " "), ("\\!", ""), ("\\quad", " "),
            ]
            for (latex, plain) in symbols {
                value = value.replacingOccurrences(of: latex, with: plain)
            }
            value = value.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
            value = value.replacingOccurrences(of: "\\", with: "")
        }
        value = value.replacingRegex(#"\^\((-?\d{1,2})\)|\^(-?\d{1,2})(?!\d|[.,]\d)"#) { groups in
            let digits = groups[1].isEmpty ? groups[2] : groups[1]
            return Int(digits).map(superscript) ?? groups[0]
        }
        return value
    }

    private static func wrap(_ part: String) -> String {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        let isSingle = trimmed.range(of: #"^[0-9A-Za-zπ.,⁰¹²³⁴⁵⁶⁷⁸⁹^]+$"#, options: .regularExpression) != nil
        return isSingle ? trimmed : "(" + trimmed + ")"
    }

    // MARK: Voice: notation → French words

    /// Words for the voice: x² → « x au carré », x³/3 → « x au cube sur 3 », √2 →
    /// « racine carrée de 2 », 3.5 → « 3,5 ». Plain sentences come back unchanged.
    static func speakable(_ text: String) -> String {
        var value = text
        value = value.replacingRegex(#"\|([^|]{1,24})\|"#) { " valeur absolue de " + $0[1] }
        value = value.replacingRegex(#"[⁰¹²³⁴⁵⁶⁷⁸⁹⁻ˣ]+"#) { groups in
            exponentWords(groups[0].map(plainExponentCharacter).joined())
        }
        value = value.replacingRegex(#"\^\s*\(?\s*(-?[0-9a-z]+)\s*\)?"#) { exponentWords($0[1]) }
        let symbols: [(String, String)] = [
            ("√", " racine carrée de "), ("∛", " racine cubique de "), ("∫", " intégrale de "), ("π", " pi "),
            ("∞", " l'infini "), ("≈", " égale environ "), ("≤", " inférieur ou égal à "), ("≥", " supérieur ou égal à "),
            ("≠", " différent de "), ("×", " fois "), ("·", " fois "), ("÷", " divisé par "), ("±", " plus ou moins "),
            ("′", " prime "), ("=", " égale "), ("−", " moins "), ("+", " plus "),
        ]
        for (symbol, words) in symbols where value.contains(symbol) {
            value = value.replacingOccurrences(of: symbol, with: words)
        }
        // « * » and « / » between two operands; a slash needs a digit, a closing
        // parenthesis or an exponent on one side, so « km/h » and « jetons/s » stay.
        value = value.replacingRegex(#"([0-9a-zA-Z)])\s*\*\s*(?=[0-9a-zA-Z(])"#, with: "$1 fois ")
        value = value.replacingRegex(#"(\d+/\d+/\d+)|([0-9)]|carré|cube)\s*/\s*(?=[0-9a-zA-Z(])|([a-zA-Z])\s*/\s*(?=[0-9(])"#) { groups in
            if !groups[1].isEmpty { return groups[1] } // a date: 25/11/2026
            return (groups[2].isEmpty ? groups[3] : groups[2]) + " sur "
        }
        // A spaced hyphen between operands is a minus: « x² - 1 », « 5 - 3 ».
        value = value.replacingRegex(#"(\b[a-zA-Z]|\d|\)|carré|cube)\s+-\s+(?=[0-9(]|[a-zA-Z]\b)"#, with: "$1 moins ")
        value = value.replacingRegex(#"(^|[=(]|égale)\s*-(?=\s?[0-9a-z(])"#, with: "$1 moins ")
        let functions: [(String, String)] = [
            (#"\bsin\b\s*"#, "sinus de "), (#"\bcos\b\s*"#, "cosinus de "), (#"\btan\b\s*"#, "tangente de "),
            (#"\bln\b\s*"#, "logarithme népérien de "), (#"\bexp\b\s*"#, "exponentielle de "), (#"\blog\b\s*"#, "logarithme de "),
        ]
        for (pattern, words) in functions {
            value = value.replacingRegex(pattern, with: words)
        }
        value = value.replacingRegex(#"\bd([xyzt])\b"#, with: "d $1")
        value = value.replacingRegex(#"(\d)([xyztn])\b"#, with: "$1 $2")
        value = value.replacingRegex(#"(\d)\.(\d)"#, with: "$1,$2")
        value = value.replacingRegex(#"[ \t]{2,}"#, with: " ")
        value = value.replacingRegex(#" ([.,;!?])(?=\s|$)"#, with: "$1")
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func plainExponentCharacter(_ character: Character) -> String {
        if let index = superscriptDigits.firstIndex(of: character) { return String(index) }
        if character == "⁻" { return "-" }
        if character == "ˣ" { return "x" }
        return ""
    }

    private static func exponentWords(_ exponent: String) -> String {
        switch exponent {
        case "2": return " au carré"
        case "3": return " au cube"
        default:
            if exponent.hasPrefix("-") { return " puissance moins " + exponent.dropFirst() }
            return " puissance " + exponent
        }
    }
}

extension String {
    /// Replaces every match of `pattern` with a value computed from the match's groups
    /// (group 0 is the whole match; a group that did not take part is "").
    func replacingRegex(_ pattern: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let text = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: text.length))
        guard !matches.isEmpty else { return self }
        var result = ""
        var cursor = 0
        for match in matches {
            result += text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : text.substring(with: range)
            }
            result += transform(groups)
            cursor = match.range.location + match.range.length
        }
        result += text.substring(from: cursor)
        return result
    }

    /// Replaces every match of `pattern` with `template` ($1 for the first group).
    func replacingRegex(_ pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        return regex.stringByReplacingMatches(in: self, range: NSRange(location: 0, length: (self as NSString).length), withTemplate: template)
    }
}
