import XCTest
@testable import JarvisXR

/// Free phrasing, the end of a turn, thinking aloud, interruptions and the PC brain's
/// commands (owner's test of 25/11: one wording per command, words lost, Jarvis that
/// cannot be interrupted, silences while it thinks).
final class JarvisConversationFlowTests: XCTestCase {
    // MARK: Free phrasing (same cases as pc/tests)

    func testFreePhrasingBecomesTheCommandsWording() {
        XCTAssertTrue(JarvisPhrasing.allPatternsCompile)
        let cases: [(String, String)] = [
            ("Est-ce que tu pourrais m'ouvrir YouTube, s'il te plaît ?", "ouvre-moi YouTube ?"),
            ("Jarvis, tu peux appeler maman ?", "appelle maman ?"),
            ("J'aimerais que tu appelles Paul", "appelle Paul"),
            ("Je voudrais que tu me rappelles d'acheter du pain", "rappelle-moi d'acheter du pain"),
            ("Tu peux me dire quelle heure il est ?", "quelle heure il est ?"),
            ("Je voudrais savoir quel temps il fait", "quel temps il fait"),
            ("Pourrais-tu me donner la météo ?", "donne-moi la météo ?"),
            ("Dis-moi ce qu'est l'arrêt Blanco", "qu'est-ce que l'arrêt Blanco"),
            ("Qu'est-ce que c'est, l'arrêt Blanco ?", "qu'est-ce que l'arrêt Blanco ?"),
            ("Tu connais l'arrêt Blanco ?", "parle-moi de l'arrêt Blanco ?"),
            ("Préviens Marie que je serai en retard", "dis à Marie que je serai en retard"),
            ("Envoie un texto à Paul pour lui dire que j'arrive", "envoie un message à Paul pour lui dire que j'arrive"),
            ("Va sur leboncoin.fr", "ouvre leboncoin.fr"),
            ("Tu peux te souvenir que je bois mon café noir ?", "souviens-toi que je bois mon café noir ?"),
            ("Ouvre YouTube, merci beaucoup !", "Ouvre YouTube !"),
            ("Euh, est-ce que tu peux mettre un minuteur de 10 minutes", "mets un minuteur de 10 minutes"),
            ("Tu peux m'appeler Tony", "appelle-moi Tony"),
        ]
        for (said, routed) in cases {
            XCTAssertEqual(JarvisPhrasing.rewrite(said), routed, said)
        }
        for unchanged in ["Pourquoi le ciel est-il bleu ?", "Je veux dormir", "Merci", "Non merci", "Bonjour Jarvis", "Jarvis",
                          "Tu connais mon nom ?", "Tu m'entends ?", "C'est quoi mon prénom ?", "Qu'est-ce que tu sais sur moi ?"] {
            XCTAssertEqual(JarvisPhrasing.rewrite(unchanged), unchanged, unchanged)
        }
    }

    func testTheRouterUnderstandsFreePhrasing() {
        let router = JarvisFrenchCommandRouter()
        guard case .answer(let call) = router.route("Est-ce que tu pourrais appeler Paul ?") else { return XCTFail("call") }
        XCTAssertEqual(call.data["action"], "phone_call")
        XCTAssertEqual(call.data["name"], "Paul")
        guard case .answer(let message) = router.route("Préviens Marie que je serai en retard") else { return XCTFail("message") }
        XCTAssertEqual(message.data["action"], "phone_message")
        XCTAssertEqual(message.data["name"], "Marie")
        XCTAssertEqual(message.data["body"], "je serai en retard")
        guard case .answer(let steps) = router.route("Tu peux me dire combien de pas j'ai fait aujourd'hui ?") else { return XCTFail("steps") }
        XCTAssertEqual(steps.data["action"], "steps")
        guard case .answer(let photo) = router.route("Pourrais-tu me montrer ma dernière photo ?") else { return XCTFail("photo") }
        XCTAssertEqual(photo.data["action"], "photos_show")
        guard case .answer(let pc) = router.route("Sur le PC, tu peux ouvrir YouTube ?") else { return XCTFail("pc") }
        XCTAssertEqual(pc.data["action"], "pc_command")
        // An open question still reaches the brain in the user's own words.
        guard case .openQuestion(let question) = router.route("Est-ce que tu pourrais m'expliquer la photosynthèse ?") else {
            return XCTFail("open question")
        }
        XCTAssertEqual(question, "Est-ce que tu pourrais m'expliquer la photosynthèse ?")
    }

    func testWikipediaSubjectsForTheArretBlanco() {
        for question in ["Qu'est-ce que l'arrêt Blanco ?", "C'est quoi l'arrêt Blanco ?", "Qu'est-ce que c'est, l'arrêt Blanco ?",
                         "Dis-moi ce qu'est l'arrêt Blanco", "Tu connais l'arrêt Blanco ?", "Explique-moi l'arrêt Blanco"] {
            XCTAssertEqual(JarvisWikipediaAnswer.subject(in: question), "l'arrêt Blanco", question)
        }
        XCTAssertNil(JarvisWikipediaAnswer.subject(in: "Explique-moi comment faire des crêpes"))
        XCTAssertNil(JarvisWikipediaAnswer.subject(in: "C'est quoi ton prénom ?"))
    }

    func testWikipediaSummaryKeepsWholeSentences() {
        let extract = "L'arrêt Blanco est un arrêt rendu en France le 8 février 1873 par le Tribunal des conflits. Souvent présenté comme le fondement du droit administratif français, il porte à la fois sur la compétence de la juridiction administrative et sur le contenu du droit administratif. L'arrêt reconnaît le service public comme le critère de la compétence de la juridiction administrative."
        let summary = JarvisWikipediaAnswer.summary(extract, limit: 260)
        XCTAssertTrue(summary.hasPrefix("L'arrêt Blanco est un arrêt rendu en France le 8 février 1873 par le Tribunal des conflits."))
        XCTAssertTrue(summary.hasSuffix("."))
        XCTAssertLessThanOrEqual(summary.count, 260)
        XCTAssertEqual(JarvisWikipediaAnswer.summary("Une seule phrase très longue sans fin claire", limit: 10), "Une seule phrase très longue sans fin claire")
    }

    // MARK: The end of a turn

    func testAFinishedSentenceEndsSoonerThanAnUnfinishedOne() {
        XCTAssertEqual(JarvisTurnEndDetector.silence(after: "Quelle heure est-il ?"), JarvisTurnEndDetector.finished)
        XCTAssertEqual(JarvisTurnEndDetector.silence(after: "Merci"), JarvisTurnEndDetector.finished)
        XCTAssertEqual(JarvisTurnEndDetector.silence(after: "Appelle"), JarvisTurnEndDetector.unfinished)
        XCTAssertEqual(JarvisTurnEndDetector.silence(after: "Envoie un message à"), JarvisTurnEndDetector.unfinished)
        XCTAssertEqual(JarvisTurnEndDetector.silence(after: "Rappelle-moi"), JarvisTurnEndDetector.unfinished)
        XCTAssertEqual(JarvisTurnEndDetector.silence(after: "Je voudrais savoir si demain il va pleuvoir et"), JarvisTurnEndDetector.unfinished)
        XCTAssertEqual(JarvisTurnEndDetector.silence(after: "Explique-moi pourquoi le ciel est bleu parce que"), JarvisTurnEndDetector.unfinished)
        XCTAssertEqual(JarvisTurnEndDetector.silence(after: "Mets un minuteur de 10 minutes"), JarvisTurnEndDetector.ordinary)
        XCTAssertEqual(JarvisTurnEndDetector.silence(after: "Appelle Paul"), JarvisTurnEndDetector.shortStart)
        XCTAssertLessThan(JarvisTurnEndDetector.finished, JarvisTurnEndDetector.ordinary)
        XCTAssertLessThan(JarvisTurnEndDetector.ordinary, JarvisTurnEndDetector.unfinished)
    }

    // MARK: Thinking aloud

    func testThinkingWordsFitTheQuestionAndNeverRepeat() {
        var filler = JarvisThinkingFiller()
        let first = filler.next(for: "Pourquoi le ciel est-il bleu ?")
        let second = filler.next(for: "Pourquoi la mer est-elle salée ?")
        XCTAssertTrue(JarvisThinkingFiller.general.contains(first))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(JarvisThinkingFiller.lookup.contains(filler.next(for: "Qui était Marie Curie ?")))
        XCTAssertTrue(JarvisThinkingFiller.calculation.contains(filler.next(for: "Combien font 128 fois 46 ?")))
    }

    // MARK: Interrupting Jarvis

    func testTheUserSpeakingOverJarvisIsHeardButNotAClick() {
        var detector = JarvisBargeInDetector()
        let buffer = 1024.0 / 48_000
        // Jarvis's residual echo while it speaks, then the user's voice for 0.3 s.
        for _ in 0..<40 { XCTAssertFalse(detector.ingest(level: -58, duration: buffer)) }
        var fired = 0
        for _ in 0..<15 where detector.ingest(level: -30, duration: buffer) { fired += 1 }
        XCTAssertEqual(fired, 1, "heard once")

        var clicks = JarvisBargeInDetector()
        for _ in 0..<40 { _ = clicks.ingest(level: -58, duration: buffer) }
        for _ in 0..<20 {
            XCTAssertFalse(clicks.ingest(level: -25, duration: buffer), "a single loud buffer is a click")
            for _ in 0..<6 { XCTAssertFalse(clicks.ingest(level: -60, duration: buffer)) }
        }
    }

    func testJarvisOwnWordsAreNotAnInterruption() {
        let spoken = "Le ciel apparaît bleu en raison de la diffusion de la lumière par l'atmosphère."
        XCTAssertFalse(JarvisEchoFilter.isInterruption("la diffusion de la lumière", spoken: spoken))
        XCTAssertTrue(JarvisEchoFilter.isInterruption("Attends, j'ai une autre question", spoken: spoken))
        XCTAssertTrue(JarvisEchoFilter.isInterruption("Stop", spoken: spoken))
        XCTAssertFalse(JarvisEchoFilter.isInterruption("euh", spoken: spoken))
        // Taking the floor back, even with words that Jarvis's reply also has.
        let answer = "Non, il ne pleut pas à Lyon, mais non loin de là il fait gris."
        XCTAssertTrue(JarvisEchoFilter.isInterruption("Non non", spoken: answer))
        XCTAssertTrue(JarvisEchoFilter.isInterruption("Laisse-moi finir", spoken: answer))
        XCTAssertTrue(JarvisEchoFilter.isInterruption("c'est pas ça", spoken: answer))
        XCTAssertFalse(JarvisEchoFilter.isInterruption("mais non loin", spoken: answer), "the reply's own « mais non »")
    }

    func testAnInterruptionIsGivenToTheBrainOnce() {
        let conversation = JarvisConversationContext()
        conversation.noteInterruption(spoken: "Il fait beau à Paris aujourd'hui")
        XCTAssertTrue(conversation.brainContextLines().contains { $0.contains("interrompu") && $0.contains("Il fait beau à Paris") })
        conversation.recordTurn(user: "Non, à Lyon", assistant: "À Lyon, il pleut.")
        XCTAssertFalse(conversation.brainContextLines().contains { $0.contains("interrompu") })
    }

    // MARK: Commands from the PC's brain

    func testThePCBrainCommandIsReadAndNeverSpoken() {
        XCTAssertEqual(JarvisBrainCommand.parse("COMMANDE: envoie un message à Marie pour lui dire que je serai en retard"),
                       "envoie un message à Marie pour lui dire que je serai en retard")
        XCTAssertEqual(JarvisBrainCommand.parse("Commande : « appelle Paul »\nautre"), "appelle Paul")
        XCTAssertNil(JarvisBrainCommand.parse("Comme vous voudrez."))
        XCTAssertTrue(JarvisBrainCommand.mayBeCommand("COM"))
        XCTAssertTrue(JarvisBrainCommand.mayBeCommand("COMMANDE: app"))
        XCTAssertFalse(JarvisBrainCommand.mayBeCommand("Comme"))
        let body = JarvisPCLink.askBody(question: "Préviens Marie", history: [], context: [], commands: true)
        XCTAssertEqual(body["commands"] as? String, "iphone")
        XCTAssertNil(JarvisPCLink.askBody(question: "Bonjour", history: [], context: [], commands: false)["commands"])
    }
}
