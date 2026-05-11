
//  WritingPromptsService.swift
//  SynqApp — on-demand writing prompts

import Foundation

final class WritingPromptsService {

    static let shared = WritingPromptsService()
    private init() {}

    private var lastIndex: Int = -1

    static let prompts: [String] = [
        "What's something you've been avoiding thinking about?",
        "Describe the last hour honestly.",
        "What do you wish you'd said?",
        "What made you feel something today?",
        "What's the thing you keep coming back to?",
        "Write about a decision you're sitting with.",
        "What would you tell yourself from a year ago?",
        "What are you pretending not to know?",
        "Describe a moment from today in detail.",
        "What's something you're grateful for that you rarely say out loud?",
        "What's been draining you lately?",
        "Write about something that surprised you recently.",
        "What do you want more of in your life right now?",
        "What's a belief you've changed your mind about?",
        "Write about a conversation you keep replaying.",
        "What are you most afraid of right now?",
        "What does a good day look like for you?",
        "Write about something you're proud of that no one knows about.",
        "What's something you need to forgive yourself for?",
        "What would you do if you knew you couldn't fail?",
        "Describe your current mood without using emotion words.",
        "What's a small thing that's been bothering you?",
        "Write about someone who influenced you recently.",
        "What's something you want to remember about today?",
        "What are you overthinking right now?",
        "Write about a goal you've been putting off.",
        "What's something you've learned about yourself this week?",
        "What do you need right now that you're not getting?",
        "Write about a place that makes you feel calm.",
        "What's a habit you want to build or break?"
    ]

    func randomPrompt() -> String {
        var index: Int
        repeat {
            index = Int.random(in: 0..<Self.prompts.count)
        } while index == lastIndex && Self.prompts.count > 1
        lastIndex = index
        return Self.prompts[index]
    }
}
