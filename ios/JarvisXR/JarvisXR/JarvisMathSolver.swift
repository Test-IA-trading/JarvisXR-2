import Foundation

/// Exact rational number for calculus coefficients (x³/3, 2/3…). An operation that would
/// overflow returns nil; the solver then leaves the question to the local brain.
struct JarvisRational: Equatable {
    let numerator: Int
    let denominator: Int

    init?(_ numerator: Int, _ denominator: Int = 1) {
        guard denominator != 0 else { return nil }
        let divisor = max(JarvisRational.gcd(abs(numerator), abs(denominator)), 1)
        let sign = denominator < 0 ? -1 : 1
        self.numerator = sign * (numerator / divisor)
        self.denominator = abs(denominator) / divisor
    }

    /// « 2.25 » → 9/4.
    init?(decimal text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts[0].count <= 9, let whole = Int(parts[0]) else { return nil }
        guard parts.count == 2 else {
            self.init(whole)
            return
        }
        let fraction = parts[1]
        guard !fraction.isEmpty, fraction.count <= 6, let digits = Int(fraction) else { return nil }
        var scale = 1
        for _ in 0..<fraction.count { scale *= 10 }
        self.init(whole * scale + digits, scale)
    }

    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    static let zero = JarvisRational(0)!
    static let one = JarvisRational(1)!

    var isZero: Bool { numerator == 0 }
    var isInteger: Bool { denominator == 1 }
    var doubleValue: Double { Double(numerator) / Double(denominator) }
    var negated: JarvisRational { JarvisRational(-numerator, denominator)! }

    func adding(_ other: JarvisRational) -> JarvisRational? {
        let (left, overflow1) = numerator.multipliedReportingOverflow(by: other.denominator)
        let (right, overflow2) = other.numerator.multipliedReportingOverflow(by: denominator)
        let (bottom, overflow3) = denominator.multipliedReportingOverflow(by: other.denominator)
        let (top, overflow4) = left.addingReportingOverflow(right)
        guard !(overflow1 || overflow2 || overflow3 || overflow4) else { return nil }
        return JarvisRational(top, bottom)
    }

    func subtracting(_ other: JarvisRational) -> JarvisRational? { adding(other.negated) }

    func multiplied(by other: JarvisRational) -> JarvisRational? {
        let (top, overflow1) = numerator.multipliedReportingOverflow(by: other.numerator)
        let (bottom, overflow2) = denominator.multipliedReportingOverflow(by: other.denominator)
        guard !(overflow1 || overflow2) else { return nil }
        return JarvisRational(top, bottom)
    }

    func divided(by other: JarvisRational) -> JarvisRational? {
        guard let inverse = JarvisRational(other.denominator, other.numerator) else { return nil }
        return multiplied(by: inverse)
    }

    func raised(to exponent: Int) -> JarvisRational? {
        guard exponent >= 0 else {
            return JarvisRational.one.divided(by: self)?.raised(to: -exponent)
        }
        var result = JarvisRational.one
        for _ in 0..<exponent {
            guard let next = result.multiplied(by: self) else { return nil }
            result = next
        }
        return result
    }

    /// 3, 1/3, −2/5.
    var text: String {
        let sign = numerator < 0 ? "−" : ""
        let top = abs(numerator)
        return denominator == 1 ? "\(sign)\(top)" : "\(sign)\(top)/\(denominator)"
    }
}

/// Exact answers to calculations, so Jarvis never approximates 128 × 46 the way a small
/// language model can:
/// - arithmetic said in French or typed: plus, moins, fois, divisé par, puissance, au carré,
///   racine carrée, pour cent de, factorielle, with number words (« vingt-deux ») and
///   French decimals (« 3,5 »);
/// - integrals (with or without bounds) and derivatives of sums of terms in x: xⁿ, sin x,
///   cos x, eˣ, 1/x, and ln x for derivatives.
/// Whatever it cannot read completely returns nil and goes to the local brain.
enum JarvisMathSolver {
    struct Answer: Equatable {
        let spoken: String
        let display: String
    }

    static func answer(to original: String) -> Answer? {
        let text = prepare(original)
        guard !text.isEmpty else { return nil }
        if hasCalculusWord(text) {
            return calculus(text)
        }
        return arithmetic(text)
    }

    // MARK: Text preparation

    /// Lowercase, accents folded, math symbols in ASCII, decimals with a point, number
    /// words as digits: « Combien font vingt-deux fois 3,5 ? » → « combien font 22 fois 3.5 ».
    static func prepare(_ original: String) -> String {
        var text = original
            .replacingOccurrences(of: "’", with: "'")
            .replacingRegex(#"[⁰¹²³⁴⁵⁶⁷⁸⁹⁻ˣ]+"#) { groups in
                "^(" + groups[0].map(exponentCharacter).joined() + ")"
            }
        let symbols: [(String, String)] = [
            ("−", "-"), ("×", " * "), ("·", " * "), ("⋅", " * "), ("÷", " / "), ("√", " racine de "),
            ("∛", " racine cubique de "), ("π", " pi "), ("∫", " integrale "), ("=", " egale "),
            ("\u{00A0}", " "), ("\u{202F}", " "),
        ]
        for (symbol, replacement) in symbols {
            text = text.replacingOccurrences(of: symbol, with: replacement)
        }
        text = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
        text = text.replacingRegex(#"(\d),(\d)"#, with: "$1.$2")
        var previous = ""
        while previous != text {
            previous = text
            text = text.replacingRegex(#"(\d) (\d{3})(?!\d)"#, with: "$1$2")
        }
        text = text.replacingRegex(#"([a-z])-(?=[a-z])"#, with: "$1 ")
        text = text.replacingRegex(#"\b(l|d|j|m|n|s|t|c|qu)'"#, with: "$1' ")
        text = text.replacingRegex(#"[?!;:«»"…]"#, with: " ")
        text = text.replacingRegex(#"(?<!\d)[.,]|[.,](?!\d)"#, with: " ")
        text = text.replacingRegex(#"\s+"#, with: " ").trimmingCharacters(in: .whitespaces)
        // « pour cent » before the number words, or « cent » would become 100.
        text = text.replacingRegex(#"\bpour\s?cents?\b"#, with: "%")
        text = numbersFromWords(text)
        return text.replacingRegex(#"(\d+) virgule (\d+)"#, with: "$1.$2")
    }

    private static func exponentCharacter(_ character: Character) -> String {
        let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        if let index = digits.firstIndex(of: character) { return String(index) }
        if character == "⁻" { return "-" }
        if character == "ˣ" { return "x" }
        return ""
    }

    private static let numberWords: [String: Int] = [
        "zero": 0, "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9,
        "dix": 10, "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16,
        "vingt": 20, "vingts": 20, "trente": 30, "quarante": 40, "cinquante": 50, "soixante": 60,
        "cent": 100, "cents": 100, "mille": 1000, "million": 1_000_000, "millions": 1_000_000,
    ]

    /// Words after which « un » or « une » is a number rather than an article.
    private static let wordsAfterNumbers: Set<String> = [
        "plus", "moins", "fois", "divise", "divises", "multiplie", "multiplies", "sur", "puissance", "exposant",
        "au", "x", "et", "pour", "virgule", "a",
    ]

    /// « vingt-deux » → 22, « quatre-vingt-dix-sept » → 97, « deux mille vingt-six » → 2026.
    static func numbersFromWords(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        var output: [String] = []
        var index = 0
        while index < words.count {
            guard numberWords[words[index]] != nil else {
                output.append(words[index])
                index += 1
                continue
            }
            var end = index
            var run: [String] = []
            while end < words.count {
                let word = words[end]
                if numberWords[word] != nil {
                    run.append(word)
                    end += 1
                } else if word == "et", !run.isEmpty, end + 1 < words.count, ["un", "une", "onze"].contains(words[end + 1]) {
                    end += 1
                } else {
                    break
                }
            }
            // A lone « un » or « une » before an ordinary word is an article: « une intégrale ».
            if run.count == 1, run[0] == "un" || run[0] == "une", end < words.count, !wordsAfterNumbers.contains(words[end]) {
                output.append(run[0])
                index = end
                continue
            }
            output.append(String(value(ofNumberWords: run)))
            index = end
        }
        return output.joined(separator: " ")
    }

    static func value(ofNumberWords words: [String]) -> Int {
        var total = 0
        var current = 0
        var previous = 0
        for word in words {
            let value = numberWords[word] ?? 0
            if value == 100 {
                current = (current == 0 ? 1 : current) * 100
            } else if value >= 1000 {
                total += (current == 0 ? 1 : current) * value
                current = 0
            } else if value == 20, previous == 4, current % 100 >= 4 {
                current += 76 // quatre-vingt: 4 + 76 = 80
            } else {
                current += value
            }
            previous = value
        }
        return total + current
    }

    /// « 12 », « 3.5 » — not « nan » or « inf », which Double() would also accept.
    static func isNumberToken(_ token: String) -> Bool {
        guard let first = token.first, first.isASCII, first.isNumber else { return false }
        return Double(token) != nil
    }

    static func tokenize(_ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?|[a-z']+|[+\-*/^()!%]|\S"#) else { return nil }
        let source = text as NSString
        var tokens: [String] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let token = source.substring(with: match.range)
            guard token.range(of: #"^(?:\d+(?:\.\d+)?|[a-z']+|[+\-*/^()!%])$"#, options: .regularExpression) != nil else { return nil }
            tokens.append(token)
        }
        return tokens
    }

    // MARK: Number formatting

    /// « 3.5 » → « 3,5 », « 12345 » → « 12 345 ».
    static func writtenNumber(_ token: String) -> String {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let whole = grouped(parts[0])
        return parts.count > 1 ? whole + "," + parts[1] : whole
    }

    /// Groups of three digits with a narrow no-break space, from five digits on.
    static func grouped(_ digits: String) -> String {
        guard digits.count > 4 else { return digits }
        var result = ""
        for (offset, character) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { result.append("\u{202F}") }
            result.append(character)
        }
        return result
    }

    /// 0,3333: at most `decimals` digits after the comma, trailing zeros removed.
    static func decimalText(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text.replacingOccurrences(of: "-", with: "−").replacingOccurrences(of: ".", with: ",")
    }

    /// Result for the screen and for the voice, and whether it is exact.
    static func resultText(_ value: Double) -> (display: String, spoken: String, exact: Bool) {
        let magnitude = abs(value)
        if magnitude < 1e15, value == value.rounded() {
            let digits = String(Int64(magnitude))
            let negative = value < 0
            return ((negative ? "−" : "") + grouped(digits), (negative ? "moins " : "") + digits, true)
        }
        if magnitude >= 1e15 || magnitude < 1e-4 {
            let exponent = Int(floor(log10(magnitude)))
            let mantissa = value / pow(10, Double(exponent))
            let text = decimalText(mantissa, decimals: 4) + " × 10" + JarvisSpokenMath.superscript(exponent)
            return (text, text, false)
        }
        let integerDigits = max(1, Int(floor(log10(magnitude))) + 1)
        let decimals = max(0, 6 - integerDigits)
        let display = decimalText(value, decimals: decimals)
        let spoken = decimalText(value, decimals: min(decimals, 3))
        let shown = Double(display.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")) ?? value
        return (display, spoken, abs(shown - value) <= 1e-12 * max(1, magnitude))
    }

    static func approximate(_ value: Double) -> (display: String, spoken: String) {
        (decimalText(value, decimals: 4), decimalText(value, decimals: 3))
    }

    // MARK: Arithmetic

    indirect enum MathExpression {
        case number(Double, String)
        case pi
        case negative(MathExpression)
        case binary(String, MathExpression, MathExpression)
        case squareRoot(MathExpression)
        case cubeRoot(MathExpression)
        case factorial(MathExpression)
        case percent(MathExpression)
        case group(MathExpression)
    }

    enum Failure: Error {
        case divisionByZero
        case negativeRoot
        case undefined
    }

    private static let arithmeticWords: [(String, String)] = [
        (#"\bmultiplie(?:s|r)? par\b"#, " * "),
        (#"\bdivise(?:s|r)? par\b"#, " / "),
        (#"\ba la puissance(?:\s+de)?\b"#, " ^ "),
        (#"\b(?:puissance|exposant)(?:\s+de)?\b"#, " ^ "),
        (#"\bau carree?\b"#, " ^ 2 "),
        (#"\bau cube\b"#, " ^ 3 "),
        (#"([0-9)])\s+carree?\b"#, "$1 ^ 2 "),
        (#"([0-9)])\s+cube\b"#, "$1 ^ 3 "),
        (#"\b(?:la\s+)?racine\s+cubique(?:\s+de)?\b"#, " cbrt "),
        (#"\b(?:la\s+)?racine(?:\s+carree?)?(?:\s+de)?\b"#, " sqrt "),
        (#"(?:\bpour\s?cents?|%)\s*(?:de\b|d')"#, " pourcentde "),
        (#"\bpour\s?cents?\b"#, " % "),
        (#"\bfactorielle\s+de\b"#, " fact "),
        (#"\bfactorielle\b"#, " ! "),
        (#"\bplus\b"#, " + "),
        (#"\bmoins\b"#, " - "),
        (#"\bfois\b"#, " * "),
    ]

    /// Words around a calculation that carry no math: « Combien font… », « Calcule… s'il te plaît ».
    private static let fillers: Set<String> = [
        "combien", "font", "fait", "ca", "calcule", "calculez", "calculer", "calcul", "le", "la", "les", "l'", "de", "d'",
        "du", "des", "resultat", "quel", "quelle", "est", "c'", "egale", "egal", "egalent", "vaut", "valent", "donne",
        "donnent", "fais", "faites", "faire", "moi", "m'", "t'", "s'", "il", "te", "toi", "vous", "plait", "svp", "stp",
        "jarvis", "dis", "dites", "peux", "peut", "pourrais", "tu", "me", "alors", "et", "un", "une", "exactement", "qu'",
        "que", "quoi", "ce", "cela", "ok", "hey", "eh",
    ]
    private static let operatorTokens: Set<String> = ["+", "-", "*", "/", "^", "!", "%", "pourcentde", "sqrt", "cbrt", "fact"]

    static func arithmetic(_ prepared: String) -> Answer? {
        guard prepared.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        var text = prepared
        for (pattern, replacement) in arithmeticWords {
            text = text.replacingRegex(pattern, with: replacement)
        }
        guard var tokens = tokenize(text) else { return nil }
        // Words that are operators only between two numbers: « 12 sur 4 », « 3 x 4 », « 2 et 2 ».
        for index in tokens.indices where ["sur", "x", "et"].contains(tokens[index]) {
            guard index > 0, index + 1 < tokens.count else { continue }
            let before = tokens[index - 1]
            let after = tokens[index + 1]
            let leftOperand = isNumberToken(before) || [")", "pi", "!", "%"].contains(before)
            let rightOperand = isNumberToken(after) || ["(", "pi", "sqrt", "cbrt", "-"].contains(after)
            guard leftOperand, rightOperand else { continue }
            tokens[index] = tokens[index] == "sur" ? "/" : tokens[index] == "x" ? "*" : "+"
        }
        tokens.removeAll { fillers.contains($0) }
        guard tokens.contains(where: { operatorTokens.contains($0) }) else { return nil }
        var parser = ExpressionParser(tokens: tokens)
        guard let expression = parser.parseExpression(), parser.isAtEnd else { return nil }

        let display = displayText(expression)
        let spoken = spokenText(expression).capitalizedFirstLetter
        do {
            let value = try evaluate(expression)
            let result = resultText(value)
            if result.exact {
                return Answer(spoken: "\(spoken) égale \(result.spoken).", display: "\(display) = \(result.display)")
            }
            return Answer(spoken: "\(spoken) égale environ \(result.spoken).", display: "\(display) ≈ \(result.display)")
        } catch Failure.divisionByZero {
            return Answer(spoken: "La division par zéro n'est pas définie.", display: "\(display) : la division par zéro n'est pas définie.")
        } catch Failure.negativeRoot {
            return Answer(spoken: "La racine carrée d'un nombre négatif n'existe pas dans les nombres réels.", display: "\(display) : pas de racine carrée réelle d'un nombre négatif.")
        } catch {
            return Answer(spoken: "Ce résultat est trop grand ou n'est pas défini.", display: "\(display) : résultat trop grand ou non défini.")
        }
    }

    private struct ExpressionParser {
        let tokens: [String]
        var index = 0

        init(tokens: [String]) {
            self.tokens = tokens
        }

        var isAtEnd: Bool { index >= tokens.count }
        var peek: String? { index < tokens.count ? tokens[index] : nil }

        mutating func parseExpression() -> MathExpression? {
            guard var left = parseTerm() else { return nil }
            while let operation = peek, operation == "+" || operation == "-" {
                index += 1
                guard let right = parseTerm() else { return nil }
                left = .binary(operation, left, right)
            }
            return left
        }

        mutating func parseTerm() -> MathExpression? {
            guard var left = parseUnary() else { return nil }
            while let operation = peek {
                if operation == "*" || operation == "/" || operation == "pourcentde" {
                    index += 1
                    guard let right = parseUnary() else { return nil }
                    left = .binary(operation, left, right)
                } else if ["(", "pi", "sqrt", "cbrt"].contains(operation) {
                    guard let right = parseUnary() else { return nil }
                    left = .binary("*", left, right)
                } else {
                    break
                }
            }
            return left
        }

        mutating func parseUnary() -> MathExpression? {
            if peek == "-" {
                index += 1
                guard let inner = parseUnary() else { return nil }
                return MathExpression.negative(inner)
            }
            if peek == "+" {
                index += 1
                return parseUnary()
            }
            return parsePower()
        }

        mutating func parsePower() -> MathExpression? {
            guard let base = parsePostfix() else { return nil }
            guard peek == "^" else { return base }
            index += 1
            guard let exponent = parseUnary() else { return nil }
            return MathExpression.binary("^", base, exponent)
        }

        mutating func parsePostfix() -> MathExpression? {
            guard var value = parsePrimary() else { return nil }
            while let operation = peek, operation == "!" || operation == "%" {
                index += 1
                value = operation == "!" ? MathExpression.factorial(value) : MathExpression.percent(value)
            }
            return value
        }

        mutating func parsePrimary() -> MathExpression? {
            guard let token = peek else { return nil }
            index += 1
            if JarvisMathSolver.isNumberToken(token), let number = Double(token) {
                return MathExpression.number(number, JarvisMathSolver.writtenNumber(token))
            }
            switch token {
            case "pi":
                return MathExpression.pi
            case "(":
                guard let inner = parseExpression(), peek == ")" else { return nil }
                index += 1
                return MathExpression.group(inner)
            case "sqrt":
                guard let inner = parseUnary() else { return nil }
                return MathExpression.squareRoot(inner)
            case "cbrt":
                guard let inner = parseUnary() else { return nil }
                return MathExpression.cubeRoot(inner)
            case "fact":
                guard let inner = parseUnary() else { return nil }
                return MathExpression.factorial(inner)
            default:
                return nil
            }
        }
    }

    static func evaluate(_ expression: MathExpression) throws -> Double {
        switch expression {
        case .number(let value, _):
            return value
        case .pi:
            return Double.pi
        case .negative(let inner):
            return try -evaluate(inner)
        case .group(let inner):
            return try evaluate(inner)
        case .squareRoot(let inner):
            let value = try evaluate(inner)
            guard value >= 0 else { throw Failure.negativeRoot }
            return value.squareRoot()
        case .cubeRoot(let inner):
            return try cbrt(evaluate(inner))
        case .factorial(let inner):
            let value = try evaluate(inner)
            guard value >= 0, value == value.rounded(), value <= 170 else { throw Failure.undefined }
            return value < 2 ? 1 : (2...Int(value)).reduce(1.0) { $0 * Double($1) }
        case .percent(let inner):
            return try evaluate(inner) / 100
        case .binary(let operation, let left, let right):
            let a = try evaluate(left)
            let b = try evaluate(right)
            let result: Double
            switch operation {
            case "+": result = a + b
            case "-": result = a - b
            case "*": result = a * b
            case "/":
                guard b != 0 else { throw Failure.divisionByZero }
                result = a / b
            case "^": result = pow(a, b)
            case "pourcentde": result = a / 100 * b
            default: throw Failure.undefined
            }
            guard result.isFinite else { throw Failure.undefined }
            return result
        }
    }

    static func displayText(_ expression: MathExpression) -> String {
        switch expression {
        case .number(_, let written): return written
        case .pi: return "π"
        case .negative(let inner): return "−" + displayText(inner)
        case .group(let inner): return "(" + displayText(inner) + ")"
        case .squareRoot(let inner): return "√" + displayText(inner)
        case .cubeRoot(let inner): return "∛" + displayText(inner)
        case .factorial(let inner): return displayText(inner) + "!"
        case .percent(let inner): return displayText(inner) + " %"
        case .binary(let operation, let left, let right):
            switch operation {
            case "+": return displayText(left) + " + " + displayText(right)
            case "-": return displayText(left) + " − " + displayText(right)
            case "*": return displayText(left) + " × " + displayText(right)
            case "/": return displayText(left) + " ÷ " + displayText(right)
            case "^":
                if case .number(let value, _) = right, value >= 0, value < 100, value == value.rounded() {
                    return displayText(left) + JarvisSpokenMath.superscript(Int(value))
                }
                return displayText(left) + "^" + displayText(right)
            case "pourcentde": return displayText(left) + " % de " + displayText(right)
            default: return displayText(left) + " " + operation + " " + displayText(right)
            }
        }
    }

    static func spokenText(_ expression: MathExpression) -> String {
        switch expression {
        case .number(_, let written): return written.replacingOccurrences(of: "\u{202F}", with: "")
        case .pi: return "pi"
        case .negative(let inner): return "moins " + spokenText(inner)
        case .group(let inner): return spokenText(inner)
        case .squareRoot(let inner): return "racine carrée de " + spokenText(inner)
        case .cubeRoot(let inner): return "racine cubique de " + spokenText(inner)
        case .factorial(let inner): return spokenText(inner) + " factorielle"
        case .percent(let inner): return spokenText(inner) + " pour cent"
        case .binary(let operation, let left, let right):
            switch operation {
            case "+": return spokenText(left) + " plus " + spokenText(right)
            case "-": return spokenText(left) + " moins " + spokenText(right)
            case "*": return spokenText(left) + " fois " + spokenText(right)
            case "/": return spokenText(left) + " divisé par " + spokenText(right)
            case "^":
                if case .number(let value, _) = right, value == 2 { return spokenText(left) + " au carré" }
                if case .number(let value, _) = right, value == 3 { return spokenText(left) + " au cube" }
                return spokenText(left) + " puissance " + spokenText(right)
            case "pourcentde": return spokenText(left) + " pour cent de " + spokenText(right)
            default: return spokenText(left) + " " + spokenText(right)
            }
        }
    }

    // MARK: Integrals and derivatives

    enum Basis: Hashable {
        case power(Int)
        case sine
        case cosine
        case exponential
        case logarithm
        case absLogarithm

        /// Display order: powers from the highest, then sin, cos, eˣ, ln.
        var order: (Int, Int) {
            switch self {
            case .power(let exponent): return (0, -exponent)
            case .sine: return (1, 0)
            case .cosine: return (2, 0)
            case .exponential: return (3, 0)
            case .logarithm: return (4, 0)
            case .absLogarithm: return (5, 0)
            }
        }
    }

    struct Term: Equatable {
        var coefficient: JarvisRational
        var basis: Basis
    }

    private static let integralPattern = #"\b(?:integrales?|integral|integrer|integre|integrez|primitives?)\b"#
    private static let derivativePattern = #"\b(?:derivees?|derive|deriver|derivez)\b"#
    private static let boundPattern = #"((?:moins |-)?(?:\d+(?:\.\d+)?|pi))"#

    static func hasCalculusWord(_ text: String) -> Bool {
        text.range(of: integralPattern, options: .regularExpression) != nil
            || text.range(of: derivativePattern, options: .regularExpression) != nil
    }

    struct Bound {
        let value: Double
        let exact: JarvisRational?
        let display: String

        init?(_ text: String) {
            var body = text.trimmingCharacters(in: .whitespaces)
            var negative = false
            if body.hasPrefix("moins ") {
                negative = true
                body = String(body.dropFirst(6))
            } else if body.hasPrefix("-") {
                negative = true
                body = String(body.dropFirst())
            }
            if body == "pi" {
                value = negative ? -Double.pi : Double.pi
                exact = nil
                display = (negative ? "−" : "") + "π"
                return
            }
            guard let rational = JarvisRational(decimal: body) else { return nil }
            let signed = negative ? rational.negated : rational
            value = signed.doubleValue
            exact = signed
            display = (negative ? "−" : "") + JarvisMathSolver.writtenNumber(body)
        }
    }

    static func calculus(_ text: String) -> Answer? {
        let integralRange = text.range(of: integralPattern, options: .regularExpression)
        let derivativeRange = text.range(of: derivativePattern, options: .regularExpression)
        let isIntegral: Bool
        let keyword: Range<String.Index>
        switch (integralRange, derivativeRange) {
        case (let range?, nil):
            isIntegral = true
            keyword = range
        case (nil, let range?):
            isIntegral = false
            keyword = range
        default:
            return nil
        }
        var rest = String(text[keyword.upperBound...])
        rest = rest.replacingRegex(#"\s*(?:s' il (?:te|vous) plait|svp|stp|jarvis)\s*$"#, with: "")
        rest = rest.replacingRegex(#"\s*par rapport (?:a|au) x\s*$"#, with: "")
        rest = rest.replacingRegex(#"\s*d\s*x\s*$"#, with: "")
        rest = rest.trimmingCharacters(in: .whitespaces)

        var lower: Bound?
        var upper: Bound?
        var expression = rest
        if isIntegral {
            let leading = #"^(?:(?:de|d'|du|entre)\s+)?"# + boundPattern + #"\s+(?:a|et|jusqu'a)\s+"# + boundPattern + #"\s+(?:(?:de|d'|du)\s*)?(.+)$"#
            let trailing = #"^(.+?)\s+(?:de|entre)\s+"# + boundPattern + #"\s+(?:a|et|jusqu'a)\s+"# + boundPattern + #"$"#
            if let groups = rest.regexGroups(leading), let a = Bound(groups[1]), let b = Bound(groups[2]) {
                lower = a
                upper = b
                expression = groups[3]
            } else if let groups = rest.regexGroups(trailing), let a = Bound(groups[2]), let b = Bound(groups[3]) {
                lower = a
                upper = b
                expression = groups[1]
            }
        }
        guard let terms = parseFunction(expression), !terms.isEmpty else { return nil }
        let function = format(terms)

        guard isIntegral else {
            guard let derived = derivative(of: terms) else { return nil }
            let result = format(derived)
            return Answer(spoken: "La dérivée de \(function) est \(result).", display: "Dérivée de \(function) : \(result)")
        }
        guard let primitive = integral(of: terms) else { return nil }
        let primitiveText = format(primitive)
        guard let lower, let upper else {
            let integrand = terms.count > 1 ? "(\(function))" : function
            return Answer(
                spoken: "Une primitive de \(function) est \(primitiveText) + C, où C est une constante.",
                display: "∫ \(integrand) dx = \(primitiveText) + C"
            )
        }
        return definite(terms, primitive: primitive, function: function, primitiveText: primitiveText, lower: lower, upper: upper)
    }

    private static let functionWords: [(String, String)] = [
        (#"\bmultiplie(?:s|r)? par\b"#, " * "),
        (#"\bdivise(?:s|r)? par\b"#, " / "),
        (#"\ba la puissance\b"#, " ^ "),
        (#"\b(?:puissance|exposant)\b"#, " ^ "),
        (#"\bau carree?\b"#, " ^ 2 "),
        (#"\bau cube\b"#, " ^ 3 "),
        (#"([0-9x)])\s+carree?\b"#, "$1 ^ 2 "),
        (#"([0-9x)])\s+cube\b"#, "$1 ^ 3 "),
        (#"\bplus\b"#, " + "),
        (#"\bmoins\b"#, " - "),
        (#"\bfois\b"#, " * "),
        (#"\bsur\b"#, " / "),
        (#"\b(?:sinus|sin)(?:\s+de)?\b"#, " sin "),
        (#"\b(?:cosinus|cos)(?:\s+de)?\b"#, " cos "),
        (#"\be\s*\^\s*\(?\s*x\s*\)?"#, " exp x "),
        (#"\b(?:exponentielle|exp)(?:\s+de)?\b"#, " exp "),
        (#"\b(?:logarithme neperien|logarithme|ln|log)(?:\s+de)?\b"#, " ln "),
    ]

    /// « de la fonction 3 x au carré plus 2 x » → 3x² + 2x, or nil when any part is not a
    /// term the solver knows.
    static func parseFunction(_ raw: String) -> [Term]? {
        var text = raw
        text = text.replacingRegex(#"^\s*(?:(?:de|d'|du|la|le|l'|des|cette|fonction|suivante)\s+)*"#, with: "")
        text = text.replacingRegex(#"^\s*f\s*(?:\(\s*x\s*\)|de x)\s*(?:egale\s*)?"#, with: "")
        text = text.replacingRegex(#"^\s*(?:(?:de|d'|du|la|le|l')\s+)*"#, with: "")
        for (pattern, replacement) in functionWords {
            text = text.replacingRegex(pattern, with: replacement)
        }
        guard let tokens = tokenize(text), !tokens.isEmpty else { return nil }
        var parser = TermParser(tokens: tokens)
        guard let terms = parser.parsePolynomial(), parser.isAtEnd else { return nil }
        return combine(terms)
    }

    private struct TermParser {
        let tokens: [String]
        var index = 0

        init(tokens: [String]) {
            self.tokens = tokens
        }

        var isAtEnd: Bool { index >= tokens.count }
        var peek: String? { index < tokens.count ? tokens[index] : nil }

        mutating func next() -> String? {
            let token = peek
            index += 1
            return token
        }

        mutating func parsePolynomial() -> [Term]? {
            var terms: [Term] = []
            var negative = false
            if peek == "+" || peek == "-" {
                negative = next() == "-"
            }
            guard var first = parseTerm() else { return nil }
            if negative { first.coefficient = first.coefficient.negated }
            terms.append(first)
            while peek == "+" || peek == "-" {
                let minus = next() == "-"
                guard var term = parseTerm() else { return nil }
                if minus { term.coefficient = term.coefficient.negated }
                terms.append(term)
            }
            return terms
        }

        /// Product and quotient of factors: 3x², x³/3, 2 sin x, 1/x.
        mutating func parseTerm() -> Term? {
            guard var term = parseFactor() else { return nil }
            while let token = peek {
                if token == "*" {
                    index += 1
                    guard let factor = parseFactor(), let product = JarvisMathSolver.multiply(term, factor) else { return nil }
                    term = product
                } else if token == "/" {
                    index += 1
                    guard let factor = parseFactor(), let quotient = JarvisMathSolver.divide(term, factor) else { return nil }
                    term = quotient
                } else if token == "x" || token == "(" || ["sin", "cos", "exp", "ln"].contains(token) || JarvisMathSolver.isNumberToken(token) {
                    guard let factor = parseFactor(), let product = JarvisMathSolver.multiply(term, factor) else { return nil }
                    term = product
                } else {
                    break
                }
            }
            return term
        }

        /// A number (with an optional integer power), x or xⁿ, sin x, cos x, eˣ, ln x, or one
        /// term in parentheses.
        mutating func parseFactor() -> Term? {
            guard let token = next() else { return nil }
            if let number = JarvisRational(decimal: token) {
                guard peek == "^" else { return Term(coefficient: number, basis: .power(0)) }
                index += 1
                guard let exponent = parseExponent(), exponent >= 0, exponent <= 12, let value = number.raised(to: exponent) else { return nil }
                return Term(coefficient: value, basis: .power(0))
            }
            switch token {
            case "x":
                guard peek == "^" else { return Term(coefficient: .one, basis: .power(1)) }
                index += 1
                guard let exponent = parseExponent(), abs(exponent) <= 50 else { return nil }
                return Term(coefficient: .one, basis: .power(exponent))
            case "sin", "cos", "exp", "ln":
                let opened = peek == "("
                if opened { index += 1 }
                guard next() == "x" else { return nil }
                if opened {
                    guard next() == ")" else { return nil }
                }
                let basis: Basis
                switch token {
                case "sin": basis = .sine
                case "cos": basis = .cosine
                case "exp": basis = .exponential
                default: basis = .logarithm
                }
                return Term(coefficient: .one, basis: basis)
            case "(":
                guard let inner = parsePolynomial(), inner.count == 1, next() == ")" else { return nil }
                return inner[0]
            default:
                return nil
            }
        }

        /// 2, -1, (3), (-2).
        mutating func parseExponent() -> Int? {
            let opened = peek == "("
            if opened { index += 1 }
            var negative = false
            if peek == "-" {
                negative = true
                index += 1
            }
            guard let token = next(), let value = Int(token) else { return nil }
            if opened {
                guard next() == ")" else { return nil }
            }
            return negative ? -value : value
        }
    }

    static func multiply(_ a: Term, _ b: Term) -> Term? {
        guard let coefficient = a.coefficient.multiplied(by: b.coefficient) else { return nil }
        switch (a.basis, b.basis) {
        case (.power(let m), .power(let n)):
            return Term(coefficient: coefficient, basis: .power(m + n))
        case (.power(0), let other), (let other, .power(0)):
            return Term(coefficient: coefficient, basis: other)
        default:
            return nil // x·sin x, sin x·cos x: left to the local brain
        }
    }

    static func divide(_ a: Term, _ b: Term) -> Term? {
        guard let coefficient = a.coefficient.divided(by: b.coefficient) else { return nil }
        switch (a.basis, b.basis) {
        case (.power(let m), .power(let n)):
            return Term(coefficient: coefficient, basis: .power(m - n))
        case (let other, .power(0)):
            return Term(coefficient: coefficient, basis: other)
        default:
            return nil
        }
    }

    /// Adds like terms and orders them for display; zero terms disappear.
    static func combine(_ terms: [Term]) -> [Term]? {
        var sums: [Basis: JarvisRational] = [:]
        var bases: [Basis] = []
        for term in terms {
            if let existing = sums[term.basis] {
                guard let sum = existing.adding(term.coefficient) else { return nil }
                sums[term.basis] = sum
            } else {
                sums[term.basis] = term.coefficient
                bases.append(term.basis)
            }
        }
        return bases
            .compactMap { basis -> Term? in
                guard let coefficient = sums[basis], !coefficient.isZero else { return nil }
                return Term(coefficient: coefficient, basis: basis)
            }
            .sorted { $0.basis.order < $1.basis.order }
    }

    static func integral(of terms: [Term]) -> [Term]? {
        var result: [Term] = []
        for term in terms {
            switch term.basis {
            case .power(let exponent):
                if exponent == -1 {
                    result.append(Term(coefficient: term.coefficient, basis: .absLogarithm))
                } else {
                    guard let divisor = JarvisRational(exponent + 1),
                          let coefficient = term.coefficient.divided(by: divisor) else { return nil }
                    result.append(Term(coefficient: coefficient, basis: .power(exponent + 1)))
                }
            case .sine:
                result.append(Term(coefficient: term.coefficient.negated, basis: .cosine))
            case .cosine:
                result.append(Term(coefficient: term.coefficient, basis: .sine))
            case .exponential:
                result.append(term)
            case .logarithm, .absLogarithm:
                return nil // x ln x − x: left to the local brain
            }
        }
        return combine(result)
    }

    static func derivative(of terms: [Term]) -> [Term]? {
        var result: [Term] = []
        for term in terms {
            switch term.basis {
            case .power(let exponent):
                guard exponent != 0 else { continue }
                guard let factor = JarvisRational(exponent),
                      let coefficient = term.coefficient.multiplied(by: factor) else { return nil }
                result.append(Term(coefficient: coefficient, basis: .power(exponent - 1)))
            case .sine:
                result.append(Term(coefficient: term.coefficient, basis: .cosine))
            case .cosine:
                result.append(Term(coefficient: term.coefficient.negated, basis: .sine))
            case .exponential:
                result.append(term)
            case .logarithm, .absLogarithm:
                result.append(Term(coefficient: term.coefficient, basis: .power(-1)))
            }
        }
        return combine(result)
    }

    static func value(of terms: [Term], at x: Double) -> Double? {
        var total = 0.0
        for term in terms {
            let c = term.coefficient.doubleValue
            switch term.basis {
            case .power(let exponent):
                if exponent < 0 && x == 0 { return nil }
                total += c * pow(x, Double(exponent))
            case .sine: total += c * sin(x)
            case .cosine: total += c * cos(x)
            case .exponential: total += c * exp(x)
            case .logarithm:
                guard x > 0 else { return nil }
                total += c * log(x)
            case .absLogarithm:
                guard x != 0 else { return nil }
                total += c * log(abs(x))
            }
        }
        return total.isFinite ? total : nil
    }

    static func exactDefinite(_ primitive: [Term], from a: JarvisRational, to b: JarvisRational) -> JarvisRational? {
        var total = JarvisRational.zero
        for term in primitive {
            guard case .power(let exponent) = term.basis,
                  let high = b.raised(to: exponent),
                  let low = a.raised(to: exponent),
                  let difference = high.subtracting(low),
                  let part = term.coefficient.multiplied(by: difference),
                  let sum = total.adding(part) else { return nil }
            total = sum
        }
        return total
    }

    static func definite(_ terms: [Term], primitive: [Term], function: String, primitiveText: String, lower: Bound, upper: Bound) -> Answer {
        let header = "de \(lower.display) à \(upper.display) de \(function)"
        let low = min(lower.value, upper.value)
        let high = max(lower.value, upper.value)
        let singular = terms.contains { term in
            switch term.basis {
            case .power(let exponent): return exponent < 0 && low <= 0 && high >= 0
            case .logarithm, .absLogarithm: return low <= 0
            default: return false
            }
        }
        if singular {
            return Answer(
                spoken: "L'intégrale \(header) n'est pas définie : la fonction n'existe pas en 0, qui est dans l'intervalle.",
                display: "∫ \(header) dx : non définie, la fonction n'existe pas en 0."
            )
        }
        if let a = lower.exact, let b = upper.exact, let exact = exactDefinite(primitive, from: a, to: b) {
            if exact.isInteger {
                return Answer(spoken: "L'intégrale \(header) vaut \(exact.text).", display: "∫ \(header) dx = [\(primitiveText)] = \(exact.text)")
            }
            let approx = approximate(exact.doubleValue)
            return Answer(
                spoken: "L'intégrale \(header) vaut \(exact.text), soit environ \(approx.spoken).",
                display: "∫ \(header) dx = [\(primitiveText)] = \(exact.text) ≈ \(approx.display)"
            )
        }
        guard let fb = value(of: primitive, at: upper.value), let fa = value(of: primitive, at: lower.value) else {
            return Answer(spoken: "Je ne peux pas calculer cette intégrale sur cet intervalle.", display: "∫ \(header) dx : non calculable sur cet intervalle.")
        }
        let result = fb - fa
        if abs(result - result.rounded()) < 1e-9 {
            let whole = decimalText(result.rounded(), decimals: 0)
            return Answer(spoken: "L'intégrale \(header) vaut \(whole).", display: "∫ \(header) dx = [\(primitiveText)] = \(whole)")
        }
        let approx = approximate(result)
        return Answer(
            spoken: "L'intégrale \(header) vaut environ \(approx.spoken).",
            display: "∫ \(header) dx = [\(primitiveText)] ≈ \(approx.display)"
        )
    }

    // MARK: Writing a function

    /// 3x² − 2x + 1, x³/3, −sin x, eˣ, ln|x|, 1/x.
    static func format(_ terms: [Term]) -> String {
        guard !terms.isEmpty else { return "0" }
        var text = ""
        for (index, term) in terms.enumerated() {
            let negative = term.coefficient.numerator < 0
            let magnitude = negative ? term.coefficient.negated : term.coefficient
            let body = formatMagnitude(magnitude, basis: term.basis)
            if index == 0 {
                text = (negative ? "−" : "") + body
            } else {
                text += (negative ? " − " : " + ") + body
            }
        }
        return text
    }

    static func formatMagnitude(_ coefficient: JarvisRational, basis: Basis) -> String {
        let p = coefficient.numerator
        let q = coefficient.denominator
        func withSymbol(_ symbol: String) -> String {
            let lead = p == 1 ? "" : "\(p)"
            return q == 1 ? lead + symbol : lead + symbol + "/\(q)"
        }
        func withFunction(_ symbol: String) -> String {
            if p == 1 && q == 1 { return symbol }
            if q == 1 { return "\(p) \(symbol)" }
            return "(\(p)/\(q)) \(symbol)"
        }
        switch basis {
        case .power(0):
            return q == 1 ? "\(p)" : "\(p)/\(q)"
        case .power(1):
            return withSymbol("x")
        case .power(let exponent) where exponent > 1:
            return withSymbol("x" + JarvisSpokenMath.superscript(exponent))
        case .power(let exponent):
            let denominator = exponent == -1 ? "x" : "x" + JarvisSpokenMath.superscript(-exponent)
            return q == 1 ? "\(p)/\(denominator)" : "\(p)/(\(q)\(denominator))"
        case .sine: return withFunction("sin x")
        case .cosine: return withFunction("cos x")
        case .exponential: return withFunction("eˣ")
        case .logarithm: return withFunction("ln x")
        case .absLogarithm: return withFunction("ln|x|")
        }
    }
}

private extension String {
    /// Groups of the first match of `pattern` (group 0 is the whole match), or nil.
    func regexGroups(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let text = self as NSString
        guard let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: text.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : text.substring(with: range)
        }
    }
}
