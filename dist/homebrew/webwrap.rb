class Webwrap < Formula
  desc "Wrap any website into a standalone macOS .app"
  homepage "https://github.com/yepzdk/webwrap"
  # Prebuilt universal (arm64 + x86_64) binary — no Xcode/Swift toolchain needed.
  url "https://github.com/yepzdk/webwrap/releases/download/v0.10.0/webwrap-0.10.0-macos-universal.tar.gz"
  version "0.10.0"
  # From the release: webwrap-0.10.0-macos-universal.tar.gz.sha256
  sha256 "c1874a8ff2da82e11774f1e5ba08d2c48c4cd37672979105162c37077b242398"
  license "MIT"

  depends_on :macos

  def install
    bin.install "webwrap"
  end

  test do
    assert_match "0.10.0", shell_output("#{bin}/webwrap --version")
  end
end
