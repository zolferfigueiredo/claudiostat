# Claudiostat

<img src="Icon/icon.png" width="128" alt="Claudiostat icon">

Your Claude plan limits, live in the macOS menu bar.

```
S 42% · W 18% · F 7% · L 12%
```

- **S**: current session
- **W**: this week, all models
- **F**: this week, Fable
- **L**: daily budget. What's left of the week, spread evenly per 24 hours until the weekly reset, rounded up.

Click it for reset countdowns and settings: refresh interval, show or hide F and L, only refresh while the Claude app is open, and launch at login.

## Requirements

- macOS 15 or later, Apple Silicon
- [Claude Code](https://code.claude.com) installed and signed in with a Claude plan

## How it works

On every refresh, Claudiostat runs your installed Claude Code once, headless, and asks it for its `/usage` data (the `get_usage` control request). No prompt is sent, so it costs zero tokens.

Claude Code uses its own login. Claudiostat never sees or stores a credential. Hooks, plugins and MCP servers are off for that run, and nothing is saved as a session.

While "Only refresh while Claude is open" is on and the Claude desktop app is closed, Claudiostat makes no requests at all and dims the last numbers.

## Install

1. Open `Claudiostat.dmg` and drag Claudiostat to Applications.
2. The app is not notarized, so the first launch of a downloaded copy is blocked. Open System Settings > Privacy & Security, scroll down, click **Open Anyway** next to Claudiostat and confirm. You only do this once.

## Build

```sh
./build.sh
```

It runs the tests, builds the app and writes `dist/Claudiostat.dmg`. It needs Xcode 26 (Swift 6.2 or later). Every intermediate goes to a folder in `/tmp` that is deleted when the script ends.

## Disclaimer

Unofficial. Not affiliated with or endorsed by Anthropic. It relies on an experimental Claude Code API that may change or stop working at any time.

## License

[MIT](LICENSE)
