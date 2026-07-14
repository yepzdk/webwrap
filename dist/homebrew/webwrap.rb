class Webwrap < Formula
  desc "Wrap any website into a standalone macOS .app"
  homepage "https://github.com/yepzdk/webwrap"
  # Prebuilt universal (arm64 + x86_64) binary — no Xcode/Swift toolchain needed.
  url "https://github.com/yepzdk/webwrap/releases/download/v0.6.0/webwrap-0.6.0-macos-universal.tar.gz"
  version "0.6.0"
  # From the release: webwrap-0.6.0-macos-universal.tar.gz.sha256
  sha256 "048d5e57616a5ba8ec6e09356a4d9ace604cfcdc55c8d389f618845263c6fbc7"
  license "MIT"

  depends_on :macos

  def install
    bin.install "webwrap"
  end

  test do
    assert_match "0.6.0", shell_output("#{bin}/webwrap --version")
  end
end
