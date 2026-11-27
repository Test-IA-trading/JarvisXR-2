import Foundation

/// The phone's attitude (unit quaternion from CoreMotion) and the strongest shake since the
/// previous frame. Plain values so the Live Guide engine is testable without sensors.
struct VisionCameraPose: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double
    var w: Double
    /// Strongest user acceleration since the previous frame, in g.
    var peakAcceleration: Double

    init(x: Double, y: Double, z: Double, w: Double, peakAcceleration: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
        self.peakAcceleration = peakAcceleration
    }

    static let level = VisionCameraPose(x: 0, y: 0, z: 0, w: 1)

    /// Rotation between two attitudes, in degrees.
    func rotationDegrees(to other: VisionCameraPose) -> Double {
        let dot = abs(x * other.x + y * other.y + z * other.z + w * other.w)
        return 2 * acos(min(1, dot)) * 180 / Double.pi
    }

    /// The level attitude turned by `degrees` around the vertical axis (tests, previews).
    static func turned(by degrees: Double, peakAcceleration: Double = 0) -> VisionCameraPose {
        let half = degrees * Double.pi / 360
        return VisionCameraPose(x: 0, y: 0, z: sin(half), w: cos(half), peakAcceleration: peakAcceleration)
    }
}

/// One tracked detection handed to the Live Guide engine for a frame.
struct VisionLiveGuideSighting: Equatable, Sendable {
    let trackIdentifier: UUID
    let classIdentifier: String
    /// The detector's own box for this frame (not smoothed), in Vision's normalized coordinates.
    let box: NormalizedRect
    /// Seen over several frames and allowed by the safety policy: may be announced.
    let isConfirmed: Bool
    /// High confidence (« je vois ») rather than plausible (« je crois voir »).
    let isCertain: Bool
}

enum VisionLiveGuideEventKind: String, Codable, Sendable {
    case appeared
    case reappeared
    case moved
    case approached
    case receded
    case gone
}

struct VisionLiveGuideEvent: Equatable, Sendable {
    let kind: VisionLiveGuideEventKind
    let objectIdentifier: UUID
    let trackIdentifier: UUID
    let classIdentifier: String
    let fromRegion: SpatialRegion?
    let toRegion: SpatialRegion?
    /// Shift of the object's centre since its last known place, as fractions of the image
    /// (positive: to the right, upwards).
    let horizontalShift: Double
    let verticalShift: Double
    let isCertain: Bool
    let occurredAt: Date
}

struct VisionLiveGuideConfiguration: Equatable, Sendable {
    /// An object unseen for this long (and for `minimumMissedFrames` analysed frames) is gone;
    /// shorter detector dropouts stay silent.
    var lossGrace: TimeInterval = 2.5
    var minimumMissedFrames: Int = 3
    /// A gone object detected again within this window is the same object (« Je revois la tasse »).
    var revivalWindow: TimeInterval = 60
    /// Coming back this soon after being declared gone makes the next loss wait longer.
    var flickerWindow: TimeInterval = 8
    /// How long gone objects are remembered for questions (process memory only).
    var memoryWindow: TimeInterval = 600
    /// Shift of the centre, as a fraction of the image, that counts as a move.
    var horizontalMoveThreshold: Double = 0.14
    var verticalMoveThreshold: Double = 0.18
    /// Change of apparent size that counts as « s'est rapprochée / éloignée ».
    var scaleRatioThreshold: Double = 1.8
    /// Analysed frames the object must stay put before its move is announced.
    var settleFrames: Int = 2
    /// Per-frame change of the centre under which the object is at rest.
    var restingTolerance: Double = 0.05
    /// How far a not-yet-confirmed detection may be from a known object to keep it alive.
    var unconfirmedMatchDistance: Double = 0.25
    /// Rotation of the phone between two frames, in degrees, meaning the phone is moving.
    var phoneRotationPerFrame: Double = 1.2
    /// Rotation of the phone since an object was placed, in degrees, beyond which the
    /// object's shift in the image is attributed to the phone.
    var phoneRotationTolerance: Double = 4
    /// User acceleration, in g, meaning the phone is moving.
    var phoneAccelerationThreshold: Double = 0.1
    /// After the phone moved, wait this long before trusting positions again.
    var phoneSettleInterval: TimeInterval = 0.8
    /// Minimum time between two announcements about the same object.
    var objectCooldown: TimeInterval = 3
    var maximumRecords: Int = 24
    var maximumEvents: Int = 40
}

/// What Live Guide remembers about one real object during the session.
struct VisionLiveObjectRecord: Equatable, Sendable {
    let id: UUID
    let classIdentifier: String
    var trackIdentifier: UUID
    var box: NormalizedRect
    /// Where the object was last announced (or silently accepted after the phone moved).
    var anchorBox: NormalizedRect
    var anchorPose: VisionCameraPose?
    var firstSeenAt: Date
    var lastSeenAt: Date
    var lastMentionedAt: Date
    var lastAnnouncedAt: Date?
    var isVisible: Bool
    var isCertain: Bool
    var presenceAnnounced: Bool
    var hasBeenGone: Bool
    var goneAt: Date?
    var flickerCount: Int
    var missedFrames: Int
    var restingFrames: Int
    var needsReanchor: Bool

    var noun: VisionFrenchNoun { VisionFrenchVocabulary.noun(for: classIdentifier) }
    var region: SpatialRegion { box.horizontalRegion }
}

/// Turns tracked detections into the few events worth saying in Live Guide: an object
/// appears (once), moves and comes to rest, or leaves the view. Detector flicker, a hand
/// hiding the object while carrying it and movements of the phone itself stay silent.
/// It also answers « Elle est où maintenant ? » from what it saw. Nothing is written to disk.
final class VisionLiveGuideEngine: @unchecked Sendable {
    let configuration: VisionLiveGuideConfiguration

    private let lock = NSLock()
    private var records: [VisionLiveObjectRecord] = []
    private var recentEvents: [VisionLiveGuideEvent] = []
    private var observing = false
    private var previousPose: VisionCameraPose?
    private var lastPhoneMotionAt: Date?
    private var lastFrameAt: Date?
    private var frameInterval: TimeInterval = 0.6

    init(configuration: VisionLiveGuideConfiguration = VisionLiveGuideConfiguration()) {
        self.configuration = configuration
    }

    var isObserving: Bool { locked { observing } }
    var objects: [VisionLiveObjectRecord] { locked { records } }
    var events: [VisionLiveGuideEvent] { locked { recentEvents } }

    /// Starts a fresh observation: nothing from an earlier session is kept.
    func begin() {
        locked {
            clearLocked()
            observing = true
        }
    }

    /// Stops observing and forgets everything that was seen.
    func end() {
        locked {
            clearLocked()
            observing = false
        }
    }

    /// The phone may have moved while frames were not analysed (pause, unusable image): the
    /// next resting place of every object is accepted without announcing a move.
    func noteCameraMayHaveMoved(at date: Date = Date()) {
        locked {
            lastPhoneMotionAt = date
            previousPose = nil
            for index in records.indices {
                records[index].needsReanchor = true
                records[index].restingFrames = 0
            }
        }
    }

    func update(
        sightings: [VisionLiveGuideSighting],
        pose: VisionCameraPose?,
        at now: Date = Date()
    ) -> [VisionLiveGuideEvent] {
        locked { updateLocked(sightings: sightings, pose: pose, now: now) }
    }

    /// Answers a French question about the observed objects, or nil when the sentence is not
    /// such a question (the caller then tries its other commands).
    func answer(to question: String, at now: Date = Date()) -> String? {
        let normalized = JarvisFrenchCommandRouter.stripWakeWord(JarvisFrenchCommandRouter.normalize(question))
        return locked { answerLocked(normalized, now: now) }
    }

    // MARK: - Frames

    private func updateLocked(
        sightings: [VisionLiveGuideSighting],
        pose: VisionCameraPose?,
        now: Date
    ) -> [VisionLiveGuideEvent] {
        guard observing else { return [] }
        if let lastFrameAt {
            let elapsed = now.timeIntervalSince(lastFrameAt)
            if elapsed > 0, elapsed < 5 {
                frameInterval = frameInterval * 0.8 + elapsed * 0.2
            }
        }
        lastFrameAt = now

        // 1. Did the phone itself move since the previous frame?
        var phoneMoving = false
        if let pose {
            if let previousPose, pose.rotationDegrees(to: previousPose) > configuration.phoneRotationPerFrame {
                phoneMoving = true
            }
            if pose.peakAcceleration > configuration.phoneAccelerationThreshold {
                phoneMoving = true
            }
            previousPose = pose
        }
        if phoneMoving {
            lastPhoneMotionAt = now
            for index in records.indices {
                records[index].needsReanchor = true
                records[index].restingFrames = 0
            }
        }

        var produced: [VisionLiveGuideEvent] = []
        var matched = Set<UUID>()
        var reacquiring = Set<String>()

        // 2. Same track as before first…
        var remaining: [VisionLiveGuideSighting] = []
        for sighting in sightings {
            if let index = records.firstIndex(where: {
                $0.trackIdentifier == sighting.trackIdentifier && !matched.contains($0.id)
            }) {
                matched.insert(records[index].id)
                produced += observe(sighting, at: index, pose: pose, phoneMoving: phoneMoving, now: now)
            } else {
                remaining.append(sighting)
            }
        }
        // …then the same kind of object the tracker lost and found again, or a new object.
        for sighting in remaining {
            if let index = reidentify(sighting, excluding: matched, now: now) {
                matched.insert(records[index].id)
                produced += observe(sighting, at: index, pose: pose, phoneMoving: phoneMoving, now: now)
            } else if sighting.isConfirmed {
                let record = VisionLiveObjectRecord(
                    id: UUID(),
                    classIdentifier: sighting.classIdentifier,
                    trackIdentifier: sighting.trackIdentifier,
                    box: sighting.box,
                    anchorBox: sighting.box,
                    anchorPose: pose,
                    firstSeenAt: now,
                    lastSeenAt: now,
                    lastMentionedAt: now,
                    lastAnnouncedAt: nil,
                    isVisible: true,
                    isCertain: sighting.isCertain,
                    presenceAnnounced: false,
                    hasBeenGone: false,
                    goneAt: nil,
                    flickerCount: 0,
                    missedFrames: 0,
                    restingFrames: 0,
                    needsReanchor: phoneMoving
                )
                records.append(record)
                matched.insert(record.id)
            } else {
                // A detection still being confirmed: probably a known object being found again.
                reacquiring.insert(sighting.classIdentifier)
            }
        }

        // 3. Objects missing from this frame.
        let phoneRecentlyMoved = phoneMovedRecently(now)
        for index in records.indices where records[index].isVisible && !matched.contains(records[index].id) {
            if reacquiring.contains(records[index].classIdentifier) { continue }
            records[index].missedFrames += 1
            records[index].restingFrames = 0
            let unseenFor = now.timeIntervalSince(records[index].lastSeenAt)
            guard records[index].missedFrames >= configuration.minimumMissedFrames,
                  unseenFor >= lossGrace(for: records[index]) else { continue }
            let wasAnnounced = records[index].presenceAnnounced
            records[index].isVisible = false
            records[index].hasBeenGone = true
            records[index].goneAt = now
            records[index].presenceAnnounced = false
            if wasAnnounced, !phoneRecentlyMoved, canAnnounce(records[index], now: now) {
                let region = records[index].region
                produced.append(Self.announce(.gone, record: &records[index], from: region, to: nil, now: now))
            }
        }

        // 4. Objects whose presence has not been spoken yet: new, or back after being gone.
        for index in records.indices
        where records[index].isVisible && !records[index].presenceAnnounced && matched.contains(records[index].id) {
            guard canAnnounce(records[index], now: now) else { continue }
            let kind: VisionLiveGuideEventKind = records[index].hasBeenGone ? .reappeared : .appeared
            let region = records[index].region
            produced.append(Self.announce(kind, record: &records[index], from: nil, to: region, now: now))
            records[index].presenceAnnounced = true
        }

        pruneLocked(now: now)
        recentEvents += produced
        if recentEvents.count > configuration.maximumEvents {
            recentEvents.removeFirst(recentEvents.count - configuration.maximumEvents)
        }
        return produced
    }

    private func observe(
        _ sighting: VisionLiveGuideSighting,
        at index: Int,
        pose: VisionCameraPose?,
        phoneMoving: Bool,
        now: Date
    ) -> [VisionLiveGuideEvent] {
        var record = records[index]
        let previousBox = record.box
        record.trackIdentifier = sighting.trackIdentifier
        record.box = sighting.box
        record.lastSeenAt = now
        record.missedFrames = 0
        if sighting.isConfirmed {
            record.isCertain = sighting.isCertain
        }

        guard record.isVisible else {
            // Back after being declared gone: its new place is the reference from now on.
            record.isVisible = true
            if let goneAt = record.goneAt, now.timeIntervalSince(goneAt) < configuration.flickerWindow {
                record.flickerCount += 1
            }
            record.anchorBox = sighting.box
            record.anchorPose = pose
            record.needsReanchor = phoneMoving
            record.restingFrames = 0
            records[index] = record
            return []
        }

        let frameShift = previousBox.centerDistance(to: sighting.box)
        record.restingFrames = frameShift <= configuration.restingTolerance ? record.restingFrames + 1 : 0

        if phoneMoving {
            record.needsReanchor = true
            records[index] = record
            return []
        }
        if record.needsReanchor {
            // The phone moved: accept the place where the object rests, without announcing it.
            if record.restingFrames >= configuration.settleFrames, !phoneMovedRecently(now) {
                record.anchorBox = sighting.box
                record.anchorPose = pose
                record.needsReanchor = false
            }
            records[index] = record
            return []
        }
        if let pose, let anchorPose = record.anchorPose,
           pose.rotationDegrees(to: anchorPose) > configuration.phoneRotationTolerance {
            // The phone slowly turned since the object was placed: its shift is the phone's.
            record.needsReanchor = true
            record.restingFrames = 0
            records[index] = record
            return []
        }

        let horizontalShift = sighting.box.centerX - record.anchorBox.centerX
        let verticalShift = sighting.box.centerY - record.anchorBox.centerY
        let ratio = record.anchorBox.area > 0 ? sighting.box.area / record.anchorBox.area : 1
        let shifted = abs(horizontalShift) >= configuration.horizontalMoveThreshold ||
            abs(verticalShift) >= configuration.verticalMoveThreshold
        let grew = ratio >= configuration.scaleRatioThreshold
        let shrank = ratio <= 1 / configuration.scaleRatioThreshold
        guard shifted || grew || shrank,
              record.restingFrames >= configuration.settleFrames,
              sighting.isConfirmed,
              canAnnounce(record, now: now) else {
            records[index] = record
            return []
        }

        let kind: VisionLiveGuideEventKind = shifted ? .moved : (grew ? .approached : .receded)
        let fromRegion = record.anchorBox.horizontalRegion
        let toRegion = sighting.box.horizontalRegion
        let event = Self.announce(
            kind,
            record: &record,
            from: fromRegion,
            to: toRegion,
            horizontalShift: horizontalShift,
            verticalShift: verticalShift,
            now: now
        )
        record.anchorBox = sighting.box
        record.anchorPose = pose
        record.restingFrames = 0
        records[index] = record
        return [event]
    }

    private func reidentify(_ sighting: VisionLiveGuideSighting, excluding matched: Set<UUID>, now: Date) -> Int? {
        var best: (index: Int, score: Double)?
        for index in records.indices {
            let record = records[index]
            guard record.classIdentifier == sighting.classIdentifier, !matched.contains(record.id) else { continue }
            if !record.isVisible {
                // Declared gone: only a confirmed detection brings it back, and not forever.
                guard sighting.isConfirmed,
                      let goneAt = record.goneAt,
                      now.timeIntervalSince(goneAt) <= configuration.revivalWindow else { continue }
            }
            let distance = record.box.centerDistance(to: sighting.box)
            if !sighting.isConfirmed && distance > configuration.unconfirmedMatchDistance { continue }
            let score = distance + (record.isVisible ? 0 : 1)
            if let current = best, current.score <= score { continue }
            best = (index: index, score: score)
        }
        return best?.index
    }

    private func lossGrace(for record: VisionLiveObjectRecord) -> TimeInterval {
        let base = max(configuration.lossGrace, Double(configuration.minimumMissedFrames + 1) * frameInterval)
        return base * (1 + 0.5 * Double(min(record.flickerCount, 4)))
    }

    private func canAnnounce(_ record: VisionLiveObjectRecord, now: Date) -> Bool {
        guard let last = record.lastAnnouncedAt else { return true }
        return now.timeIntervalSince(last) >= configuration.objectCooldown
    }

    private func phoneMovedRecently(_ now: Date) -> Bool {
        guard let lastPhoneMotionAt else { return false }
        return now.timeIntervalSince(lastPhoneMotionAt) < configuration.phoneSettleInterval
    }

    private static func announce(
        _ kind: VisionLiveGuideEventKind,
        record: inout VisionLiveObjectRecord,
        from: SpatialRegion?,
        to: SpatialRegion?,
        horizontalShift: Double = 0,
        verticalShift: Double = 0,
        now: Date
    ) -> VisionLiveGuideEvent {
        record.lastAnnouncedAt = now
        record.lastMentionedAt = now
        return VisionLiveGuideEvent(
            kind: kind,
            objectIdentifier: record.id,
            trackIdentifier: record.trackIdentifier,
            classIdentifier: record.classIdentifier,
            fromRegion: from,
            toRegion: to,
            horizontalShift: horizontalShift,
            verticalShift: verticalShift,
            isCertain: record.isCertain,
            occurredAt: now
        )
    }

    private func pruneLocked(now: Date) {
        records.removeAll { !$0.isVisible && now.timeIntervalSince($0.lastSeenAt) > configuration.memoryWindow }
        if records.count > configuration.maximumRecords {
            // Forget first the objects that left the view the longest time ago.
            let removable = records.filter { !$0.isVisible }.sorted { $0.lastSeenAt < $1.lastSeenAt }
            let forgotten = Set(removable.prefix(records.count - configuration.maximumRecords).map(\.id))
            records.removeAll { forgotten.contains($0.id) }
        }
        let cutoff = now.addingTimeInterval(-configuration.memoryWindow)
        recentEvents.removeAll { $0.occurredAt < cutoff }
    }

    private func clearLocked() {
        records.removeAll(keepingCapacity: false)
        recentEvents.removeAll(keepingCapacity: false)
        previousPose = nil
        lastPhoneMotionAt = nil
        lastFrameAt = nil
        frameInterval = 0.6
    }

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    // MARK: - Questions

    static let whereCues = [
        "ou est", "ou sont", "est ou", "sont ou", "ou se trouve", "ou elle est", "ou il est",
        "ou est elle", "ou est il", "ou l'as tu vue", "ou l'as tu vu", "ou tu l'as vue", "ou tu l'as vu",
        "ou est passee", "ou est passe", "c'est ou", "tu la vois", "tu le vois", "la vois tu", "le vois tu",
        "toujours la", "encore la", "elle est la", "il est la"
    ]
    static let seeCues = ["tu vois", "vois tu", "tu as vu", "as tu vu", "tu reperes"]
    static let sceneCues = [
        "qu'est ce que tu vois", "que vois tu", "tu vois quoi", "qu'est ce qu'il y a", "qu'y a t il",
        "il y a quoi", "qu'est ce qui est devant moi", "decris", "decris moi", "qu'est ce que tu observes"
    ]
    static let changeCues = [
        "qu'est ce qui a change", "qu'est ce qui a bouge", "qu'est ce qui a ete deplace",
        "qu'est ce qui s'est passe", "quoi de neuf", "du nouveau", "qu'as tu remarque",
        "qu'est ce que tu as remarque", "qu'est ce que je viens de deplacer", "qu'est ce que j'ai deplace",
        "qu'est ce que j'ai bouge", "qu'est ce que je viens de bouger", "qu'est ce qui vient de bouger"
    ]

    private enum Referent {
        case object(Int)
        case unseen(String)
        case nothingSeen
    }

    private func answerLocked(_ normalized: String, now: Date) -> String? {
        let padded = " \(normalized) "
        func has(_ cues: [String]) -> Bool { cues.contains { padded.contains(" \($0) ") } }
        let mentioned = VisionFrenchVocabulary.classesMentioned(in: normalized)
        let asksChange = has(Self.changeCues)
        let asksScene = has(Self.sceneCues)
        let asksWhere = has(Self.whereCues) || (!mentioned.isEmpty && has(Self.seeCues) && !asksScene)
        guard asksChange || asksScene || asksWhere else { return nil }

        guard observing else {
            return "Le guide en direct est arrêté : je n'observe plus rien. Relancez-le pour que je regarde."
        }
        if asksChange { return changeAnswer(now: now) }
        if asksWhere { return whereAnswer(referent(mentioned: mentioned, padded: padded), now: now) }
        return sceneAnswer(now: now)
    }

    private func referent(mentioned: [String], padded: String) -> Referent {
        if !mentioned.isEmpty {
            let candidates = records.indices.filter { mentioned.contains(records[$0].classIdentifier) }
            guard let index = candidates.max(by: { records[$0].lastSeenAt < records[$1].lastSeenAt }) else {
                return .unseen(mentioned[0])
            }
            return .object(index)
        }
        let ordered = records.indices.sorted { records[$0].lastMentionedAt > records[$1].lastMentionedAt }
        let wantsFeminine = [" elle ", " la vois ", " l'as tu vue ", " tu l'as vue ", " passee "].contains { padded.contains($0) }
        let wantsMasculine = [" il ", " le vois ", " l'as tu vu ", " tu l'as vu ", " passe "].contains { padded.contains($0) }
        if wantsFeminine, let index = ordered.first(where: { records[$0].noun.isFeminine }) {
            return .object(index)
        }
        if wantsMasculine, let index = ordered.first(where: { !records[$0].noun.isFeminine }) {
            return .object(index)
        }
        guard let index = ordered.first else { return .nothingSeen }
        return .object(index)
    }

    /// Seen in the last frame or so. A cup removed a moment ago is not claimed visible, even
    /// before its loss is announced.
    private func seenNow(_ record: VisionLiveObjectRecord, now: Date) -> Bool {
        record.isVisible && now.timeIntervalSince(record.lastSeenAt) <= max(0.9, 1.5 * frameInterval)
    }

    private func whereAnswer(_ referent: Referent, now: Date) -> String {
        switch referent {
        case .nothingSeen:
            return "Je n'ai encore repéré aucun objet depuis le début du guide en direct."
        case .unseen(let identifier):
            let noun = VisionFrenchVocabulary.noun(for: identifier)
            return "Je n'ai pas vu \(noun.partitiveAfterNegation) depuis le début du guide en direct."
        case .object(let index):
            records[index].lastMentionedAt = now
            let record = records[index]
            let noun = record.noun
            let place = record.region.spokenLocation
            if seenNow(record, now: now) {
                return record.isCertain
                    ? "\(noun.capitalizedDefinite) est \(place)."
                    : "Je crois voir \(noun.definite) \(place)."
            }
            let ago = Self.agoPhrase(now.timeIntervalSince(record.lastSeenAt))
            return "Je ne \(noun.objectPronoun) vois plus. Je l'ai \(noun.agreed("vu")) pour la dernière fois \(place), \(ago)."
        }
    }

    private func sceneAnswer(now: Date) -> String {
        let visible = records.indices
            .filter { seenNow(records[$0], now: now) }
            .sorted { Self.order(records[$0].region) < Self.order(records[$1].region) }
            .prefix(4)
        guard !visible.isEmpty else {
            return "Je ne détecte aucun objet connu pour le moment, mais je peux en manquer."
        }
        let parts = visible.map { "\(records[$0].noun.indefinite) \(records[$0].region.spokenLocation)" }
        let certain = visible.allSatisfy { records[$0].isCertain }
        for index in visible {
            records[index].lastMentionedAt = now
        }
        return (certain ? "Je vois " : "Je crois voir ") + Self.frenchList(Array(parts)) + "."
    }

    private func changeAnswer(now: Date) -> String {
        guard let last = recentEvents.last(where: { now.timeIntervalSince($0.occurredAt) <= 300 }) else {
            return "Je n'ai remarqué aucun changement depuis le début du guide en direct."
        }
        if let index = records.firstIndex(where: { $0.id == last.objectIdentifier }) {
            records[index].lastMentionedAt = now
        }
        let noun = VisionFrenchVocabulary.noun(for: last.classIdentifier)
        let ago = Self.agoPhrase(now.timeIntervalSince(last.occurredAt))
        let place = (last.toRegion ?? last.fromRegion ?? .center).spokenLocation
        switch last.kind {
        case .appeared:
            return "\(noun.indefinite.capitalizedFirstLetter) est \(noun.agreed("apparu")) \(place), \(ago)."
        case .reappeared:
            return "\(noun.capitalizedDefinite) est \(noun.agreed("revenu")) \(place), \(ago)."
        case .moved:
            return "\(noun.capitalizedDefinite) s'est \(noun.agreed("déplacé")) \(Self.movementPath(last)), \(ago)."
        case .approached:
            return "\(noun.capitalizedDefinite) semble s'être \(noun.agreed("rapproché")), \(ago)."
        case .receded:
            return "\(noun.capitalizedDefinite) semble s'être \(noun.agreed("éloigné")), \(ago)."
        case .gone:
            return "\(noun.capitalizedDefinite) a disparu de l'image \(ago) ; je l'avais \(noun.agreed("vu")) \(place)."
        }
    }

    // MARK: - French sentences

    /// What Live Guide says when the event happens.
    static func sentence(for event: VisionLiveGuideEvent) -> String {
        let noun = VisionFrenchVocabulary.noun(for: event.classIdentifier)
        let place = (event.toRegion ?? event.fromRegion ?? .center).spokenLocation
        switch event.kind {
        case .appeared:
            return (event.isCertain ? "Je vois " : "Je crois voir ") + "\(noun.indefinite) \(place)."
        case .reappeared:
            return "Je revois \(noun.definite) \(place)."
        case .moved:
            return "\(noun.capitalizedDefinite) s'est \(noun.agreed("déplacé")) \(movementPath(event))."
        case .approached:
            return "\(noun.capitalizedDefinite) semble s'être \(noun.agreed("rapproché"))."
        case .receded:
            return "\(noun.capitalizedDefinite) semble s'être \(noun.agreed("éloigné"))."
        case .gone:
            return "Je ne vois plus \(noun.definite)."
        }
    }

    /// One spoken line for the events of a frame (at most three, in the order they happened).
    static func narrationText(for events: [VisionLiveGuideEvent]) -> String {
        events.prefix(3).map(sentence(for:)).joined(separator: " ")
    }

    static func movementPath(_ event: VisionLiveGuideEvent) -> String {
        if let from = event.fromRegion, let to = event.toRegion, from != to {
            return "\(from.frenchFromPhrase) \(to.frenchTowardPhrase)"
        }
        if abs(event.horizontalShift) >= abs(event.verticalShift) {
            return event.horizontalShift >= 0 ? "vers la droite" : "vers la gauche"
        }
        return event.verticalShift >= 0 ? "vers le haut" : "vers le bas"
    }

    static func agoPhrase(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 5 { return "il y a quelques secondes" }
        if seconds < 60 { return "il y a \(seconds) secondes" }
        let minutes = seconds / 60
        return minutes == 1 ? "il y a une minute" : "il y a \(minutes) minutes"
    }

    static func frenchList(_ parts: [String]) -> String {
        guard parts.count > 1, let last = parts.last else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " et " + last
    }

    private static func order(_ region: SpatialRegion) -> Int {
        switch region {
        case .left: return 0
        case .center: return 1
        case .right: return 2
        }
    }
}
