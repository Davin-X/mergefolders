# Homebrew formula template. The release workflow fills in @VERSION@, @URL@ and
# @SHA256@ and attaches the result; copy it to Formula/ in your homebrew-tap repo.
class Mergefolders < Formula
  desc "Merge folders without overwriting same-named files"
  homepage "https://github.com/Davin-X/mergefolders"
  url "@URL@"
  version "@VERSION@"
  sha256 "@SHA256@"
  license "MIT"

  depends_on :macos

  def install
    bin.install "mergefolders"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/mergefolders --version")
    (testpath/"a/x").write "a"
    mkdir testpath/"out"
    system bin/"mergefolders", "--to", testpath/"out", testpath/"a"
    assert_path_exists testpath/"out/x"
  end
end
