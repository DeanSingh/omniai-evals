# frozen_string_literal: true

require "open3"

module OmniAI
  module Evals
    # The run manifest written beside the results.
    #
    # The first five fields match the first consumer's existing run manifest, in the
    # same shape, so its port is a rename rather than a rewrite. Invariant 2 applies:
    # nothing here may carry input or output text -- argv is sanitized on the way in.
    module Manifest
      REDACTED = "<redacted>"

    module_function

      def build(tool:, repo_root:, run_id:, dataset:, criteria:, target:, model:, epochs:,
        argv: ARGV, now: Time.now.utc, params: {}, seed: "none", reducer: "all_epochs",
        gems: {}, judge: nil)
        {
          "contract" => CONTRACT_VERSION,
          "run_id" => run_id,
          "tool" => tool,
          "argv_sanitized" => sanitize_argv(argv),
          "toolkit_sha" => toolkit_sha(repo_root),
          "ruby_version" => RUBY_VERSION,
          "ts" => now.strftime("%Y-%m-%dT%H:%M:%SZ"),
          "dataset" => dataset,
          "criteria" => criteria,
          "target" => target,
          "model" => model,
          "params" => params,
          "seed" => seed,
          "epochs" => epochs,
          "reducer" => reducer,
          "gems" => gems,
          "judge" => judge,
          "comparability_key" => Compare.key(dataset_sha: dataset.fetch("sha256"),
            criteria_sha: criteria.fetch("sha256"),
            prompt_version: target.fetch("prompt_version")),
        }.compact
      end

      # Redacts the value following --claimant (both "--claimant X" and "--claimant=X"
      # forms) so the manifest never records a claimant name; all other args pass through.
      def sanitize_argv(argv)
        redact_next = false
        argv.map do |arg|
          if redact_next
            redact_next = false
            REDACTED
          elsif arg == "--claimant"
            redact_next = true
            arg
          elsif arg.start_with?("--claimant=")
            "--claimant=#{REDACTED}"
          else
            arg
          end
        end
      end

      # The toolkit's short git SHA for provenance; "unknown" when repo_root isn't a repo
      # or git is unavailable (never fails the run over provenance).
      def toolkit_sha(repo_root)
        stdout, _stderr, status = Open3.capture3("git", "-C", repo_root, "rev-parse", "--short", "HEAD")
        status.success? ? stdout.strip : "unknown"
      rescue Errno::ENOENT
        "unknown"
      end
    end
  end
end
