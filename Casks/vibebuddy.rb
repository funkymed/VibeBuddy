cask "vibebuddy" do
  version "0.1.0"
  sha256 "b1c017ecc0742796d06391ea89a9a4ac040b3ab8cb55f7257a74d97242173b46"

  url "https://github.com/funkymed/VibeBuddy/releases/download/v#{version}/VibeBuddy-#{version}.dmg"
  name "VibeBuddy"
  desc "Turns the MacBook notch into a dashboard for your coding agents"
  homepage "https://github.com/funkymed/VibeBuddy"

  depends_on macos: ">= :sonoma"

  app "VibeBuddy.app"

  # Signed with a stable self-signed identity, not notarised: Gatekeeper would
  # refuse the first launch. Homebrew removes the quarantine attribute itself,
  # which is the friction this cask exists to remove.

  zap trash: [
    "~/Library/Application Support/VibeBuddy",
    "~/Library/Preferences/fr.funkylab.vibebuddy.plist",
    "~/.vibebuddy",
  ]
end
