class Planq < Formula
  desc "Git-native planning DSL, validation, formatting, and read-only Gantt tooling"
  homepage "https://planq.dev"
  url "https://github.com/planq-cli/plan-releases/releases/download/v0.1.6/planq-0.1.6-darwin-arm64.tar.gz"
  sha256 "c8b0f63e4cc94cecc519093bfc56ddcd36c68660aed67031ad0be8a9ce48be01"
  license "PolyForm-Noncommercial-1.0.0"

  depends_on "git" => :test
  depends_on arch: :arm64

  def install
    bin.install "bin/planq", "bin/planq-solver", "bin/planq-solver.sha256"
    pkgshare.install "THIRD_PARTY_NOTICES.md"
    pkgshare.install "share/planq/skills"
  end

  test do
    require "digest"
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
    assert_equal "0.1.6", version.dig("result", "productVersion")
    assert_equal "darwin-arm64", version.dig("result", "buildTarget")

    cd repo do
      solver = bin/"planq-solver"
      checksum = bin/"planq-solver.sha256"
      handshake = JSON.parse(shell_output("#{solver} --version"))
      assert_equal "1", handshake.fetch("requestVersion")
      assert_equal "1", handshake.fetch("responseVersion")
      engine_version = handshake.fetch("solverEngineVersion")
      assert_equal(
        "sha256:#{Digest::SHA256.file(solver).hexdigest}",
        checksum.read.strip,
      )

      missing = JSON.parse(shell_output("#{bin}/planq skill status"))
      assert_equal "missing", missing.dig("result", "status")

      installed = JSON.parse(shell_output("#{bin}/planq skill install"))
      assert_equal "installed", installed.dig("result", "action")

      current = JSON.parse(shell_output("#{bin}/planq skill status"))
      assert_equal "current", current.dig("result", "status")

      system bin/"planq", "init", "smoke.plan", "--id", "smoke", "--name", "Smoke"
      system bin/"planq", "validate", "smoke.plan"

      (repo/"smoke.plan").write <<~PLAN
        {:version 1.0 :id homebrew-solver-smoke :title "Homebrew Solver Smoke"
         :now 2026-10-01 :items [
           {:id build :task Build :effort 1pd :to [@alice]}]}
      PLAN
      (repo/"resources.plan").write <<~PLAN
        {:version 1.0 :people [
          {:id alice :name Alice :role Engineer}]}
      PLAN
      source = (repo/"smoke.plan").read
      solved = JSON.parse(
        shell_output("#{bin}/planq solve smoke.plan --now 2026-10-05"),
      )
      assert_equal true, solved.fetch("ok")
      assert_equal "solved", solved.dig("result", "status")
      assert_equal "2026-10-05", solved.dig("result", "now")
      assert_equal engine_version, solved.dig("result", "solverEngineVersion")
      assert_equal(
        ["2026-10-05"],
        solved.dig("result", "projection", "computedSchedules", 0, "workDates"),
      )

      proxy = "http://127.0.0.1:9"
      %w[ALL_PROXY HTTPS_PROXY HTTP_PROXY all_proxy https_proxy http_proxy].each do |name|
        ENV[name] = proxy
      end
      %w[NO_PROXY no_proxy].each { |name| ENV[name] = "" }
      begin
        offline = JSON.parse(
          shell_output("#{bin}/planq solve smoke.plan --now 2026-10-06"),
        )
        assert_equal "solved", offline.dig("result", "status")
        assert_equal "2026-10-06", offline.dig("result", "now")
      ensure
        %w[
          ALL_PROXY HTTPS_PROXY HTTP_PROXY all_proxy https_proxy http_proxy
          NO_PROXY no_proxy
        ].each { |name| ENV.delete(name) }
      end

      solver_backup = testpath/"planq-solver.backup"
      solver.rename(solver_backup)
      begin
        failure = JSON.parse(
          shell_output("#{bin}/planq solve smoke.plan --now 2026-10-07", 1),
        )
        assert_equal "unknown", failure.dig("result", "status")
        assert_equal(
          "solver/unknown",
          failure.dig("result", "diagnostics", 0, "code"),
        )
      ensure
        solver_backup.rename(solver)
      end

      checksum_backup = testpath/"planq-solver.sha256.backup"
      original_solver = solver.binread
      replacement = engine_version.sub(/[0-9]/) { |digit| digit == "9" ? "8" : "9" }
      patched_solver = original_solver.gsub(engine_version, replacement)
      refute_equal original_solver, patched_solver
      solver.rename(solver_backup)
      checksum.rename(checksum_backup)
      begin
        solver.binwrite(patched_solver)
        solver.chmod(0755)
        checksum.write("sha256:#{Digest::SHA256.hexdigest(patched_solver)}\n")
        patched_handshake = JSON.parse(shell_output("#{solver} --version"))
        assert_equal replacement, patched_handshake.fetch("solverEngineVersion")
        failure = JSON.parse(
          shell_output("#{bin}/planq solve smoke.plan --now 2026-10-08", 1),
        )
        assert_equal "unknown", failure.dig("result", "status")
        assert_equal(
          "solver/unknown",
          failure.dig("result", "diagnostics", 0, "code"),
        )
      ensure
        solver.unlink if solver.exist?
        checksum.unlink if checksum.exist?
        solver_backup.rename(solver)
        checksum_backup.rename(checksum)
      end
      assert_equal source, (repo/"smoke.plan").read
    end

    refute_path_exists home/".agents"
    refute_path_exists home/".trae"
    refute_path_exists home/".vscode"
    refute_path_exists repo/".plan-dev-session.json"
  end
end
