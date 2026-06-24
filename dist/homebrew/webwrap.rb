class Webwrap < Formula
  desc "Wrap any website into a standalone macOS .app"
  homepage "https://github.com/yepzdk/webwrap"
  # Prebuilt universal (arm64 + x86_64) binary — no Xcode/Swift toolchain needed.
  url "https://github.com/yepzdk/webwrap/releases/download/v0.3.0/webwrap-0.3.0-macos-universal.tar.gz"
  version "0.3.0"
  # From the release: webwrap-0.3.0-macos-universal.tar.gz.sha256
  sha256 "REPLACE_WITH_TARBALL_SHA256"
  license "MIT"

  depends_on :macos

  def install
    bin.install "webwrap"
  end

  test do
    assert_match "0.3.0", shell_output("#{bin}/webwrap --version")
  end
end
