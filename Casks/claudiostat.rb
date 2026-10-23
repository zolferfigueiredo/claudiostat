# Installs the DMG of release v<version>. CI keeps version equal to the app's, so a version bump bumps it too.
# The app updates itself, so brew upgrade leaves it alone, and Gatekeeper checks its notarization.
cask "claudiostat" do
  version "0.8.0"
  sha256 :no_check

  url "https://github.com/zolferfigueiredo/claudiostat/releases/download/v#{version}/ClaudioStat-#{version}.dmg"
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
