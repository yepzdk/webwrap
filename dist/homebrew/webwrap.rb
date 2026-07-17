class Webwrap < Formula
  desc "Wrap any website into a standalone macOS .app"
  homepage "https://github.com/yepzdk/webwrap"
  # Prebuilt universal (arm64 + x86_64) binary — no Xcode/Swift toolchain needed.
  url "https://github.com/yepzdk/webwrap/releases/download/v0.7.0/webwrap-0.7.0-macos-universal.tar.gz"
  version "0.7.0"
  # From the release: webwrap-0.7.0-macos-universal.tar.gz.sha256
  sha256 "0e9919f2a13b1dad00cbfeacedb53427ee56f3e7f4eaf1517cbf8266c00dd9ef"
  license "MIT"

  depends_on :macos

  def install
    bin.install "webwrap"
  end

  test do
    assert_match "0.7.0", shell_output("#{bin}/webwrap --version")
  end
end
