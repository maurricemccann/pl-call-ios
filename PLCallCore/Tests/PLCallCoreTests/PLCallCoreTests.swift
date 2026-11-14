import XCTest
@testable import PLCallCore

final class ConfigTests: XCTestCase {
    func testLoadsAndNormalisesBase() throws {
        let json = #"{"v":1,"line":{"base":"https://pc.example/call","certName":"pc.example"},"callKey":"abc"}"#
        let c = try PLCallConfig.load(Data(json.utf8))
        XCTAssertEqual(c.line.base, "https://pc.example/call/")
        XCTAssertEqual(c.startingVoice, "phone")
        XCTAssertEqual(c.endOfTurn, 0.9, accuracy: 0.001)
        XCTAssertFalse(c.usesSystemFont)
    }

    func testRejectsPlainHTTPAndMissingKey() {
        let http = #"{"v":1,"line":{"base":"http://pc/call/","certName":"pc"},"callKey":"abc"}"#
        XCTAssertThrowsError(try PLCallConfig.load(Data(http.utf8))) { XCTAssertEqual($0 as? PLCallConfig.Problem, .baseNotHTTPS) }
        let noKey = #"{"v":1,"line":{"base":"https://pc/call/","certName":"pc"},"callKey":"  "}"#
        XCTAssertThrowsError(try PLCallConfig.load(Data(noKey.utf8))) { XCTAssertEqual($0 as? PLCallConfig.Problem, .missingCallKey) }
        XCTAssertThrowsError(try PLCallConfig.load(Data("not json".utf8)))
    }
}

final class SSEParserTests: XCTestCase {
    func testBlankLineEndsAnEventAndCommentsAreIgnored() {
        var p = SSEParser()
        XCTAssertNil(p.feed(": keep-alive"))
        XCTAssertNil(p.feed("data: {\"a\":1}"))
        XCTAssertEqual(p.feed(""), SSEParser.Message(event: nil, data: "{\"a\":1}", id: nil))
        XCTAssertNil(p.feed(""))
    }

    func testMultiLineDataAndCRLF() {
        var p = SSEParser()
        _ = p.feed("event: x\r")
        _ = p.feed("data: one\r")
        _ = p.feed("data:two\r")
        XCTAssertEqual(p.feed("\r"), SSEParser.Message(event: "x", data: "one\ntwo", id: nil))
    }

    func testLineSplitterKeepsPartialLine() {
        var buf = ""
        XCTAssertEqual(SSEParser.lines(appending: "data: a\nda", to: &buf), ["data: a"])
        XCTAssertEqual(buf, "da")
        XCTAssertEqual(SSEParser.lines(appending: "ta: b\n\n", to: &buf), ["data: b", ""])
    }
}

final class ReducerTests: XCTestCase {
    func testSpeaksEveryWordOfTheTurnAtTurnEnd() {
        var r = EventReducer(lastSeq: 10)
        r.sent()
        XCTAssertEqual(r.ingest(SessionEvent(sequenceNum: 11, role: "assistant", text: "Working on it.")), [])
        XCTAssertEqual(r.ingest(SessionEvent(sequenceNum: 12, role: "assistant", text: "Done, the file is fixed.")), [])
        let whole = "Working on it.\n\nDone, the file is fixed."
        XCTAssertEqual(r.ingest(SessionEvent(sequenceNum: 13, type: "result")), [.transcript(whole), .speak(whole)])
        XCTAssertEqual(r.lastSaid, whole)
        XCTAssertFalse(r.waiting)
    }

    func testIgnoresOldEvents() {
        var r = EventReducer(lastSeq: 20)
        r.sent()
        XCTAssertEqual(r.ingest(SessionEvent(sequenceNum: 20, type: "result")), [])
        XCTAssertTrue(r.waiting)
    }

    func testPermissionAndQuestionAsks() throws {
        var r = EventReducer()
        r.sent()
        let permJSON = #"{"sequenceNum":5,"isBlockingControl":true,"requestId":"r1","toolUseId":"t1","permissionRequest":{"toolName":"Bash","input":{"command":"ls -la","description":"List the files"}}}"#
        let perm = try XCTUnwrap(SessionEvent.decode(permJSON))
        XCTAssertEqual(r.ingest(perm), [.ask(.permission(requestId: "r1", toolUseId: "t1", forWhat: "List the files", what: "ls -la"))])
        XCTAssertFalse(r.waiting)

        let qJSON = #"{"sequenceNum":6,"isBlockingControl":true,"requestId":"r2","permissionRequest":{"questions":[{"question":"Which?","header":"Pick","options":[{"label":"A"},{"label":"B"}]}],"input":{"x":1}}}"#
        let q = try XCTUnwrap(SessionEvent.decode(qJSON))
        let out = r.ingest(q)
        guard case .ask(.question(let rid, _, let question, let input))? = out.first else { return XCTFail("no question") }
        XCTAssertEqual(rid, "r2")
        XCTAssertEqual(question.options, ["A", "B"])
        XCTAssertEqual(input, .object(["x": .number(1)]))
    }

    func testPrimeSetsReplayAndResumePoint() {
        var r = EventReducer()
        r.prime([SessionEvent(sequenceNum: 3, role: "assistant", text: "First."), SessionEvent(sequenceNum: 4, role: "user", text: "hi")])
        XCTAssertEqual(r.lastSeq, 4)
        XCTAssertEqual(r.lastSaid, "First.")
    }
}

final class SpokenTextTests: XCTestCase {
    func testSkipsCodeTablesLinksAndPaths() {
        let text = """
        I fixed the bug. See [the docs](https://example.com/x).
        ```
        let x = 1
        ```
        | a | b |
        |---|---|
        The change is in `src/app/main.swift` and it builds now.
        """
        let r = SpokenText.make(text)
        XCTAssertTrue(r.skippedSomething)
        XCTAssertEqual(r.sentences.first, "I fixed the bug.")
        XCTAssertEqual(r.sentences.last, SpokenText.restOnScreen)
        XCTAssertFalse(r.sentences.joined().contains("let x"))
        XCTAssertFalse(r.sentences.joined().contains("src/app"))
        XCTAssertTrue(r.sentences.joined().contains("the docs"))
    }

    func testPlainTextHasNoTail() {
        let r = SpokenText.make("All done. Nothing else needed!")
        XCTAssertEqual(r.sentences, ["All done.", "Nothing else needed!"])
        XCTAssertFalse(r.skippedSomething)
    }

    func testEmptyBecomesDone() {
        XCTAssertEqual(SpokenText.make("   ").sentences, ["Done."])
    }
}

final class AnswerTests: XCTestCase {
    func testDecisions() {
        XCTAssertEqual(SpokenAnswer.decision("yes approve it"), true)
        XCTAssertEqual(SpokenAnswer.decision("no, deny"), false)
        XCTAssertNil(SpokenAnswer.decision("hmm"))
        XCTAssertNil(SpokenAnswer.decision("yes no"))
    }

    func testOptions() {
        let q = PermissionRequest.Question(question: "Which?", header: "H", options: ["Red", "Blue", "Green"])
        XCTAssertEqual(SpokenAnswer.option("option two", of: q), 1)
        XCTAssertEqual(SpokenAnswer.option("3", of: q), 2)
        XCTAssertEqual(SpokenAnswer.option("the blue one", of: q), 1)
        XCTAssertNil(SpokenAnswer.option("purple", of: q))
    }

    func testBodiesMatchThePage() throws {
        let p = BridgeBody.permission(requestId: "r", toolUseId: "t", allow: false, message: " use the other file ")
        let pj = String(decoding: BridgeBody.json(p), as: UTF8.self)
        XCTAssertEqual(pj, #"{"decision":"deny","message":"use the other file","request_id":"r","tool_use_id":"t"}"#)
        let noMsg = String(decoding: BridgeBody.json(BridgeBody.permission(requestId: "r", toolUseId: nil, allow: true, message: "  ")), as: UTF8.self)
        XCTAssertEqual(noMsg, #"{"decision":"allow","request_id":"r"}"#)

        let q = PermissionRequest.Question(question: "Which?", header: "H", options: ["A", "B"])
        let d = String(decoding: BridgeBody.json(BridgeBody.dialog(requestId: "r2", toolUseId: "t2", question: q, option: 1, input: .object(["x": .number(1)]))), as: UTF8.self)
        XCTAssertEqual(d, #"{"answers":[{"header":"H","options":["B"],"question":"Which?"}],"input":{"x":1},"request_id":"r2","status":"completed","subtype":"can_use_tool","tool_use_id":"t2"}"#)
    }
}

final class CallLaneEventTests: XCTestCase {
    func testPictureAndClearedApprovalEventsDecode() {
        let pic = SessionEvent.decode(#"{"sequenceNum":4,"role":"assistant","text":"look","image":"img/ab12cd34ef56.png"}"#)
        XCTAssertEqual(pic?.image, "img/ab12cd34ef56.png")
        let gone = SessionEvent.decode(#"{"sequenceNum":5,"role":"system","text":"","type":"permission_answered","requestId":"abcde","expired":true}"#)
        XCTAssertEqual(gone?.type, "permission_answered")
        XCTAssertEqual(gone?.requestId, "abcde")
        XCTAssertEqual(gone?.expired, true)
        XCTAssertNil(SessionEvent.decode(#"{"sequenceNum":6,"role":"user","text":"hi"}"#)?.image)
    }

    func testAClearedApprovalIsNotAnAskAndMovesTheSequence() {
        var r = EventReducer(lastSeq: 1)
        let gone = SessionEvent(sequenceNum: 2, role: "system", text: "", type: "permission_answered", requestId: "abcde", expired: true)
        XCTAssertEqual(r.ingest(gone), [])
        XCTAssertEqual(r.lastSeq, 2)
    }
}

final class QuickReplyTests: XCTestCase {
    func testArmedRepliesNeedASecondTapInThreeSeconds() {
        var arm = QuickReplyArm()
        let ship = PLCallConfig.QuickReply(label: "SHIP", send: "/ship", arm: true)
        let go = PLCallConfig.QuickReply(label: "PROCEED", send: "proceed", arm: false)
        XCTAssertEqual(arm.tap(go, now: 0), .send("proceed"))
        XCTAssertEqual(arm.tap(ship, now: 1), .armed("SHIP"))
        XCTAssertEqual(arm.tap(ship, now: 3.5), .send("/ship"))
        XCTAssertEqual(arm.tap(ship, now: 10), .armed("SHIP"))
        XCTAssertEqual(arm.tap(ship, now: 14), .armed("SHIP"))   // too late: re-arms
    }
}

final class HeardTests: XCTestCase {
    func testConfidenceIsTheWeakestStretch() {
        XCTAssertEqual(Heard.confidence([HeardSegment(text: "a", confidence: 0.9), HeardSegment(text: "b", confidence: 0.3), HeardSegment(text: "c")]), 0.3)
        XCTAssertNil(Heard.confidence([HeardSegment(text: "a")]))
    }

    func testUnsureOnlyWhenThereIsAConfidenceBelowTheThreshold() {
        XCTAssertTrue(Heard.isUnsure(confidence: 0.4, below: 0.5))
        XCTAssertFalse(Heard.isUnsure(confidence: 0.5, below: 0.5))
        XCTAssertFalse(Heard.isUnsure(confidence: nil, below: 0.5))
    }

    func testAlternativesSwapTheLeastSureStretchFirst() {
        let segments = [
            HeardSegment(text: "bring off all teachers", alternatives: ["turn on all features", "bring on all teachers", "bring off all teachers"], confidence: 0.2),
            HeardSegment(text: "please", alternatives: ["pleas"], confidence: 0.9),
        ]
        XCTAssertEqual(Heard.alternatives(segments), ["turn on all features please", "bring on all teachers please", "bring off all teachers pleas"])
        XCTAssertEqual(Heard.alternatives(segments, limit: 1), ["turn on all features please"])
        XCTAssertEqual(Heard.alternatives([HeardSegment(text: "the call", alternatives: ["The call", "the call"])]), [])
    }

    func testConfirmReplyTakesOnlyShortWholeAnswers() {
        XCTAssertEqual(ConfirmReply.parse("Yes."), .yes)
        XCTAssertEqual(ConfirmReply.parse("that\u{2019}s right"), .yes)
        XCTAssertEqual(ConfirmReply.parse("No"), .again)
        XCTAssertEqual(ConfirmReply.parse("try again"), .again)
        XCTAssertEqual(ConfirmReply.parse("yes turn on all features"), .other)
        XCTAssertEqual(ConfirmReply.parse("no I said the call"), .other)
    }

    func testSendBodyCarriesAlternativesOnlyWhenThereAreSome() throws {
        let plain = try JSONEncoder().encode(BridgeBody.send("hello"))
        XCTAssertEqual(String(decoding: plain, as: UTF8.self), #"{"text":"hello"}"#)
        let doubt = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BridgeBody.send("the ball", alt: ["the call", "a", "b", "c"], conf: 0.31))) as? [String: Any]
        XCTAssertEqual(doubt?["alt"] as? [String], ["the call", "a", "b"])
        XCTAssertEqual(doubt?["conf"] as? Double, 0.31)
    }
}
