class Webwrap < Formula
  desc "Wrap any website into a standalone macOS .app"
  homepage "https://github.com/yepzdk/webwrap"
  # Prebuilt universal (arm64 + x86_64) binary — no Xcode/Swift toolchain needed.
  url "https://github.com/yepzdk/webwrap/releases/download/v0.8.0/webwrap-0.8.0-macos-universal.tar.gz"
  version "0.8.0"
  # From the release: webwrap-0.8.0-macos-universal.tar.gz.sha256
  sha256 "94705072dac96758ffb493c1bb8c49d0a814978f47f5820d69e1cd4d5817e776"
  license "MIT"

  depends_on :macos

  def install
    bin.install "webwrap"
  end

  test do
    assert_match "0.8.0", shell_output("#{bin}/webwrap --version")
  end
end
