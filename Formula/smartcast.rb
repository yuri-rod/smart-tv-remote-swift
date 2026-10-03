class Smartcast < Formula
  desc "Control Smart TVs and cast media from your terminal"
  homepage "https://github.com/yuri-rod/smart-tv-remote-swift"
  url "https://github.com/yuri-rod/smart-tv-remote-swift/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "bb0208fbbe776bc3281affcdf4a99fd80464097f6346d5571bbe89e710c600c4"
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
