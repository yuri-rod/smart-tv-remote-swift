class Smartcast < Formula
  desc "Control Smart TVs and cast media from your terminal"
  homepage "https://github.com/yuri-rod/smart-tv-remote-swift"
  url "https://github.com/yuri-rod/smart-tv-remote-swift/archive/refs/tags/v1.1.1.tar.gz"
  sha256 "8aa0f94f8aecb28ba11a69da21759e1206a9e9f41edc58cb3e788391c6044955"
  license "MIT"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/smartcast"
  end

  test do
    assert_match "smartcast v", shell_output("#{bin}/smartcast version")
  end
end
