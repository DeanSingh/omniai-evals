# frozen_string_literal: true

require "json"

module OmniAI
  module Evals
    module Adapters
      class ClaudeCLI
        # Reads the verdict out of a `claude -p` process's stdout. Error messages stay PHI-free: byte
        # counts only, never the output.
        module Verdict
          # Parses the `claude -p --output-format json` envelope ({ is_error, result })
          # and returns the verdict Hash carried in `result`. The error message never
          # includes the raw output -- it holds PHI (verbatim source quotes).
          def self.parse_output(stdout)
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
          def self.parse_verdict(result)
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
          def self.parse_structured(stdout)
            envelope = JSON.parse(stdout)
            raise JudgeError, "claude reported an error result" if envelope["is_error"]

            verdict = envelope["structured_output"]
            raise JudgeError, "no structured_output in judge response (#{stdout.bytesize} bytes)" unless
              verdict.is_a?(Hash)

            verdict
          rescue JSON::ParserError
            raise JudgeError, "unparseable judge output (#{stdout.bytesize} bytes)"
          end

          private_class_method :parse_verdict
        end
      end
    end
  end
end
