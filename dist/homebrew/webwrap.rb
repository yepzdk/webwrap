class Webwrap < Formula
  desc "Wrap any website into a standalone macOS .app"
  homepage "https://github.com/yepzdk/webwrap"
  # Prebuilt universal (arm64 + x86_64) binary — no Xcode/Swift toolchain needed.
  url "https://github.com/yepzdk/webwrap/releases/download/v0.1.0/webwrap-0.1.0-macos-universal.tar.gz"
  version "0.1.0"
  # From the release: webwrap-0.1.0-macos-universal.tar.gz.sha256
  sha256 "7168c982ff7d9f0d82686dec572835f4289d24484dd7a1eaa35afc1113914054"
  license "MIT"

  depends_on :macos

  def install
    bin.install "webwrap"
  end

  test do
    assert_match "0.1.0", shell_output("#{bin}/webwrap --version")
  end
end
