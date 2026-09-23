import Foundation
import Testing
@testable import SynqCore

private var utc: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}

private func day(_ d: Int, hour: Int = 12) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 9, day: d, hour: hour))!
}

private func entry(_ body: String, on date: Date, type: EntryType = .text, transcript: String? = nil) -> JournalEntry {
    let id = UUID()
    return JournalEntry(id: id, filename: EntryFilename.make(id: id, date: date), createdAt: date,
                        body: body, entryType: type, transcript: transcript)
}

@Suite struct FilenameTests {
    @Test func roundTrips() {
        let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let name = EntryFilename.make(id: id, date: date)
        let parsed = EntryFilename.parse(name)
        #expect(parsed?.id == id)
        #expect(parsed?.date == date)
    }

    @Test func rejectsForeignFiles() {
        #expect(EntryFilename.parse("notes.md") == nil)
        #expect(EntryFilename.parse("[not-a-uuid]-[2026-01-01-00-00-00].md") == nil)
        #expect(EntryFilename.parse(".synqapp-pins.json") == nil)
    }

    @Test func videoNameMatchesMarkdownName() {
        #expect(EntryFilename.videoName(for: "[A]-[B].md") == "[A]-[B].mov")
    }
}

@Suite struct StatsTests {
    @Test func countsWords() {
        #expect(Stats.wordCount("") == 0)
        #expect(Stats.wordCount("  one\ttwo\n\nthree  ") == 3)
        #expect(Stats.wordCountLabel("solo") == "1 word")
    }

    @Test func readingTime() {
        #expect(Stats.readingTimeLabel("") == "")
        #expect(Stats.readingTimeLabel("word") == "~1 min read")
        #expect(Stats.readingTimeLabel(Array(repeating: "w", count: 500).joined(separator: " ")) == "~3 min read")
    }

    @Test func streakCountsBackFromToday() {
        let entries = [entry("a", on: day(20)), entry("b", on: day(21)), entry("c", on: day(22)), entry("old", on: day(10))]
        #expect(Stats.currentStreak(entries: entries, now: day(22, hour: 20), calendar: utc) == 3)
    }

    @Test func streakSurvivesUntilTodayIsWritten() {
        let entries = [entry("a", on: day(20)), entry("b", on: day(21))]
        #expect(Stats.currentStreak(entries: entries, now: day(22), calendar: utc) == 2)
        #expect(Stats.currentStreak(entries: entries, now: day(23), calendar: utc) == 0)
    }

    @Test func streakIgnoresEmptyEntriesButCountsVideo() {
        let entries = [entry("   ", on: day(22)), entry("Video Entry", on: day(21), type: .video, transcript: "spoken words")]
        #expect(Stats.currentStreak(entries: entries, now: day(22), calendar: utc) == 1)
    }

    @Test func dailyGoal() {
        let entries = [entry("one two three", on: day(22)), entry("four five", on: day(22)), entry("yesterday", on: day(21))]
        let today = Stats.todayWordCount(entries: entries, now: day(22), calendar: utc)
        #expect(today == 5)
        #expect(Stats.goalLabel(todayWords: today, goal: 10) == "5/10 today")
        #expect(Stats.goalProgress(todayWords: today, goal: 10) == 0.5)
        #expect(Stats.goalLabel(todayWords: 12, goal: 10) == "Goal reached ✓")
    }

    @Test func tags() {
        #expect(Stats.tags(in: "Gym day #Health and #work_2, not an#anchor or #1") == ["health", "work_2"])
        let entries = [entry("#a #b", on: day(1)), entry("#b", on: day(2))]
        #expect(Stats.allTags(in: entries) == ["b", "a"])
    }
}

@Suite struct SearchTests {
    @Test func findsTextAndTranscripts() {
        let written = entry("I went running by the river", on: day(20))
        let spoken = entry("Video Entry", on: day(21), type: .video, transcript: "Talking about the River trip and the river again")
        let results = Search.run(query: "river", in: [written, spoken])
        #expect(results.map(\.entry.id) == [spoken.id, written.id])
        #expect(results.first?.matchCount == 2)
    }

    @Test func emptyQueryFindsNothing() {
        #expect(Search.run(query: "  ", in: [entry("text", on: day(1))]).isEmpty)
    }

    @Test func snippetMarksTruncation() {
        let long = String(repeating: "a ", count: 60) + "needle" + String(repeating: " b", count: 60)
        let snippet = Search.run(query: "needle", in: [entry(long, on: day(1))]).first?.matchSnippet ?? ""
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.contains("needle"))
    }
}

@Suite struct ReflectionTests {
    @Test func sessionContextHasNoDuplicatedSystemPrompt() {
        let text = Reflection.context(scope: .session, currentText: "Rough day at work", entries: [])
        #expect(text == "Here is what I'm writing right now:\n\nRough day at work")
        #expect(!text.contains(Reflection.systemPrompt))
    }

    @Test func weekContextIsOldestFirstAndIncludesTranscripts() {
        let entries = [
            entry("Thursday thoughts", on: day(24)),
            entry("Video Entry", on: day(22), type: .video, transcript: "Tuesday spoken"),
            entry("Too old", on: day(1)),
            entry("  ", on: day(23)),
        ]
        let text = Reflection.context(scope: .week, currentText: "", entries: entries, now: day(25), calendar: utc)
        let tuesday = text.range(of: "Tuesday spoken")
        let thursday = text.range(of: "Thursday thoughts")
        #expect(tuesday != nil && thursday != nil)
        #expect(tuesday!.lowerBound < thursday!.lowerBound)
        #expect(!text.contains("Too old"))
        #expect(text.contains("(spoken, video entry)"))
    }

    @Test func emptyScopeInvitesWriting() {
        let text = Reflection.context(scope: .month, currentText: "", entries: [], now: day(25), calendar: utc)
        #expect(text.contains("haven't written anything for this month"))
    }

    @Test func recapNeedsEntries() {
        #expect(Reflection.recapRequest(entries: [], now: day(25), calendar: utc) == nil)
        let recap = Reflection.recapRequest(entries: [entry("Shipped the app", on: day(23))], now: day(25), calendar: utc)
        #expect(recap?.heading.hasPrefix("# Weekly recap") == true)
        #expect(recap?.message.contains("Shipped the app") == true)
    }

    @Test func plainTextStripsMarkdown() {
        let md = "# Title\n## Sub\nSome **bold** and _soft_ `code` and [a link](https://x.y)\nsnake_case_name stays"
        #expect(PlainText.fromMarkdown(md) == "Title\nSub\nSome bold and soft code and a link\nsnake_case_name stays")
    }
}

@Suite struct AIWireTests {
    private func body(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
    }

    @Test func anthropicRequestShape() throws {
        let req = AIRequest(provider: .anthropic, model: "claude-opus-5", apiKey: "k", system: "sys",
                            turns: [ChatTurn(.user, "hi"), ChatTurn(.assistant, "hey"), ChatTurn(.user, "more")])
        let request = try AIWire.urlRequest(for: req)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let json = body(request)
        #expect(json["system"] as? String == "sys")
        #expect(json["stream"] as? Bool == true)
        #expect(json["fallbacks"] as? String == "default")
        #expect((json["output_config"] as? [String: String])?["effort"] == "medium")
        let messages = json["messages"] as? [[String: String]]
        #expect(messages?.map { $0["role"]! } == ["user", "assistant", "user"])
    }

    @Test func haikuGetsNoEffortOrFallbacks() throws {
        let request = try AIWire.urlRequest(for: AIRequest(provider: .anthropic, model: "claude-haiku-4-5", apiKey: "k", system: "s", turns: [ChatTurn(.user, "x")]))
        let json = body(request)
        #expect(json["output_config"] == nil)
        #expect(json["fallbacks"] == nil)
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test func openAIRequestPutsSystemFirst() throws {
        let request = try AIWire.urlRequest(for: AIRequest(provider: .openAI, model: "gpt-4o-mini", apiKey: "k", system: "sys", turns: [ChatTurn(.user, "x")]))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        let messages = body(request)["messages"] as? [[String: String]]
        #expect(messages?.first == ["role": "system", "content": "sys"])
        #expect(messages?.count == 2)
    }

    @Test func missingKeyThrows() {
        #expect(throws: AIError.missingKey(.anthropic)) {
            try AIWire.urlRequest(for: AIRequest(provider: .anthropic, model: "m", apiKey: "", system: "", turns: []))
        }
    }

    @Test func parsesAnthropicEvents() {
        #expect(AIWire.parse(line: "event: content_block_delta", provider: .anthropic) == nil)
        #expect(AIWire.parse(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#, provider: .anthropic) == .text("Hel"))
        #expect(AIWire.parse(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#, provider: .anthropic) == nil)
        #expect(AIWire.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#, provider: .anthropic) == .refusal)
        #expect(AIWire.parse(line: #"data: {"type":"message_stop"}"#, provider: .anthropic) == .done)
        #expect(AIWire.parse(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#, provider: .anthropic) == .failure("Overloaded"))
    }

    @Test func parsesOpenAIEvents() {
        #expect(AIWire.parse(line: #"data: {"choices":[{"delta":{"content":"lo"}}]}"#, provider: .openAI) == .text("lo"))
        #expect(AIWire.parse(line: #"data: {"choices":[{"delta":{}}]}"#, provider: .openAI) == nil)
        #expect(AIWire.parse(line: "data: [DONE]", provider: .openAI) == .done)
    }
}

// MARK: - End-to-end streaming over a stubbed URLSession

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct AIClientTests {
    private var client: AIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return AIClient(session: URLSession(configuration: config))
    }

    private let req = AIRequest(provider: .anthropic, model: "claude-sonnet-5", apiKey: "k", system: "s", turns: [ChatTurn(.user, "hi")])

    @Test func streamsChunksInOrder() async throws {
        StubProtocol.status = 200
        StubProtocol.body = """
        event: message_start
        data: {"type":"message_start","message":{}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hey, "}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"thanks for sharing."}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        var chunks: [String] = []
        for try await chunk in client.stream(req) { chunks.append(chunk) }
        #expect(chunks == ["Hey, ", "thanks for sharing."])
    }

    @Test func surfacesHTTPErrors() async {
        StubProtocol.status = 401
        StubProtocol.body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        await #expect(throws: AIError.http(provider: .anthropic, status: 401, message: "invalid x-api-key")) {
            _ = try await client.complete(req)
        }
    }

    @Test func surfacesRefusal() async {
        StubProtocol.status = 200
        StubProtocol.body = #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"# + "\n"
        await #expect(throws: AIError.refused) {
            _ = try await client.complete(req)
        }
    }
}
