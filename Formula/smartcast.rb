class Smartcast < Formula
  desc "Control Smart TVs and cast media from your terminal"
  homepage "https://github.com/yuri-rod/smart-tv-remote-swift"
  url "https://github.com/yuri-rod/smart-tv-remote-swift/archive/refs/tags/v1.2.2.tar.gz"
  sha256 "70d3fe1746acc3a841bbace59999d7f3cd8847a52257f2e62139405eb25a4835"
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
