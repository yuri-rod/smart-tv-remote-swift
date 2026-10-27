class Smartcast < Formula
  desc "Control Smart TVs and cast media from your terminal"
  homepage "https://github.com/yuri-rod/smart-tv-remote-swift"
  url "https://github.com/yuri-rod/smart-tv-remote-swift/archive/refs/tags/v1.2.1.tar.gz"
  sha256 "e66d265d7e016bfef086eb230f625acab1540782b1a52e79b7a3ac0c03ff998f"
  license "MIT"

  depends_on xcode: ["16.3", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/smartcast"
  end

  test do
    assert_match "smartcast v", shell_output("#{bin}/smartcast version")
  end
end
