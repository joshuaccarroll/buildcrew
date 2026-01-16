# typed: false
# frozen_string_literal: true

# Homebrew formula for BuildCrew
# To use: brew tap joshuacarroll/tap && brew install buildcrew
#
# For maintainers:
# 1. Update version number below
# 2. Download new release tarball
# 3. Run: shasum -a 256 buildcrew-X.X.X.tar.gz
# 4. Update sha256 below
# 5. Push to joshuacarroll/homebrew-tap repository

class Buildcrew < Formula
  desc "Autonomous AI development workflow with expert personas for Claude Code"
  homepage "https://github.com/joshuacarroll/buildcrew"
  url "https://github.com/joshuacarroll/buildcrew/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256_UPDATE_AFTER_RELEASE"
  license "MIT"
  head "https://github.com/joshuacarroll/buildcrew.git", branch: "main"

  depends_on "jq"

  def install
    # Install to libexec (keeps all files together)
    libexec.install Dir["*"]

    # Create wrapper script in bin that points to libexec
    (bin/"buildcrew").write <<~EOS
      #!/bin/bash
      export BUILDCREW_HOME="#{libexec}"
      exec "#{libexec}/bin/buildcrew" "$@"
    EOS
  end

  def caveats
    <<~EOS
      BuildCrew has been installed!

      To get started:
        1. Navigate to your project directory
        2. Run: buildcrew init
        3. Use /build in Claude Code to create a project plan
        4. Run: buildcrew run

      Documentation: https://github.com/joshuacarroll/buildcrew

      Note: Claude Code CLI must be installed separately.
      Visit: https://claude.ai/code
    EOS
  end

  test do
    assert_match "BuildCrew", shell_output("#{bin}/buildcrew version")
  end
end
