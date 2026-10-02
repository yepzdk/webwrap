class Webwrap < Formula
  desc "Wrap any website into a standalone macOS .app"
  homepage "https://github.com/yepzdk/webwrap"
  # Prebuilt universal (arm64 + x86_64) binary — no Xcode/Swift toolchain needed.
  url "https://github.com/yepzdk/webwrap/releases/download/v0.9.1/webwrap-0.9.1-macos-universal.tar.gz"
  version "0.9.1"
  # From the release: webwrap-0.9.1-macos-universal.tar.gz.sha256
  sha256 "1a1097139b60d934b9032329a06bfd9c26ce5a2b7ee732d8e99d6dbf4a09b390"
  license "MIT"

  depends_on :macos

  def install
    bin.install "webwrap"
  end

  test do
    assert_match "0.9.1", shell_output("#{bin}/webwrap --version")
  end
end
