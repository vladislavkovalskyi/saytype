cask "voicemode" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/vladislavkovalskyi/voicemode/releases/download/v#{version}/voicemode-#{version}.dmg"
  name "voicemode"
  desc "Local push-to-talk dictation"
  homepage "https://github.com/vladislavkovalskyi/voicemode"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle updates the app in place; `brew upgrade --greedy` upgrades it too.
  auto_updates true
  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "voicemode.app"

  # Releases are not notarized yet, so Gatekeeper would refuse the first launch.
  # Clearing the quarantine flag opens the app as if it came from a trusted source.
  # Remove this block once releases are notarized.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/voicemode.app"]
  end

  zap trash: [
    "~/Library/Application Support/dev.kovalskyi.voicemode",
    "~/Library/Caches/dev.kovalskyi.voicemode",
    "~/Library/Preferences/dev.kovalskyi.voicemode.plist",
  ]
end
