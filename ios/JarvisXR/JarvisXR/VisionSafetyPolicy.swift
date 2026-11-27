import Foundation

enum VisionSafetySuppressionReason: String, Codable, Equatable, Sendable {
    case invalidConfidence
    case belowMinimumConfidence
    case insufficientStability
    case unusableFrame
}

enum VisionEvidenceDecision: Codable, Equatable, Sendable {
    case suppressed(VisionSafetySuppressionReason)
    case uncertain
    case supported
}

struct VisionSafetyConfiguration: Codable, Equatable, Sendable {
    var minimumConfidence: Double
    var requestedMinimumConfidence: Double
    var supportedConfidence: Double
    var requiredStableFrames: Int
    var requestedStableFrames: Int

    static let conservative = VisionSafetyConfiguration(
        minimumConfidence: 0.58,
        requestedMinimumConfidence: 0.54,
        supportedConfidence: 0.82,
        requiredStableFrames: 3,
        requestedStableFrames: 2
    )

    static let balanced = VisionSafetyConfiguration(
        minimumConfidence: 0.52,
        requestedMinimumConfidence: 0.50,
        supportedConfidence: 0.78,
        requiredStableFrames: 3,
        requestedStableFrames: 2
    )

    static let moreSensitive = VisionSafetyConfiguration(
        minimumConfidence: 0.45,
        requestedMinimumConfidence: 0.43,
        supportedConfidence: 0.74,
        requiredStableFrames: 2,
        requestedStableFrames: 2
    )
}

struct VisionSafetyValidation: Equatable, Sendable {
    let isAllowed: Bool
    let violations: [String]
}

struct VisionSafetyPolicy: Sendable {
    let configuration: VisionSafetyConfiguration

    init(configuration: VisionSafetyConfiguration = .conservative) {
        self.configuration = configuration
    }

    func decision(
        confidence: Double,
        consecutiveFrames: Int,
        isRequested: Bool,
        frameUsable: Bool
    ) -> VisionEvidenceDecision {
        guard frameUsable else {
            return .suppressed(.unusableFrame)
        }
        guard confidence.isFinite, confidence >= 0, confidence <= 1 else {
            return .suppressed(.invalidConfidence)
        }

        let minimum = isRequested ? configuration.requestedMinimumConfidence : configuration.minimumConfidence
        guard confidence >= minimum else {
            return .suppressed(.belowMinimumConfidence)
        }

        let requiredFrames = isRequested ? configuration.requestedStableFrames : configuration.requiredStableFrames
        guard consecutiveFrames >= requiredFrames else {
            return .suppressed(.insufficientStability)
        }

        return confidence >= configuration.supportedConfidence ? .supported : .uncertain
    }

    func decision(for observation: TrackedObservation, frameUsable: Bool) -> VisionEvidenceDecision {
        decision(
            confidence: observation.smoothedConfidence,
            consecutiveFrames: observation.consecutiveFrameCount,
            isRequested: observation.observation.isRequested,
            frameUsable: frameUsable
        )
    }

    func validateNarration(
        _ text: String,
        contentKind: NarrationContentKind = .scene,
        isVerbatim: Bool = false
    ) -> VisionSafetyValidation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return VisionSafetyValidation(isAllowed: false, violations: ["empty narration"])
        }

        // OCR and barcode payloads can contain arbitrary words. They are permitted only when
        // explicitly typed as verbatim content; callers must never execute them as commands.
        if isVerbatim, contentKind == .reading || contentKind == .barcode {
            return VisionSafetyValidation(isAllowed: true, violations: [])
        }

        let normalized = normalize(trimmed)
        var violations: [String] = []
        for rule in Self.prohibitedRules where Self.matches(normalized, pattern: rule.pattern) {
            violations.append(rule.label)
        }

        return VisionSafetyValidation(isAllowed: violations.isEmpty, violations: violations)
    }

    func safeNarration(
        _ proposed: String,
        fallback: String = "Je ne peux pas donner de description fiable à partir de cette image."
    ) -> String {
        if validateNarration(proposed).isAllowed {
            return proposed
        }
        if validateNarration(fallback).isAllowed {
            return fallback
        }
        return "Je ne peux pas le vérifier."
    }

    func qualifiedAbsence(region: SpatialRegion? = nil) -> String {
        let location = region.map { " \($0.spokenLocation)" } ?? ""
        return "Je ne détecte aucun objet connu\(location) pour le moment, mais je peux en manquer."
    }

    func isQualifiedAbsence(_ text: String) -> Bool {
        let normalized = normalize(text)
        let describesAbsence = normalized.contains("do not detect") ||
            normalized.contains("did not detect") ||
            normalized.contains("have not found") ||
            normalized.contains("ne détecte") ||
            normalized.contains("pas encore trouvé") ||
            normalized.contains("n'ai pas trouvé")
        let includesUncertainty = normalized.contains("may be missing") ||
            normalized.contains("cannot verify") ||
            normalized.contains("not confident") ||
            normalized.contains("peux en manquer") ||
            normalized.contains("peux la manquer") ||
            normalized.contains("peux le manquer") ||
            normalized.contains("peut-être") ||
            normalized.contains("pas certain")
        return !describesAbsence || includesUncertainty
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let prohibitedRules: [(label: String, pattern: String)] = [
        (
            "navigation safety claim",
            #"\b(the\s+)?(path|road|street|crosswalk)\s+(is|looks|appears)\s+(safe|clear)\b"#
        ),
        (
            "crossing or proceeding instruction",
            #"\b(safe\s+to|you\s+can)\s+(cross|proceed|continue|go|go\s+ahead)\b"#
        ),
        (
            "all-clear claim",
            #"\b(all\s+clear|nothing\s+(is\s+)?(ahead|in\s+front|there))\b"#
        ),
        (
            "unsupported absence guarantee",
            #"\b(there\s+(are|is)|i\s+(see|detect))\s+no\s+(obstacles?|hazards?|vehicles?|people|persons?)\b"#
        ),
        (
            "certainty guarantee",
            #"\b(definitely|certainly|guaranteed|infallible)\b"#
        ),
        (
            "unsupported precise visual distance",
            #"\b\d+(\.\d+)?\s*(feet|foot|ft|inches|inch|meters|meter|metres|metre|yards|yard)\b"#
        ),
        // The same claims in French, now that Live Guide speaks French.
        (
            "affirmation de sécurité du trajet",
            #"\b(le|la)\s+(chemin|route|rue|voie|passage)\s+(est|semble|paraît|parait)\s+(sûre?|sure?|libre|dégagée?|degagee?|sans\s+danger)\b"#
        ),
        (
            "consigne de traverser ou d'avancer",
            #"\b(vous\s+pouvez|tu\s+peux|on\s+peut)\s+(traverser|avancer|continuer|passer|y\s+aller)\b"#
        ),
        (
            "affirmation que tout est dégagé",
            #"\b(la\s+voie\s+est\s+libre|il\s+n'y\s+a\s+rien\s+(devant|en\s+face)|rien\s+(devant|en\s+face)\s+de\s+(vous|toi))\b"#
        ),
        (
            "garantie d'absence non étayée",
            #"\b(il\s+n'y\s+a|je\s+ne\s+(vois|détecte|detecte))\s+(aucun|aucune|pas\s+d'|pas\s+de)\s*(obstacles?|dangers?|véhicules?|vehicules?|voitures?|personnes?)\b"#
        ),
        (
            "garantie de certitude",
            #"\b(certainement|assurément|assurement|sans\s+aucun\s+doute|garanti|garantie|infaillible)\b"#
        ),
        (
            "distance visuelle précise non étayée",
            #"\b\d+([.,]\d+)?\s*(mètres?|metres?|centimètres?|centimetres?|cm|pieds?|pouces?)\b"#
        )
    ]

    private static func matches(_ value: String, pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, options: [], range: range) != nil
    }
}
