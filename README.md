# SynqApp

A quiet, native macOS journal. Write in plain Markdown, then talk it through with Claude or OpenAI, by typing or out loud.

Requires macOS 14 Sonoma or later.

## Features

- **Writing modes.** Flow, Focus (dims every paragraph except the current one), Typewriter (keeps the current line centred) and Zen (hides everything; press Esc to leave). Switch with ⌘1 to ⌘4.
- **Your files.** Every entry is a Markdown file. Choose the folder in Settings → Storage. Pick a folder in iCloud Drive to sync across Macs.
- **Reflect.** Discuss the current entry, your week or your month with Claude (Opus 5, Sonnet 5, Haiku 4.5) or OpenAI. Replies stream in as they are written. In voice mode you speak, SynqApp transcribes on your Mac, and it reads the reply aloud.
- **Weekly recap.** Writes an AI summary of your week into a new entry.
- **Quick capture.** Press ⌥Space in any app to jot a note. No Accessibility permission is needed. It is also available from the menu bar icon.
- **Video entries.** Record from the camera. SynqApp transcribes the video so it can be searched and reflected on.
- **Insights.** The sidebar shows your streak, entries, words and days journaled this year, and word counts for the last 7 days.
- **Search and tags.** Search entries and video transcripts. Filter by `#tags`.
- **Export.** Export one entry as PDF, Markdown or plain text, or the whole journal as a ZIP.

## Privacy

Entries stay on your Mac, in the folder you choose. API keys are kept in the Keychain. An entry is sent to the AI provider you pick only when you use Reflect or a recap. Speech recognition runs on your Mac when the Mac supports it.

## Build

Open `synqapp.xcodeproj` in Xcode 16 or later and run the `synqapp` scheme. To build from the command line:

```sh
scripts/build.sh --run
```

## Code layout

| Path | Contents |
|---|---|
| `SynqCore/` | Swift package with the logic that doesn't need the UI: entries and file names, stats and insights, search, reflection prompts, and the Claude/OpenAI streaming client. |
| `synqapp/Services/` | Files and storage folder, Keychain, preferences, global hotkey, PDF export, voice session. |
| `synqapp/Views/` | SwiftUI views: sidebar, editor (`WritingTextView`, built on `NSTextView`), Reflect, Settings, video, quick capture. |

## Tests

```sh
cd SynqCore && swift test
```
