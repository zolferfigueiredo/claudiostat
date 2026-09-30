# ClaudioStat

<img src="Icon/icon.png" width="128" alt="ClaudioStat icon">

Your Claude plan limits, live in the macOS menu bar.

<pre><img src="Icon/icon.png" width="18" align="absmiddle" alt="ClaudioStat icon"> S 42% · W 18% · F 7%</pre>

- **S**: current session
- **W**: this week, all models
- **F**: this week, Fable
- **P** (off by default, experimental): pace. How fast W is rising over the last hour, per day (times the working time, 8 hours by default) or per hour, following the pace warning mode. Shows "-" until there's a reading from an hour ago. After a pause, the rise is spread over the whole gap.
- **D** (off by default): budget, **H** when pace warning mode is per hour. What's left of the week split over the days (or working hours) until the weekly reset, a partial last one counting in full, rounded down: 35% left with 1d 17h to go is 17% a day, or 0.8% an hour with a 24-hour working time. The menu shows P and the budget too, and per hour says how many working hours it is spread over.

S and W change color when you're using them too fast.

- **S**: its rise over the last 30 minutes against what's left spread evenly until the reset: S 50% with 2 hours left needs 25% per hour.
- **W**: P against D, so it turns orange once P is over D.
- **Orange**: faster than needed. **Red**: 5 points per hour past it for S, 10 points past it for W.

The menu says why under a colored S or W: "Using 24% a day, 17% a day lasts until reset".

A warning triangle replaces the icon when Claude itself flags a limit: locked out, or its severity is anything but normal.

Click it for reset countdowns and settings: refresh interval, only refresh while the Claude app is open, icon and numbers, icon only or numbers only, the app icon (default) or a plain star icon, which of F, P and D to show (Data), pace warning mode (W per day, W per hour or off), daily working time (the hours a day you use Claude, 24 down to 4, 8 by default, so P and D leave out the rest of the day), notifications (a limit reached, its reset, the week at 80% and 90%, all on by default), launch at login, and keep in Dock.

## Requirements

- macOS 15 or later, Apple Silicon or Intel
- [Claude Code](https://code.claude.com) installed and signed in with a Claude plan

## How it works

On every refresh, ClaudioStat runs your installed Claude Code once, headless, and asks it for its `/usage` data (the `get_usage` control request). No prompt is sent, so it costs zero tokens.

Claude Code uses its own login. ClaudioStat never sees or stores a credential. Hooks, plugins and MCP servers are off for that run, and nothing is saved as a session.

While "Only refresh while Claude is open" is on and the Claude desktop app is closed, ClaudioStat runs no usage refreshes and dims the last numbers.

## Updates

**Check for updates…** in the menu asks claudiostat.zolfer.com for `latest.json`, a plain download that sends nothing about you. **Check automatically** does the same daily, weekly (the default) or never. When there is a newer version, **Update Now** downloads it, replaces the copy in Applications and relaunches.

## Install

Open `ClaudioStat-<version>.dmg` and drag ClaudioStat to Applications.

## Build

```sh
./build.sh
```

It runs the tests, builds the app and writes `dist/ClaudioStat-<version>.dmg`. It needs Xcode 26 (Swift 6.2 or later). Every intermediate goes to a folder in `/tmp` that is deleted when the script ends.

To try a change, run `./run.sh`. It builds a debug copy in `/tmp/claudiostat-run`, quits any running ClaudioStat and opens the new one.

To release: bump both versions in `Info.plist` and run `./release.sh`. It builds `dist/ClaudioStat-<version>.dmg`, signs it with Developer ID and notarizes it. Then publish it from the website repo. `./release.sh --url` also makes the permanent url.zolfer.com download link. Notarizing needs a one-time `xcrun notarytool store-credentials bihan --key <AuthKey.p8> --key-id <id> --issuer <issuer-id>`.

## Disclaimer

Unofficial. Not affiliated with or endorsed by Anthropic. It relies on an experimental Claude Code API that may change or stop working at any time.

## License

[MIT](LICENSE)
