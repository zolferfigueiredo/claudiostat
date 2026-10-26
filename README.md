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

<p align="center">
  <img src="docs/screenshots/claudiostat-menu.png" width="572" alt="The ClaudioStat menu: each limit with its reset, pace and budget, the settings, and the Language list open">
</p>
<p align="center"><a href="#screenshots"><b>More screenshots</b></a></p>

## Install

1. [Download the DMG](https://github.com/zolferfigueiredo/claudiostat/releases/latest), open it and drag ClaudioStat to Applications.
2. Open ClaudioStat. It's signed and notarized by Apple, so macOS only asks you to confirm the first time.
3. A setup window finds Claude Code and, if it isn't signed in yet, signs you in through your browser. **Reopen** then shows your numbers in the menu bar.

Or install it with [Homebrew](https://brew.sh/):

```bash
brew tap zolferfigueiredo/claudiostat https://github.com/zolferfigueiredo/claudiostat
brew install --cask claudiostat
```

You need:

- macOS 15 or later, on Apple silicon or Intel
- [Claude Code](https://code.claude.com), or the copy the Claude desktop app keeps for itself
- A Claude plan
- ClaudioStat in Applications, for launch at login and updates

## What the letters mean

| | Limit | What it counts |
|:-:|---|---|
| **S** | Session | Your current 5-hour window |
| **W** | Week | All models, this week |
| **F** | Fable | Fable only, this week |
| **P** | Pace | How fast W rose over the last hour, per day. Off by default |
| **B** | Budget | What's left of the week per day, or per working hour, until the reset. Off by default |

Turn on **Resets in …** in Settings, Menu Bar, to add the time to each reset on the line: `S 54% 1h13  W 6% 1d2h  F 3% 1d2h`. The letters and times are dimmed, so the values stand out.

S and W turn orange when you're using them faster than they last until the reset, and red when it's well past that. A warning triangle takes the icon's place when Claude flags a limit.

## Features

- **Every reset, counted down.** Open the menu to see when each limit resets and how much of the week you can use per day.
- **Zero tokens.** It sends Claude Code one `get_usage` request and no prompt, so a refresh takes nothing from your limits.
- **Never sees your login.** Signing in runs Claude Code's own `claude auth login` in your browser. ClaudioStat never sees or stores a credential.
- **Shows when tokens are going.** The icon pulses while Claude Code is writing a reply on this Mac.
- **Tells you in time.** Notifications when a limit is reached, when it resets, and when the week hits 80% and 90%.
- **Sleeps when Claude does.** While neither the Claude app nor Claude Code in a terminal is running, it stops asking, and the last numbers dim so you can tell they're old.
- **Speaks 12 languages.** Deutsch, English, Español, Français, Italiano, Polski, Português, Русский, Українська, 中文, 日本語 and 한국어. It starts in your Mac's language, and **Language** in Settings changes it.
- **Native and tiny.** A small Swift app with no Dock icon. It can launch at login and installs updates in one click.

## Screenshots

<p align="center">
  <img src="docs/screenshots/claudiostat-menubar-app.png" width="317" alt="The menu bar line with the app icon: S, W, P and B">
  &nbsp;&nbsp;&nbsp;
  <img src="docs/screenshots/claudiostat-menubar-star.png" width="369" alt="The menu bar line with the plain star: S, W, F and B">
</p>
<p align="center"><sub>The menu bar line, with the app icon (S, W, P and B) or the plain star (S, W, F and B)</sub></p>

## How it works

Every refresh, ClaudioStat runs your installed Claude Code once, headless, and sends it one `get_usage` control request: the same numbers as `/usage`. No prompt goes with it, so it costs zero tokens.

- It looks for `claude` in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`, then for the copy the Claude desktop app keeps in `~/Library/Application Support/Claude/claude-code`.
- Claude Code uses its own login. **Sign In** runs `claude auth login`, which finishes in your browser, and removing a profile runs `claude auth logout`. ClaudioStat never sees or stores a credential. It keeps only each profile's email, from `claude auth status`, to name it.
- Hooks, plugins and MCP servers are off for that run, and no session is saved.
- To know when Claude Code is writing a reply, it watches the session files in `~/.claude/projects` and reads the end of the one that changed. It keeps and sends nothing.
- **Check for updates…** asks GitHub for the newest release and sends nothing about you, and an update downloads from that release. An update installs only if it's signed by the same developer, and only into the copy in Applications. While it installs, a window shows each step under a loading bar; **Reopen** then starts the new version. When an automatic check finds a new version, a notification says so once; clicking it offers Update Now.
- Only one copy runs at a time: opening another one, say from the DMG, quits the copy already running.

<details>
<summary><b>Every setting</b></summary>

- **Settings…** (⌘,) opens a window with three tabs:
  - **General**, in three parts:
    - **App**: **Language** picks one of the 12. **Pause when Claude is closed** (off): while neither the Claude desktop app nor Claude Code in a terminal is running, nothing refreshes and the last numbers dim. It looks for a running `claude` every minute and when you open the menu. Hidden when neither is installed. **Refresh rate** 1, 3 (default), 5 or 10 minutes.
    - **Profiles**: one per Claude account, each in its own Claude Code folder and named by its email. Each row has a switch on the left: the ones switched on fill the bar, one after another, and the last one on stays on. On the right, a pencil renames it and a trash can removes it. With none, the menu bar says **Add a profile** and the menu offers **Add profile…**.
      - **Add profile…** signs in to another account through your browser and switches it on, into a new folder: `~/.claude-2`, `~/.claude-3` and so on. With no profile left, it signs `~/.claude` in instead.
      - The pencil gives it a name of your own, shown instead of its email: the row says "Personal (you@example.com)". Left empty, the email comes back.
      - The trash can removes it after asking, `~/.claude` included, and signs it out of Claude Code with `claude auth logout`. For `~/.claude` that is the login Claude Code uses in Terminal too. The folder stays.
      - When the first profile switched on is signed out, the menu says **Sign in to Claude Code…**, which signs it in again.
      - When Claude turns the profile's usage checks away for a while, the last numbers stay, faded, and ClaudioStat waits 25 minutes before it asks again. The menu says **Claude paused usage checks. Sign in again…**, which signs the same profile in again for a new login that works right away.
    - **Notifications**: a limit reached, its reset, and the week at 80% and 90%. All on.
  - **Menu Bar**: **Display**: icon and text, icon only or text only, with the app icon or a plain star. A letter without a value yet is left out, and with none the bar shows just the icon. **Compact text** (on) puts the text on two lines. **Background** (off) puts a soft rounded background behind the icon and text.
    Under **Loading**: **Icon** (on) and **Text** (off) pick what pulses while Claude Code writes a reply.
    Under **Data**: whether the menu bar starts with the profile's name (off), **Resets in …** (off), whether it shows P and B (off), whether P and B count per day or per hour (**Pace and budget**), and **Daily working time**: the hours a day you use Claude, 24 down to 4 (8 by default), so P and B leave out the rest of the day.
  - **About**: the version, **Check for updates…** and the website.
- **Show usage details** (on): every limit with its reset countdown, then pace and the budget. With several profiles shown, each in its own block or submenu.
- **Refresh** (⌘R).
- **Launch at login** (from the Applications folder) and **Keep in Dock**.
- **Check for updates…**, and **Check automatically** daily, weekly (default) or never.

</details>

<details>
<summary><b>How pace, budget and the colors are worked out</b></summary>

**P** is how fast W is rising over the last hour, per day (times the working time, 8 hours by default) or per hour, following **Pace and budget** under Data. It shows "-" in the menu, and stays out of the menu bar, until there's a reading from 10 minutes ago. Until the readings cover the hour, it's measured over what they cover. After a pause, the rise is spread over the whole gap.

**B** is what's left of the week split over the days (or working hours) until the weekly reset, a partial last one counting in full, rounded down: 35% left with 1d 17h to go is 17% a day, or 0.8% an hour with a 24-hour working time. Per hour, the menu says how many working hours it is spread over.

S and W change color when you're using them too fast:

- **S**: its rise over the last 30 minutes (from 10 minutes of readings, like P) against what's left spread evenly until the reset: S 50% with 2 hours left needs 25% per hour.
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

`./run.sh -testNotifications YES` also shows every notification, to check how they read: the update notice, offering the next version, then Week at 80% and 90% and each limit reached, 8 seconds apart. The installed app does the same with `open -a ClaudioStat --args -testNotifications YES` once quit.

CI builds and tests every pull request on macOS, counting any compiler warning as an error. It also runs shellcheck on the scripts, and fails a pull request that changes the app without raising its version in `Info.plist`.

`./release.sh` makes the notarized DMG for sharing, using the version in `Info.plist`, and publishes it as a GitHub release of the current commit, which must be pushed. `./release.sh --url` also makes the permanent url.zolfer.com download link.

Every push to `main` whose version isn't released yet is released by `.github/workflows/release.yml`. GitHub's Mac runs `./release.sh build`, then a self-hosted runner on the Mac that holds the Developer ID key runs `./release.sh sign`, so the key never leaves its keychain. A pull request that changes the release files runs only the build half. The runner, set up once on that Mac:

1. On GitHub, open Settings > Actions > Runners > New self-hosted runner (macOS, ARM64), and download it into `~/www/actions-runner/claudiostat` as that page shows.
2. From a terminal where `gh` and Homebrew are on the PATH (the runner keeps that PATH), run `./config.sh --url https://github.com/zolferfigueiredo/claudiostat --token <the token on that page> --labels release --name claudiostat-mac --unattended`, then `./svc.sh install`. Then run `plutil -remove SessionCreate ~/Library/LaunchAgents/actions.runner.zolferfigueiredo-claudiostat.claudiostat-mac.plist` and `./svc.sh stop && ./svc.sh start`: with its own session, the runner can't use the login keychain, and `codesign` fails with errSecInternalComponent. The runner then starts at login, and `~/www/actions-runner/run.sh` starts every runner in that folder.
3. Under Settings > Actions > General > Fork pull request workflows, choose "Require approval for all external contributors", so a fork's pull request can't reach the runner.
4. On the first release, let the runner control Finder, and let `codesign` and `notarytool` use the keychain.

While that Mac is off or logged out, the sign job waits; Re-run failed jobs retries it with the same build.

## Disclaimer

Unofficial. Not affiliated with or endorsed by Anthropic. It relies on an experimental Claude Code API that may change or stop working at any time.

## License

[MIT](LICENSE)

---

<p align="center">
  If ClaudioStat is useful to you, please consider giving it a ⭐<br>
  It helps other Claude users find it. Thank you!
</p>

<p align="center">
  Made with ❤️ for the Claude community by <a href="https://zolfer.com">zolfer.com</a>
</p>
