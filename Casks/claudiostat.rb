# Always the latest GitHub release: release.sh uploads a copy of each DMG as ClaudioStat.dmg, so this file
# never changes with a version. The app updates itself, and Gatekeeper checks its notarization.
cask "claudiostat" do
  version :latest
  sha256 :no_check

  url "https://github.com/zolferfigueiredo/claudiostat/releases/latest/download/ClaudioStat.dmg",
      verified: "github.com/zolferfigueiredo/claudiostat/"
  name "ClaudioStat"
  desc "Menu bar meter for Claude Code usage limits"
  homepage "https://claudiostat.zolfer.com/"

  auto_updates true
  depends_on macos: :sequoia

  app "ClaudioStat.app"

  uninstall quit: "com.zolfer.claudiostat"

  zap trash: [
    "~/Library/Caches/com.zolfer.claudiostat",
    "~/Library/HTTPStorages/com.zolfer.claudiostat",
    "~/Library/Preferences/com.zolfer.claudiostat.plist",
  ]

  caveats <<~EOS
    ClaudioStat reads your usage through Claude Code, or the copy the Claude desktop app keeps.
    Its setup window signs you in if needed.
  EOS
end
