# Homebrew cask template, generated only for notarized releases. Copy the filled
# file from the release to Casks/ in your homebrew-tap repo.
cask "mergefolders-app" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/@REPO@/releases/download/v#{version}/MergeFolders-#{version}.zip"
  name "Merge Folders"
  desc "Finder menu to merge folders without overwriting same-named files"
  homepage "https://github.com/@REPO@"

  depends_on macos: ">= :ventura"
  conflicts_with formula: "mergefolders"

  app "MergeFolders.app"
  binary "#{appdir}/MergeFolders.app/Contents/Resources/mergefolders"

  zap trash: ["~/Library/Logs/MergeFolders", "~/Library/Logs/MergeFolders.log"]
end
