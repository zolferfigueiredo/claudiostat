<p align="center">
  <img src="Icon/icon.png" width="128" height="128" alt="ClaudioStat icon">
</p>

<h1 align="center">ClaudioStat</h1>

<h3 align="center">Your limits. Zero tokens.</h3>

<p align="center">
  Your Claude plan limits, live in the macOS menu bar.<br>
  A refresh costs zero tokens and never touches your login.
</p>

<p align="center">
  <a href="https://github.com/zolferfigueiredo/claudiostat/releases/latest"><img src="https://img.shields.io/github/v/release/zolferfigueiredo/claudiostat" alt="Latest release"></a>
  <a href="https://www.swift.org"><img src="https://img.shields.io/badge/Swift-6.2-orange" alt="Swift 6.2"></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2015%2B-blue" alt="macOS 15 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow" alt="MIT license"></a>
  <a href="https://github.com/zolferfigueiredo/claudiostat/actions/workflows/ci.yml"><img src="https://github.com/zolferfigueiredo/claudiostat/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
</p>

<p align="center">
  <a href="https://github.com/zolferfigueiredo/claudiostat/releases/latest"><b>Download for macOS</b></a>
  &nbsp;·&nbsp;
  <a href="https://claudiostat.zolfer.com">Try the menu in your browser</a>
</p>

## Install

1. [Download the DMG](https://github.com/zolferfigueiredo/claudiostat/releases/latest), open it and drag ClaudioStat to Applications.
2. Open ClaudioStat. It's signed and notarized by Apple, so macOS only asks you to confirm the first time.
3. With the Claude app open, your numbers show up in the menu bar a few seconds later.

You need:

- macOS 15 or later, on Apple silicon or Intel
- [Claude Code](https://code.claude.com) installed and signed in with a Claude plan
- The Claude desktop app open, or Only refresh while Claude is open turned off
- ClaudioStat in Applications, for launch at login and updates

## What the letters mean

| | Limit | What it counts |
|:-:|---|---|
| **S** | Session | Your current 5-hour window |
| **W** | Week | All models, this week |
| **F** | Fable | Fable only, this week |
| **P** | Pace | How fast W rose over the last hour, per day. Off by default, experimental |
| **B** | Budget | What's left of the week per day, or per working hour, until the reset. Off by default |

S and W turn orange when you're using them faster than they last until the reset, and red when it's well past that. A warning triangle takes the icon's place when Claude flags a limit.

## Features

- **Every reset, counted down.** Open the menu to see when each limit resets and how much of the week you can use per day.
- **Zero tokens.** It sends Claude Code one `get_usage` request and no prompt, so a refresh takes nothing from your limits.
- **Never sees your login.** Claude Code signs in on its own. ClaudioStat never sees or stores a credential.
- **Shows when tokens are going.** The icon pulses while Claude Code is writing a reply on this Mac.
- **Tells you in time.** Notifications when a limit is reached, when it resets, and when the week hits 80% and 90%.
- **Sleeps when Claude does.** While the Claude app is closed it stops asking, and the last numbers dim so you can tell they're old.
- **Native and tiny.** A small Swift app with no Dock icon. It can launch at login and installs updates in one click.

## How it works

Every refresh, ClaudioStat runs your installed Claude Code once, headless, and sends it one `get_usage` control request: the same numbers as `/usage`. No prompt goes with it, so it costs zero tokens.

- Claude Code uses its own login. ClaudioStat never sees or stores a credential.
- Hooks, plugins and MCP servers are off for that run, and no session is saved.
- To know when Claude Code is writing a reply, it watches the session files in `~/.claude/projects` and reads the end of the one that changed. It keeps and sends nothing.
- **Check for updates…** downloads `latest.json` from claudiostat.zolfer.com and sends nothing about you. An update installs only if it's signed by the same developer, and only into the copy in Applications. While it installs, a window shows each step under a loading bar; **Reopen** then starts the new version. When an automatic check finds a new version, a notification says so once; clicking it offers Update Now.

<details>
<summary><b>Every setting</b></summary>

- **Show data below** (on): every limit with its reset countdown, then pace and the budget.
- **Refresh now** (⌘R), and **Refresh every** 1, 3 (default), 5 or 10 minutes.
- **Only refresh while Claude is open** (on): while the Claude desktop app is closed, nothing refreshes and the last numbers dim.
- **Claude Status** opens status.claude.com.
- **Display**: icon and numbers, icon only or numbers only, with the app icon or a plain star. **Loading icon** (on) and **Loading text** (off) pick what pulses while Claude Code writes a reply.
- **Data**: whether the menu bar shows F (on), P and B (off), and whether P and B count per day or per hour.
- **Daily working time**: the hours a day you use Claude, 24 down to 4 (8 by default), so P and B leave out the rest of the day.
- **Notifications**: a limit reached, its reset, and the week at 80% and 90%. All on.
- **Launch at login** (from the Applications folder) and **Keep in Dock**.
- **Check for updates…**, and **Check automatically** daily, weekly (default) or never.

</details>

<details>
<summary><b>How pace, budget and the colors are worked out</b></summary>

**P** is how fast W is rising over the last hour, per day (times the working time, 8 hours by default) or per hour, following Budget per day or Budget per hour under Data. It shows "-" until there's a reading from an hour ago. After a pause, the rise is spread over the whole gap.

**B** is what's left of the week split over the days (or working hours) until the weekly reset, a partial last one counting in full, rounded down: 35% left with 1d 17h to go is 17% a day, or 0.8% an hour with a 24-hour working time. Per hour, the menu says how many working hours it is spread over.

S and W change color when you're using them too fast:

- **S**: its rise over the last 30 minutes against what's left spread evenly until the reset: S 50% with 2 hours left needs 25% per hour.
- **W**: P against B, so it turns orange once P is over B.
- **Orange**: faster than needed. **Red**: 5 points per hour past it for S, 10 points past it for W.

The menu says why under a colored S or W: "Using 24% a day, 17% a day lasts until reset". A warning triangle replaces the icon when Claude itself flags a limit: locked out, or its severity is anything but normal.

</details>

## Build from source

```sh
./build.sh
```

It runs the tests, builds a universal app and writes `dist/ClaudioStat-<version>.dmg`. It needs Xcode 26 (Swift 6.2 or later). Every intermediate goes to a folder in `/tmp` that is deleted when the script ends.

To try a change, run `./run.sh`. It builds a debug copy in `/tmp/claudiostat-run`, quits any running ClaudioStat and opens the new one.

## Disclaimer

Unofficial. Not affiliated with or endorsed by Anthropic. It relies on an experimental Claude Code API that may change or stop working at any time.

## License

[MIT](LICENSE)

---

<p align="center">
  Made with ❤️ for the Claude community by <a href="https://zolfer.com">zolfer.com</a>
</p>
