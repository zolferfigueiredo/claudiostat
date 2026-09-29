# ClaudioStat

<img src="Icon/icon.png" width="128" alt="ClaudioStat icon">

Your Claude plan limits, live in the macOS menu bar.

```
★ S 42% · W 18% · F 7%
```

- **S**: current session
- **W**: this week, all models
- **F**: this week, Fable
- **P** (off by default, experimental): pace. How fast W is going: its rise over the last hour, times 24, to compare with L. Shows "-" until there's a reading from an hour ago.
- **L** (off by default): daily budget. What's left of the week split over the days until the weekly reset, a partial last day counting as a whole one, rounded down: 35% left with 1d 17h to go is 17%.

S and W change color when you're using them too fast. The needed pace is what's left spread evenly until the reset: S 50% with 2 hours left needs 25% per hour. W per day needs the daily budget, so it turns orange once the last 24 hours used more than L.

- **Orange**: faster than the needed pace. S is measured over the last 30 minutes, W per day over the last 24 hours (or per hour, like S).
- **Red**: 5 points per hour past it for S, 10 points past it for W.

The menu says why under a colored S or W: "Using 24% a day, 17% a day lasts until reset".

A warning triangle replaces the icon when Claude itself flags a limit: locked out, or its severity is anything but normal.

Click it for reset countdowns and settings: refresh interval, only refresh while the Claude app is open, icon and numbers, icon only or numbers only, the app icon (default) or a plain star icon, which of F, P and L to show (Data), pace warning mode (W per day, W per hour or off), and launch at login.

## Requirements

- macOS 15 or later, Apple Silicon or Intel
- [Claude Code](https://code.claude.com) installed and signed in with a Claude plan

## How it works

On every refresh, ClaudioStat runs your installed Claude Code once, headless, and asks it for its `/usage` data (the `get_usage` control request). No prompt is sent, so it costs zero tokens.

Claude Code uses its own login. ClaudioStat never sees or stores a credential. Hooks, plugins and MCP servers are off for that run, and nothing is saved as a session.

While "Only refresh while Claude is open" is on and the Claude desktop app is closed, ClaudioStat runs no usage refreshes and dims the last numbers.

## Updates

**Check for Updates…** in the menu asks claudiostat.zolfer.com for `latest.json`, a plain download that sends nothing about you. **Check automatically** does the same daily (the default), weekly or never. When there is a newer version, **Update Now** downloads it, replaces the copy in Applications and relaunches.

## Install

Open `ClaudioStat-<version>.dmg` and drag ClaudioStat to Applications.

## Build

```sh
./build.sh
```

It runs the tests, builds the app and writes `dist/ClaudioStat-<version>.dmg`. It needs Xcode 26 (Swift 6.2 or later). Every intermediate goes to a folder in `/tmp` that is deleted when the script ends.

To try a change, run `./run.sh`. It builds a debug copy in `/tmp/claudiostat-run`, quits any running ClaudioStat and opens the new one.

To release: bump both versions in `Info.plist` and run `./release.sh`. It builds `dist/ClaudioStat-<version>.dmg`, signs it with Developer ID and notarizes it. Then publish it from the website repo. Notarizing needs a one-time `xcrun notarytool store-credentials bihan --key <AuthKey.p8> --key-id <id> --issuer <issuer-id>`.

## Disclaimer

Unofficial. Not affiliated with or endorsed by Anthropic. It relies on an experimental Claude Code API that may change or stop working at any time.

## License

[MIT](LICENSE)
