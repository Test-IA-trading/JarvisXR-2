import XCTest
@testable import JarvisXR

/// Scenario 4 of the checklist, frame by frame: a real cup is announced once, its move is
/// reported once it rests, turning the phone is not a move, removing it is noticed, and
/// « Elle est où maintenant ? » is answered from what was seen. All in French.
final class VisionLiveGuideFrenchTests: XCTestCase {
    private var engine: VisionLiveGuideEngine!
    private var clock: Date!
    private let cupTrack = UUID()

    override func setUp() {
        super.setUp()
        engine = VisionLiveGuideEngine()
        engine.begin()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func box(centerX: Double, centerY: Double = 0.5, size: Double = 0.2) -> NormalizedRect {
        NormalizedRect(x: centerX - size / 2, y: centerY - size / 2, width: size, height: size)
    }

    private func cup(
        at centerX: Double,
        track: UUID? = nil,
        confirmed: Bool = true,
        certain: Bool = true
    ) -> VisionLiveGuideSighting {
        VisionLiveGuideSighting(
            trackIdentifier: track ?? cupTrack,
            classIdentifier: "cup",
            box: box(centerX: centerX),
            isConfirmed: confirmed,
            isCertain: certain
        )
    }

    /// One analysed frame, 0.6 s after the previous one (a typical Live Guide cadence).
    @discardableResult
    private func frame(_ sightings: [VisionLiveGuideSighting], pose: VisionCameraPose? = .level) -> [VisionLiveGuideEvent] {
        clock = clock.addingTimeInterval(0.6)
        return engine.update(sightings: sightings, pose: pose, at: clock)
    }

    @discardableResult
    private func frames(
        _ count: Int,
        _ sightings: [VisionLiveGuideSighting],
        pose: VisionCameraPose? = .level
    ) -> [VisionLiveGuideEvent] {
        (0..<count).flatMap { _ in frame(sightings, pose: pose) }
    }

    // MARK: Scenario 4

    func testCupIsAnnouncedOnceAndThenSilenceWhileItStaysStill() {
        let first = frame([cup(at: 0.5)])
        XCTAssertEqual(first.map(\.kind), [.appeared])
        XCTAssertEqual(VisionLiveGuideEngine.narrationText(for: first), "Je vois une tasse au centre.")
        XCTAssertTrue(frames(15, [cup(at: 0.5)]).isEmpty, "A still cup is not announced again.")
    }

    func testUncertainCupIsAnnouncedWithHedging() {
        let first = frame([cup(at: 0.5, certain: false)])
        XCTAssertEqual(VisionLiveGuideEngine.narrationText(for: first), "Je crois voir une tasse au centre.")
    }

    func testDetectorFlickerAndANewTrackDoNotRepeatTheAnnouncement() {
        frame([cup(at: 0.5)])
        frames(2, [])
        let newTrack = UUID()
        var events = frames(2, [cup(at: 0.52, track: newTrack, confirmed: false)])
        events += frames(5, [cup(at: 0.52, track: newTrack)])
        XCTAssertTrue(events.isEmpty, "Flicker must stay silent, got \(events.map(\.kind))")
        XCTAssertEqual(engine.objects.count, 1)
    }

    func testCupMovedToTheRightIsReportedOnceItRests() {
        frame([cup(at: 0.5)])
        frames(3, [cup(at: 0.5)])
        var events = frame([cup(at: 0.6)])
        events += frame([cup(at: 0.7)])
        events += frame([cup(at: 0.8)])
        XCTAssertTrue(events.isEmpty, "Nothing is said while the cup is still being carried.")
        events = frames(3, [cup(at: 0.8)])
        XCTAssertEqual(events.map(\.kind), [.moved])
        XCTAssertEqual(VisionLiveGuideEngine.narrationText(for: events), "La tasse s'est déplacée du centre vers la droite.")
        XCTAssertTrue(frames(10, [cup(at: 0.8)]).isEmpty, "Once settled it is not reported again.")
    }

    func testCupCarriedOutOfSightIsReportedAsMovedNotAsANewCup() {
        frame([cup(at: 0.2)])
        frames(3, [cup(at: 0.2)])
        frames(2, [])
        let newTrack = UUID()
        var events = frames(2, [cup(at: 0.8, track: newTrack, confirmed: false)])
        events += frames(4, [cup(at: 0.8, track: newTrack)])
        XCTAssertEqual(events.map(\.kind), [.moved], "\(events.map(\.kind))")
        XCTAssertEqual(VisionLiveGuideEngine.narrationText(for: events), "La tasse s'est déplacée de la gauche vers la droite.")
        XCTAssertEqual(engine.objects.count, 1)
    }

    func testTurningThePhoneIsNotReportedAsTheCupMoving() {
        frame([cup(at: 0.5)])
        frames(3, [cup(at: 0.5)])
        var events = frame([cup(at: 0.6)], pose: .turned(by: 3))
        events += frame([cup(at: 0.7)], pose: .turned(by: 6))
        events += frame([cup(at: 0.75)], pose: .turned(by: 7))
        events += frames(6, [cup(at: 0.75)], pose: .turned(by: 7))
        XCTAssertTrue(events.isEmpty, "The phone moved, not the cup: \(events.map(\.kind))")

        events = frame([cup(at: 0.6)], pose: .turned(by: 7))
        events += frame([cup(at: 0.45)], pose: .turned(by: 7))
        events += frames(3, [cup(at: 0.45)], pose: .turned(by: 7))
        XCTAssertEqual(events.map(\.kind), [.moved], "A real move after the phone settled is still reported.")
        XCTAssertEqual(VisionLiveGuideEngine.narrationText(for: events), "La tasse s'est déplacée de la droite vers le centre.")
    }

    func testShakingThePhoneIsNotReportedAsAMove() {
        frame([cup(at: 0.5)])
        frames(3, [cup(at: 0.5)])
        var events = frame([cup(at: 0.75)], pose: VisionCameraPose(x: 0, y: 0, z: 0, w: 1, peakAcceleration: 0.4))
        events += frames(6, [cup(at: 0.75)])
        XCTAssertTrue(events.isEmpty, "A jolt of the phone is not the cup moving: \(events.map(\.kind))")
    }

    func testRemovedCupIsReportedGoneAndLocatedFromMemory() throws {
        frame([cup(at: 0.8)])
        frames(3, [cup(at: 0.8)])
        XCTAssertEqual(engine.answer(to: "Elle est où maintenant ?", at: clock), "La tasse est à droite.")
        let events = frames(6, [])
        XCTAssertEqual(events.map(\.kind), [.gone])
        XCTAssertEqual(VisionLiveGuideEngine.narrationText(for: events), "Je ne vois plus la tasse.")
        let answer = try XCTUnwrap(engine.answer(to: "Elle est où maintenant ?", at: clock))
        XCTAssertTrue(
            answer.hasPrefix("Je ne la vois plus. Je l'ai vue pour la dernière fois à droite, il y a"),
            answer
        )
    }

    func testJustRemovedCupIsNotClaimedVisible() throws {
        frame([cup(at: 0.8)])
        frames(3, [cup(at: 0.8)])
        frames(2, [])
        let answer = try XCTUnwrap(engine.answer(to: "Elle est où ?", at: clock))
        XCTAssertTrue(answer.hasPrefix("Je ne la vois plus."), "Before the loss is announced, it is still not claimed visible: \(answer)")
    }

    func testCupPutBackIsAnnouncedAsSeenAgain() {
        frame([cup(at: 0.5)])
        frames(3, [cup(at: 0.5)])
        XCTAssertEqual(frames(6, []).map(\.kind), [.gone])
        let back = frames(5, [cup(at: 0.3, track: UUID())])
        XCTAssertEqual(back.map(\.kind), [.reappeared])
        XCTAssertEqual(VisionLiveGuideEngine.narrationText(for: back), "Je revois la tasse à gauche.")
    }

    func testStoppingForgetsTheSceneAndSaysSo() {
        frame([cup(at: 0.5)])
        engine.end()
        XCTAssertTrue(engine.objects.isEmpty)
        XCTAssertTrue(frame([cup(at: 0.5)]).isEmpty, "A stopped guide neither observes nor announces.")
        XCTAssertEqual(
            engine.answer(to: "Elle est où maintenant ?", at: clock),
            "Le guide en direct est arrêté : je n'observe plus rien. Relancez-le pour que je regarde."
        )
        XCTAssertNil(engine.answer(to: "Mets un minuteur de 5 minutes", at: clock), "Other sentences go to the other commands.")
    }

    // MARK: Questions

    func testPronounsAndNamesFindTheRightObject() {
        let book = VisionLiveGuideSighting(
            trackIdentifier: UUID(),
            classIdentifier: "book",
            box: box(centerX: 0.2),
            isConfirmed: true,
            isCertain: true
        )
        frame([cup(at: 0.8), book])
        frames(2, [cup(at: 0.8), book])
        XCTAssertEqual(engine.answer(to: "Il est où ?", at: clock), "Le livre est à gauche.")
        XCTAssertEqual(engine.answer(to: "Et elle, elle est où ?", at: clock), "La tasse est à droite.")
        XCTAssertEqual(engine.answer(to: "Où est mon livre ?", at: clock), "Le livre est à gauche.")
        XCTAssertEqual(
            engine.answer(to: "Tu vois mon téléphone ?", at: clock),
            "Je n'ai pas vu de téléphone depuis le début du guide en direct."
        )
        XCTAssertEqual(engine.answer(to: "Qu'est-ce que tu vois ?", at: clock), "Je vois un livre à gauche et une tasse à droite.")
    }

    func testWhatChangedDescribesTheLastEvent() {
        frame([cup(at: 0.5)])
        frames(3, [cup(at: 0.5)])
        frames(3, [cup(at: 0.2)])
        XCTAssertEqual(
            engine.answer(to: "Qu'est-ce qui a bougé ?", at: clock),
            "La tasse s'est déplacée du centre vers la gauche, il y a quelques secondes."
        )
    }

    func testNothingSeenYetIsSaidHonestly() {
        XCTAssertEqual(
            engine.answer(to: "Elle est où ?", at: clock),
            "Je n'ai encore repéré aucun objet depuis le début du guide en direct."
        )
        XCTAssertEqual(
            engine.answer(to: "Qu'est-ce que tu vois ?", at: clock),
            "Je ne détecte aucun objet connu pour le moment, mais je peux en manquer."
        )
    }

    func testObjectWordsInQuestions() {
        func classes(_ text: String) -> [String] {
            VisionFrenchVocabulary.classesMentioned(in: JarvisFrenchCommandRouter.normalize(text))
        }
        XCTAssertEqual(classes("Où est la tasse sur la table ?"), ["cup", "diningtable"])
        XCTAssertEqual(classes("Tu vois mon mug ?"), ["cup"])
        XCTAssertEqual(classes("Où est le verre à pied ?"), ["wine glass"])
        XCTAssertEqual(classes("Où est mon ordinateur portable ?"), ["laptop"])
        XCTAssertEqual(classes("Elle est où maintenant ?"), [])
    }

    func testFrenchSearchPhrasesPickTheObjectToFind() {
        func target(_ text: String) -> String? {
            VisionFrenchVocabulary.findTarget(inNormalized: JarvisFrenchCommandRouter.normalize(text))
        }
        XCTAssertEqual(target("Trouve la tasse"), "cup")
        XCTAssertEqual(target("Cherche mon téléphone"), "cell phone")
        XCTAssertEqual(target("Où est la bouteille ?"), "bottle")
        XCTAssertNil(target("Trouve-moi une idée"), "No known object: no Find.")
        XCTAssertNil(target("La tasse est jolie"), "No search verb: no Find.")
    }

    // MARK: French wording and safety

    func testFrenchNounsAgreeAndElide() {
        XCTAssertEqual(VisionFrenchVocabulary.noun(for: "laptop").definite, "l'ordinateur portable")
        XCTAssertEqual(VisionFrenchVocabulary.noun(for: "hot dog").definite, "le hot-dog")
        XCTAssertEqual(VisionFrenchVocabulary.noun(for: "clock").definite, "l'horloge")
        XCTAssertEqual(VisionFrenchVocabulary.noun(for: "cup").indefinite, "une tasse")
        XCTAssertEqual(VisionFrenchVocabulary.noun(for: "cup").agreed("déplacé"), "déplacée")
        XCTAssertEqual(VisionFrenchVocabulary.noun(for: "book").agreed("déplacé"), "déplacé")
        XCTAssertEqual(VisionFrenchVocabulary.noun(for: "laptop").partitiveAfterNegation, "d'ordinateur portable")
        XCTAssertEqual(SpatialRegion.right.spokenLocation, "à droite")
        XCTAssertTrue(
            VisionClassCatalog.rawIdentifiers.allSatisfy { VisionFrenchVocabulary.nouns[$0] != nil },
            "Every detector class has a French name."
        )
    }

    func testFrenchUnsafeClaimsAreBlocked() {
        let policy = VisionSafetyPolicy()
        for unsafe in [
            "Le chemin est libre.",
            "Vous pouvez traverser.",
            "La voie est libre.",
            "Il n'y a aucun obstacle.",
            "La tasse est à 2 mètres.",
            "C'est certainement une chaise."
        ] {
            XCTAssertFalse(policy.validateNarration(unsafe).isAllowed, unsafe)
        }
        for safe in [
            "Je vois une tasse au centre.",
            "La tasse s'est déplacée du centre vers la droite.",
            "Je ne vois plus la tasse.",
            "Je ne la vois plus. Je l'ai vue pour la dernière fois à droite, il y a 6 secondes."
        ] {
            XCTAssertTrue(policy.validateNarration(safe).isAllowed, safe)
        }
        XCTAssertEqual(
            policy.safeNarration("Vous pouvez traverser."),
            "Je ne peux pas donner de description fiable à partir de cette image."
        )
    }

    func testEveryLiveGuideSentenceIsSafe() {
        let policy = VisionSafetyPolicy()
        let kinds: [VisionLiveGuideEventKind] = [.appeared, .reappeared, .moved, .approached, .receded, .gone]
        for kind in kinds {
            for identifier in ["cup", "person", "car", "laptop"] {
                let event = VisionLiveGuideEvent(
                    kind: kind,
                    objectIdentifier: UUID(),
                    trackIdentifier: UUID(),
                    classIdentifier: identifier,
                    fromRegion: .left,
                    toRegion: .right,
                    horizontalShift: 0.4,
                    verticalShift: 0,
                    isCertain: false,
                    occurredAt: Date()
                )
                let text = VisionLiveGuideEngine.sentence(for: event)
                XCTAssertTrue(policy.validateNarration(text).isAllowed, text)
            }
        }
    }

    func testLiveGuideUsesTheDetectorBoxNotTheSmoothedOne() {
        let raw = ObjectObservation(classIdentifier: "cup", confidence: 0.9, boundingBox: box(centerX: 0.8))
        var tracked = TrackedObservation(
            trackIdentifier: UUID(),
            observation: raw,
            smoothedBoundingBox: box(centerX: 0.6),
            smoothedConfidence: 0.9,
            firstSeenAt: clock,
            lastSeenAt: clock,
            consecutiveFrameCount: 1,
            missedFrameCount: 0,
            isConfirmed: true,
            lastAnnouncedAt: nil
        )
        tracked.observation.boundingBox = box(centerX: 0.6)
        let update = TrackingUpdate(active: [tracked], confirmed: [tracked], changes: [], timestamp: clock)
        let sightings = VisionPipelineCoordinator.liveGuideSightings(
            tracking: update,
            detections: [raw],
            policy: VisionSafetyPolicy()
        )
        XCTAssertEqual(sightings.first?.box.centerX ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(sightings.first?.isConfirmed, true, "A confirmed track stays speakable after a missed frame.")
        XCTAssertEqual(sightings.first?.isCertain, true)
    }
}
