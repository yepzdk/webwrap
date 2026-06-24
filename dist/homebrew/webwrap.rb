class Webwrap < Formula
  desc "Wrap any website into a standalone macOS .app"
  homepage "https://github.com/yepzdk/webwrap"
  # Prebuilt universal (arm64 + x86_64) binary — no Xcode/Swift toolchain needed.
  url "https://github.com/yepzdk/webwrap/releases/download/v0.3.0/webwrap-0.3.0-macos-universal.tar.gz"
  version "0.3.0"
  # From the release: webwrap-0.3.0-macos-universal.tar.gz.sha256
  sha256 "eecb64eb8e42389a81d7497a4f10a71442296f57c768d5e34260c85784f55904"
  license "MIT"

  depends_on :macos

  def install
    bin.install "webwrap"
  end

  test do
    assert_match "0.3.0", shell_output("#{bin}/webwrap --version")
  end
end
