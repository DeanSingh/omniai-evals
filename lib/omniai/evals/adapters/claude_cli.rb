# frozen_string_literal: true

require "json"
require "open3"

require_relative "../../evals"
require_relative "call_record"

module OmniAI
  module Evals
    module Adapters
      # A judge that shells out to `claude -p`, ported from its first consumer's judge.
      #
      # One place for the "hand a packet to a `claude -p` judge and get back a parsed
      # JSON verdict" mechanics that several checks need: completeness (rubric
      # adherence), blind re-extraction, and dispute tie-break. Each caller supplies
      # its OWN system prompt, packet shape, and model; this owns only the transport
      # and the tolerant output parsing.
      #
      # Three disciplines are baked in and must never regress:
      #   - PHI-on-stdin: the packet (summary/source/transcript text) is PHI and goes
      #     on STDIN, never argv -- argv is visible in `ps`/process listings. Only
      #     static, PHI-free flags are passed as arguments.
      #   - PHI-free errors: `claude` stderr and the raw judge output can echo verbatim
      #     source quotes (PHI), so error messages surface only byte counts, never the
      #     content itself.
      #   - Isolation: the judge runs with only the model and the caller's system prompt
      #     (see ISOLATION_FLAGS) -- no tools, MCP servers, saved session, or settings.
      #
      # Changes from that original: it is a class whose billing is bound at
      # construction (the old Judge.bound), so it satisfies the contract's
      # `call(system:, packet:, model:, schema:, timeout:)` adapter interface; and it
      # runs isolated, replacing the Claude Code system prompt rather than appending to it.
      class ClaudeCLI
        class JudgeError < OmniAI::Evals::Error
        end

        # A judge that blew its wall-clock deadline, distinct from an unparseable result so
        # the summary can count timeouts on their own line (it is still a JudgeError, so
        # existing rescues keep treating it as a failed call).
        class TimeoutError < JudgeError
        end

        # The child's environment is built FROM SCRATCH, never inherited. ANTHROPIC_API_KEY is
        # exported machine-wide on the operator's box, and a bare Open3.popen3(*args) hands it
        # to `claude -p`, where it takes auth precedence over the claude.ai login -- so runs
        # believed to be on the subscription silently billed the metered API (confirmed in the
        # Anthropic Console, 2026-08-26). An ALLOWLIST is deliberate: deleting only the variable
        # we found would leave ANTHROPIC_AUTH_TOKEN / ANTHROPIC_BASE_URL / the Bedrock+Vertex
        # switches to bite next, via the same machine-wide-export mechanism.
        #
        # TRAP, so nobody re-derives it the expensive way: `~/.claude.json` ->
        # `customApiKeyResponses` listing a key under "rejected" governs only the INTERACTIVE
        # approval prompt. It does NOT govern `-p` subprocess auth precedence, and is not
        # evidence of auth mode. Neither is the `-p` envelope's `total_cost_usd`, which is
        # populated under both modes. Billing mode is verifiable only at the Console.
        # Drawn by AUTHORITY, not by enumeration. STRIP anything that carries or redirects
        # authority (ANTHROPIC_*, CLAUDE_CODE_USE_*, cloud credentials) or that injects code
        # (NODE_OPTIONS, RUBYOPT -- an injected --require can re-add any stripped var, so code
        # injection IS authority). PASS machine descriptors and LOCATORS.
        #
        # CLAUDE_CONFIG_DIR / XDG_CONFIG_HOME are the decisive entries: they are the only
        # omissions that would fail SILENTLY-WRONG instead of loudly. With them stripped, a
        # child on a machine whose Claude config was relocated falls back to ~/.claude and, if
        # a valid login lives there, authenticates as a DIFFERENT ACCOUNT -- the same
        # silent-wrong-auth class this seam exists to prevent. The TLS/proxy entries only
        # prevent pointless loud breakage on a corporate network.
        #
        # The boundary is self-enforcing: the spec fails if a future edit adds a name
        # matching /KEY|TOKEN|SECRET|AUTH|ANTHROPIC|AWS|GOOGLE|CREDENTIAL/.
        CHILD_ENV_ALLOWLIST = %w[
          PATH HOME SHELL LANG LC_ALL LC_CTYPE TMPDIR USER LOGNAME
          CLAUDE_CONFIG_DIR XDG_CONFIG_HOME
          SSL_CERT_FILE NODE_EXTRA_CA_CERTS HTTP_PROXY HTTPS_PROXY NO_PROXY
        ].freeze
        BILLING_MODES = %i[subscription api].freeze

        # A page legitimately takes minutes (the model re-transcribes it), so the default
        # deadline is generous; a caller's timeout: overrides it. Its job is only to cap a
        # WEDGED judge that would otherwise hang a worker forever.
        JUDGE_TIMEOUT = 900
        TERM_GRACE = 5

        # The judge receives PHI on stdin, so it runs with nothing but the model and the caller's
        # system prompt (--system-prompt replaces Claude Code's): no tools, no MCP servers (which
        # would also join it to peer networks), no saved session under ~/.claude/projects, and no
        # settings or CLAUDE.md.
        ISOLATION_FLAGS = ["--tools", "", "--strict-mcp-config", "--no-session-persistence",
                           "--setting-sources", "",].freeze

        attr_reader :billing

        # Billing is a RUN-level choice, so it is bound once at construction and the bound
        # adapter is handed to the existing injection points -- no `billing:` parameter has
        # to be threaded through every intermediate signature. The mode is validated at BIND
        # time, so a bad value fails before any page is judged rather than on the first paid
        # call, and the instance is frozen so a validated mode is the mode that runs.
        #
        # @param billing [Symbol] :subscription (local claude.ai login, no key reaches the
        #   child) or :api (METERED -- injects ANTHROPIC_API_KEY). Required on purpose:
        #   there is no default, so a caller cannot fall into metered billing by omission.
        def initialize(billing:)
          @billing = billing
          child_env # validates the mode (and, for :api, the key) up front
          freeze
        end

        # Runs one `claude -p` judge under the billing mode bound at construction.
        #
        # @param system [String] the judge's system prompt -- static and PHI-free.
        # @param packet [String] the PHI-bearing user content; sent on STDIN only.
        # @param model [String] the model id (caller-chosen -- sonnet/haiku/etc.). Keyword
        #   with a nil default only so the signature matches Adapters::OmniAI; nil raises.
        # @param schema [Hash, nil] an optional JSON Schema. When given, the CLI's
        #   `--json-schema` flag constrains the model's answer via constrained decoding
        #   and the schema-valid object comes back in the envelope's `structured_output`
        #   field -- the fix for a task prompt (e.g. "transcribe then extract") whose prose
        #   otherwise buries or replaces the JSON. Without it, behavior is unchanged: the
        #   free-form `result` is recovered by the tolerant parse_output/parse_verdict path.
        # @param calls [#<<, nil] an optional collector. Each call that reaches the subprocess
        #   pushes exactly one CallRecord however it ends, before any error is raised.
        # @return [Hash] the parsed verdict.
        # @raise [JudgeError] when the claude call errors or returns unparseable output.
        def call(system:, packet:, model: nil, schema: nil, timeout: JUDGE_TIMEOUT, calls: nil)
          # model stays effectively required -- there is no sensible default for a judge
          # model -- but it is a keyword with a nil default so this signature matches
          # Adapters::OmniAI exactly and a runner can swap the two adapters.
          raise ArgumentError, "model is required" if model.nil?

          # stderr is captured but deliberately dropped from any error -- it can echo
          # input (PHI). Only PHI-free flags ride argv; the packet rides stdin. The
          # schema is a static, PHI-free JSON Schema, so it is safe on argv.
          args = ["claude", "-p", "--system-prompt", system, *ISOLATION_FLAGS, "--model", model,
                  "--output-format", "json",]
          args += ["--json-schema", JSON.generate(schema)] if schema
          stdout = CallRecord.capture(calls, timeout_error: TimeoutError) do |on_stdout|
            run_with_timeout(args, packet, timeout:, env: child_env, on_stdout:)
          end

          schema ? parse_structured(stdout) : parse_output(stdout)
        end

        # The child environment for the bound billing mode -- built from the allowlist, so no
        # credential reaches the child unless this method puts it there. :subscription carries
        # NO auth vars, leaving `claude -p` to use the local claude.ai login; :api injects the
        # key deliberately and fails fast when it is absent, rather than silently falling back.
        def child_env
          raise ArgumentError, "unknown billing mode #{@billing.inspect}" unless BILLING_MODES.include?(@billing)

          env = CHILD_ENV_ALLOWLIST.each_with_object({}) do |name, acc|
            value = ENV.fetch(name, nil)
            acc[name] = value unless value.nil?
          end
          return env unless @billing == :api

          key = ENV.fetch("ANTHROPIC_API_KEY", "").to_s
          raise JudgeError, "billing: :api requires ANTHROPIC_API_KEY to be set" if key.empty?

          env.merge("ANTHROPIC_API_KEY" => key)
        end

      private

        # Runs the judge subprocess under a hard wall-clock deadline so a wedged `claude`
        # can't hang a worker forever (Open3.capture3 has no timeout). stdout and stderr
        # are drained in threads to avoid a pipe-buffer deadlock; stderr is dropped (it can
        # echo PHI). On expiry: SIGTERM, a short grace, then SIGKILL, and a PHI-free
        # JudgeError. The packet rides stdin only, never argv. +env+, when given, REPLACES
        # the child's environment entirely (see the unsetenv_others note below). +on_stdout+,
        # when given, receives stdout before the exit check, so a caller can read a failed
        # call's envelope without it ever reaching an error.
        def run_with_timeout(args, packet, timeout:, env: nil, on_stdout: nil)
          # unsetenv_others is what makes the allowlist real: WITHOUT it Open3 MERGES the hash
          # into the inherited environment, so every var we meant to exclude still reaches the
          # child and the whole seam is a silent no-op.
          spawn = env.nil? ? args : [env, *args, { unsetenv_others: true }]
          Open3.popen3(*spawn) do |stdin, stdout, stderr, wait_thr|
            writer = Thread.new do
              stdin.write(packet)
            rescue Errno::EPIPE
              # the child exited before reading its input -- nothing left to send
            ensure
              stdin.close
            end
            out_reader = Thread.new { stdout.read }
            err_reader = Thread.new { stderr.read } # drained to avoid deadlock; dropped (PHI)

            if wait_thr.join(timeout).nil?
              terminate(wait_thr)
              [writer, out_reader, err_reader].each(&:kill)
              raise TimeoutError, "judge timeout after #{timeout}s"
            end

            writer.join
            err_reader.join
            status = wait_thr.value
            stdout = out_reader.value.tap { |out| on_stdout&.call(out) }
            raise JudgeError, "claude -p exited #{status.exitstatus}" unless status.success?

            stdout
          end
        end

        # SIGTERM, wait a short grace, then SIGKILL -- never leave a wedged judge running.
        def terminate(wait_thr)
          Process.kill("TERM", wait_thr.pid)
          return if wait_thr.join(TERM_GRACE)

          Process.kill("KILL", wait_thr.pid)
          wait_thr.join(1)
        rescue Errno::ESRCH
          # already exited between the timeout check and the signal
        end

        # Parses the `claude -p --output-format json` envelope ({ is_error, result })
        # and returns the verdict Hash carried in `result`. The error message never
        # includes the raw output -- it holds PHI (verbatim source quotes).
        def parse_output(stdout)
          envelope = JSON.parse(stdout)
          raise JudgeError, "claude reported an error result" if envelope["is_error"]

          parse_verdict(envelope.fetch("result", "").to_s)
        rescue JSON::ParserError
          raise JudgeError, "unparseable judge output (#{stdout.bytesize} bytes)"
        end

        # The judge is told to emit bare JSON, but LLM output is nondeterministic -- the
        # same input can come back ```-fenced one run and wrapped in prose the next.
        # Strip fences first; if that still isn't valid JSON, fall back to the outermost
        # { ... } span. Raises (PHI-free) only when no JSON object is recoverable.
        def parse_verdict(result)
          cleaned = result.strip.gsub(/\A```(?:json)?\s*/m, "").gsub(/\s*```\z/m, "").strip
          JSON.parse(cleaned)
        rescue JSON::ParserError
          span = cleaned[/\{.*\}/m]
          raise JudgeError, "unparseable judge output (#{result.bytesize} bytes)" if span.nil?

          # A non-nil span can still be invalid JSON (e.g. prose braces). Rescue here too
          # so it surfaces as a PHI-free JudgeError, never a raw JSON::ParserError leaking
          # the (possibly PHI-bearing) content.
          begin
            JSON.parse(span)
          rescue JSON::ParserError
            raise JudgeError, "unparseable judge output (#{result.bytesize} bytes)"
          end
        end

        # Reads the schema-constrained object from a `claude -p --json-schema` envelope's
        # `structured_output` field (constrained decoding populates it). The free-form
        # `result` still holds the model's prose transcription -- its chain-of-thought --
        # but the deterministic artifact is `structured_output`. An absent field means the
        # model transcribed but never emitted the constrained object (refusal / max_tokens):
        # a COUNTED JudgeError, never a silent nil. Error messages stay PHI-free (byte counts
        # only) -- the envelope can echo verbatim source quotes.
        def parse_structured(stdout)
          envelope = JSON.parse(stdout)
          raise JudgeError, "claude reported an error result" if envelope["is_error"]

          verdict = envelope["structured_output"]
          raise JudgeError, "no structured_output in judge response (#{stdout.bytesize} bytes)" unless
            verdict.is_a?(Hash)

          verdict
        rescue JSON::ParserError
          raise JudgeError, "unparseable judge output (#{stdout.bytesize} bytes)"
        end
      end
    end
  end
end
