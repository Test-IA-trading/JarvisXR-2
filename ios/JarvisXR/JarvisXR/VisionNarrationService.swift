import Foundation

struct VisionNarrationConfiguration: Codable, Equatable, Sendable {
    var conciseObjectLimit: Int
    var standardObjectLimit: Int
    var detailedObjectLimit: Int

    init(conciseObjectLimit: Int = 2, standardObjectLimit: Int = 3, detailedObjectLimit: Int = 5) {
        self.conciseObjectLimit = max(1, conciseObjectLimit)
        self.standardObjectLimit = max(conciseObjectLimit, standardObjectLimit)
        self.detailedObjectLimit = max(standardObjectLimit, detailedObjectLimit)
    }
}

final class VisionNarrationService {
    let safetyPolicy: VisionSafetyPolicy
    let configuration: VisionNarrationConfiguration

    init(
        safetyPolicy: VisionSafetyPolicy = VisionSafetyPolicy(),
        configuration: VisionNarrationConfiguration = VisionNarrationConfiguration()
    ) {
        self.safetyPolicy = safetyPolicy
        self.configuration = configuration
    }

    func narrate(
        snapshot: SceneSnapshot,
        verbosity: NarrationVerbosity = .standard,
        region: SpatialRegion? = nil,
        targetClassIdentifier: String? = nil
    ) -> SceneNarration {
        guard snapshot.quality.isUsable else {
            return qualityNarration(for: snapshot, verbosity: verbosity)
        }

        var candidates = region.map { snapshot.objects(in: $0) } ?? snapshot.objects
        if let targetClassIdentifier {
            candidates = candidates.filter { $0.classIdentifier == targetClassIdentifier }
            return targetNarration(
                classIdentifier: targetClassIdentifier,
                candidates: candidates,
                snapshot: snapshot,
                verbosity: verbosity
            )
        }

        let limit = objectLimit(for: verbosity)
        let speakable = candidates.compactMap { tracked -> (TrackedObservation, VisionEvidenceDecision)? in
            let decision = safetyPolicy.decision(for: tracked, frameUsable: snapshot.quality.isUsable)
            if case .suppressed = decision { return nil }
            return (tracked, decision)
        }

        guard !speakable.isEmpty else {
            var text = safetyPolicy.qualifiedAbsence(region: region)
            if !snapshot.text.isEmpty {
                text += " Je repère aussi du texte lisible."
            }
            return makeNarration(
                snapshot: snapshot,
                text: text,
                priority: .prominent,
                verbosity: verbosity,
                contentKind: .scene
            )
        }

        var sentences = speakable.prefix(limit).map { tracked, decision in
            describe(tracked, decision: decision, verbosity: verbosity)
        }
        if !snapshot.text.isEmpty, verbosity != .concise {
            let textRegion = snapshot.text.first?.boundingBox.horizontalRegion.spokenLocation ?? "dans l'image"
            sentences.append("Je repère aussi du texte lisible \(textRegion).")
        }
        if !snapshot.quality.warnings.isEmpty, let guidance = snapshot.quality.guidance.first {
            sentences.append(guidance)
        }

        let groundedIdentifiers = speakable.prefix(limit).map { $0.0.observation.id }
        let priority: SpeechPriority = speakable.contains(where: { $0.0.observation.isRequested }) ? .target : .prominent
        return makeNarration(
            snapshot: snapshot,
            text: sentences.joined(separator: " "),
            priority: priority,
            verbosity: verbosity,
            contentKind: .scene,
            groundedIdentifiers: groundedIdentifiers
        )
    }

    func narrateChanges(
        in snapshot: SceneSnapshot,
        verbosity: NarrationVerbosity = .standard
    ) -> SceneNarration {
        guard snapshot.quality.isUsable else {
            return qualityNarration(for: snapshot, verbosity: verbosity)
        }

        let meaningful = snapshot.changes.filter {
            switch $0.kind {
            case .appeared, .moved, .approaching, .receding, .lost: return true
            case .persisted, .uncertain: return false
            }
        }

        guard !meaningful.isEmpty else {
            return makeNarration(
                snapshot: snapshot,
                text: "Je n'ai pas de changement visuel confirmé à signaler.",
                priority: .change,
                verbosity: verbosity,
                contentKind: .change
            )
        }

        let limit = objectLimit(for: verbosity)
        let selected = meaningful.prefix(limit)
        let sentences = selected.map(changeDescription)
        return makeNarration(
            snapshot: snapshot,
            text: sentences.joined(separator: " "),
            priority: meaningful.contains(where: { $0.kind == .approaching }) ? .warning : .change,
            verbosity: verbosity,
            contentKind: .change,
            groundedIdentifiers: selected.map(\.trackIdentifier)
        )
    }

    /// Live Guide: one French line for the debounced events of a frame (see VisionLiveGuideEngine).
    func narrateLiveGuide(events: [VisionLiveGuideEvent], snapshot: SceneSnapshot) -> SceneNarration? {
        guard !events.isEmpty else { return nil }
        return makeNarration(
            snapshot: snapshot,
            text: VisionLiveGuideEngine.narrationText(for: events),
            priority: .change,
            verbosity: .standard,
            contentKind: .change,
            groundedIdentifiers: events.map(\.trackIdentifier)
        )
    }

    func verbatimNarration(
        _ content: String,
        snapshotIdentifier: UUID,
        kind: NarrationContentKind,
        createdAt: Date = Date()
    ) -> SceneNarration? {
        guard kind == .reading || kind == .barcode else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SceneNarration(
            snapshotIdentifier: snapshotIdentifier,
            text: trimmed,
            priority: .target,
            verbosity: .standard,
            contentKind: kind,
            isVerbatim: true,
            createdAt: createdAt
        )
    }

    private func targetNarration(
        classIdentifier: String,
        candidates: [TrackedObservation],
        snapshot: SceneSnapshot,
        verbosity: NarrationVerbosity
    ) -> SceneNarration {
        let targetNoun = VisionFrenchVocabulary.noun(for: classIdentifier)
        let notFound = "Je n'ai pas encore trouvé \(targetNoun.definite). Balayez lentement : je peux \(targetNoun.objectPronoun) manquer."
        guard let candidate = candidates.first(where: {
            if case .suppressed = safetyPolicy.decision(for: $0, frameUsable: snapshot.quality.isUsable) {
                return false
            }
            return true
        }) else {
            return makeNarration(
                snapshot: snapshot,
                text: notFound,
                priority: .target,
                verbosity: verbosity,
                contentKind: .target
            )
        }

        let decision = safetyPolicy.decision(for: candidate, frameUsable: snapshot.quality.isUsable)
        let phrase = objectPhrase(candidate)
        let text: String
        switch decision {
        case .supported:
            text = "Je détecte \(phrase) \(candidate.horizontalRegion.spokenLocation)."
        case .uncertain:
            text = "Je vois peut-être \(phrase) \(candidate.horizontalRegion.spokenLocation)."
        case .suppressed:
            text = notFound
        }
        return makeNarration(
            snapshot: snapshot,
            text: text,
            priority: .target,
            verbosity: verbosity,
            contentKind: .target,
            groundedIdentifiers: [candidate.observation.id]
        )
    }

    private func describe(
        _ tracked: TrackedObservation,
        decision: VisionEvidenceDecision,
        verbosity: NarrationVerbosity
    ) -> String {
        let phrase = objectPhrase(tracked)
        let evidence: String
        switch decision {
        case .supported: evidence = "Je détecte \(phrase)"
        case .uncertain: evidence = "Je vois peut-être \(phrase)"
        case .suppressed: return ""
        }

        var details = " \(tracked.horizontalRegion.spokenLocation)"
        if verbosity == .detailed {
            switch tracked.verticalRegion {
            case .high: details += ", en haut de l'image"
            case .low: details += ", en bas de l'image"
            case .middle: break
            }
            let noun = VisionFrenchVocabulary.noun(for: tracked.classIdentifier)
            let pronoun = noun.subjectPronoun.capitalizedFirstLetter
            if tracked.observation.relativeDistance == .possiblyClose {
                details += ". \(pronoun) semble assez proche, d'après sa seule taille dans l'image"
            } else if tracked.observation.relativeDistance == .fartherAway {
                details += ". \(pronoun) paraît plus \(noun.isFeminine ? "petite" : "petit") et peut-être plus loin"
            }
        }
        return evidence + details + "."
    }

    private func objectPhrase(_ tracked: TrackedObservation) -> String {
        VisionFrenchVocabulary.noun(for: tracked.classIdentifier).indefinite
    }

    private func changeDescription(_ change: SceneChange) -> String {
        let noun = VisionFrenchVocabulary.noun(for: change.classIdentifier)
        let subject = noun.capitalizedDefinite
        switch change.kind {
        case .appeared:
            return "Je vois maintenant \(noun.indefinite) \((change.currentRegion ?? .center).spokenLocation)."
        case .moved:
            if let previous = change.previousRegion, let current = change.currentRegion, previous != current {
                return "\(subject) s'est \(noun.agreed("déplacé")) \(previous.frenchFromPhrase) \(current.frenchTowardPhrase)."
            }
            return "\(subject) a bougé dans l'image."
        case .approaching:
            return "\(subject) grossit dans l'image, \((change.currentRegion ?? .center).spokenLocation)."
        case .receding:
            return "\(subject) rapetisse dans l'image, \((change.currentRegion ?? .center).spokenLocation)."
        case .lost:
            return "Je ne vois plus \(noun.definite). Je l'ai \(noun.agreed("vu")) pour la dernière fois \((change.previousRegion ?? .center).spokenLocation)."
        case .persisted, .uncertain:
            return ""
        }
    }

    private func qualityNarration(for snapshot: SceneSnapshot, verbosity: NarrationVerbosity) -> SceneNarration {
        let text: String
        if snapshot.quality.warnings.contains(.cameraCovered) {
            text = "La caméra est peut-être couverte. Dégagez l'objectif et réessayez."
        } else if snapshot.quality.warnings.contains(.lowLight) {
            text = "L'image est trop sombre pour une description fiable. Plus de lumière aiderait."
        } else if snapshot.quality.warnings.contains(.overexposed) {
            text = "L'image est trop claire pour une description fiable. Détournez la caméra de la lumière la plus forte et réessayez."
        } else if snapshot.quality.warnings.contains(.blurry) || snapshot.quality.warnings.contains(.excessiveMotion) {
            text = "L'image est trop floue pour une description fiable. Tenez le téléphone plus immobile et réessayez."
        } else if let guidance = snapshot.quality.guidance.first {
            text = "Je ne peux pas identifier la scène de façon fiable. \(guidance)"
        } else {
            text = "Je ne peux pas donner de description fiable à partir de cette image."
        }
        return makeNarration(
            snapshot: snapshot,
            text: text,
            priority: .warning,
            verbosity: verbosity,
            contentKind: .system
        )
    }

    private func makeNarration(
        snapshot: SceneSnapshot,
        text: String,
        priority: SpeechPriority,
        verbosity: NarrationVerbosity,
        contentKind: NarrationContentKind,
        groundedIdentifiers: [UUID] = []
    ) -> SceneNarration {
        let safeText = safetyPolicy.safeNarration(text)
        return SceneNarration(
            snapshotIdentifier: snapshot.id,
            text: safeText,
            priority: priority,
            verbosity: verbosity,
            contentKind: contentKind,
            groundedObservationIdentifiers: groundedIdentifiers,
            createdAt: snapshot.capturedAt
        )
    }

    private func objectLimit(for verbosity: NarrationVerbosity) -> Int {
        switch verbosity {
        case .concise: return configuration.conciseObjectLimit
        case .standard: return configuration.standardObjectLimit
        case .detailed: return configuration.detailedObjectLimit
        }
    }
}
