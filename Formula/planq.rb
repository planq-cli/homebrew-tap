class Planq < Formula
  desc "Git-native planning DSL, validation, formatting, and read-only Gantt tooling"
  homepage "https://planq.dev"
  url "https://github.com/planq-cli/plan-releases/releases/download/v0.1.0/planq-0.1.0-darwin-arm64.tar.gz"
  sha256 "7a6b65905dd721a6c80a686e574a38d0af249b11df9a329faee9675d21e6a067"
  license "PolyForm-Noncommercial-1.0.0"

  depends_on "git" => :test
  depends_on arch: :arm64

  def install
    bin.install "bin/planq"
    pkgshare.install "share/planq/skills"
  end

  test do
    require "json"

    home = testpath/"home"
    repo = testpath/"repo"
    home.mkpath
    repo.mkpath
    ENV["HOME"] = home
    ENV["USERPROFILE"] = home
    system "git", "init", "-q", repo

    version = JSON.parse(shell_output("#{bin}/planq version"))
    assert_equal true, version.fetch("ok")
    assert_equal "0.1.0", version.dig("result", "productVersion")
    assert_equal "darwin-arm64", version.dig("result", "buildTarget")

    cd repo do
      missing = JSON.parse(shell_output("#{bin}/planq skill status"))
      assert_equal "missing", missing.dig("result", "status")

      installed = JSON.parse(shell_output("#{bin}/planq skill install"))
      assert_equal "installed", installed.dig("result", "action")

      current = JSON.parse(shell_output("#{bin}/planq skill status"))
      assert_equal "current", current.dig("result", "status")

      system bin/"planq", "init", "smoke.plan", "--id", "smoke", "--name", "Smoke"
      system bin/"planq", "validate", "smoke.plan"
    end

    refute_path_exists home/".agents"
    refute_path_exists home/".trae"
    refute_path_exists home/".vscode"
    refute_path_exists repo/".plan-dev-session.json"
  end
end
