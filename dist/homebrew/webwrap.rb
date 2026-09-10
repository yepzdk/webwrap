class Webwrap < Formula
  desc "Wrap any website into a standalone macOS .app"
  homepage "https://github.com/yepzdk/webwrap"
  # Prebuilt universal (arm64 + x86_64) binary — no Xcode/Swift toolchain needed.
  url "https://github.com/yepzdk/webwrap/releases/download/v0.9.0/webwrap-0.9.0-macos-universal.tar.gz"
  version "0.9.0"
  # From the release: webwrap-0.9.0-macos-universal.tar.gz.sha256
  sha256 "9fe4513d4377d8050b91d6bb2d19d9bcb9a5d052be3ad7c17de897442397451f"
  license "MIT"

  depends_on :macos

  def install
    bin.install "webwrap"
  end

  test do
    assert_match "0.9.0", shell_output("#{bin}/webwrap --version")
  end
end
