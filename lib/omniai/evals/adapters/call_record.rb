# frozen_string_literal: true

require "json"

module OmniAI
  module Evals
    module Adapters
      # One per-call record for an adapter's optional `calls:` collector: stop codes and numbers
      # only, never result text or stderr (both can carry PHI).
      #
      # `attempts` counts `claude -p` processes: one more each time a process came back rate limited
      # (see RateLimit). `latency_ms` covers them and their waits. Retries inside `claude -p` or the
      # provider client are not reported, so Adapters::OmniAI always records 1.
      module CallRecord
        DURATION_KEYS = %w[duration_ms duration_api_ms].freeze
        # A call that finished but named no reason.
        UNREPORTED = "unreported"

        # For Adapters::ClaudeCLI. Runs the block once per process, again while +rate_limit+ says to,
        # and pushes exactly one record however that ends, from the last process to finish. The block
        # receives a sink to hand the subprocess stdout to (including on a non-zero exit, so an error
        # envelope's subtype is still recorded) and returns that stdout. Its errors are kept for the
        # caller to raise; only what isn't a StandardError, like an Interrupt, goes straight up.
        #
        # @return [Hash] the last process: :stdout, and :result or :error
        def self.capture(calls, timeout_error:, rate_limit:, &process)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          attempts = 1
          run = nil
          begin
            run = attempt(timeout_error, &process)
            while rate_limit.run_again?(run[:stdout], attempts)
              attempts += 1
              run = attempt(timeout_error, &process)
            end
            run
          ensure
            latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            failure = run ? run[:failure] : "error"
            calls&.<<(envelope_record(run && run[:stdout], failure:, latency_ms:, attempts:))
          end
        end

        # One process: what it printed, and how it failed. The stdout is parsed only for stop codes,
        # numbers and the rate limit.
        def self.attempt(timeout_error)
          stdout = nil
          result = yield(->(out) { stdout = out })
          { stdout: stdout || result, result: }
        rescue timeout_error => e
          { stdout:, failure: "timeout", error: e }
        rescue StandardError => e
          { stdout:, failure: "error", error: e }
        end

        # For Adapters::OmniAI. The block returns an OmniAI::Chat::Response; its verbatim provider
        # finish reason is recorded.
        def self.capture_response(calls, timeout_error:, &block)
          return yield if calls.nil?

          response = nil
          measure(calls, timeout_error:, body: -> { response = block.call }) do |failure, latency_ms|
            reason = failure || string(response.finish_reason&.value) || UNREPORTED
            record(reason, latency_ms)
          end
        end

        # Runs +body+ and pushes exactly one record (built by the block from the failure word, or
        # nil on success, and the latency) however it ends, before any error propagates.
        def self.measure(calls, timeout_error:, body:)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          failure = "error"
          begin
            result = body.call
            failure = nil
            result
          rescue timeout_error
            failure = "timeout"
            raise
          ensure
            calls << yield(failure, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
          end
        end

        # The envelope's stop_reason, else its subtype (subtype first when is_error), else
        # "unreported". A failed call keeps +failure+ unless its stdout is an is_error envelope, so
        # a timeout, or a non-zero exit without one, records "timeout" / "error"; stdout that is
        # not a JSON object records "error".
        def self.envelope_record(stdout, failure:, latency_ms:, attempts: 1)
          envelope = envelope(stdout)
          return record(failure || "error", latency_ms, attempts) if envelope.nil?
          return record(failure, latency_ms, attempts) if failure && !envelope["is_error"]

          result = record(finish_reason(envelope), latency_ms, attempts)
          DURATION_KEYS.each { |key| result[key] = envelope[key] if envelope[key].is_a?(Numeric) }
          result
        end

        def self.record(finish_reason, latency_ms, attempts = 1)
          { "finish_reason" => finish_reason, "latency_ms" => latency_ms, "attempts" => attempts }
        end

        # Strings only, so an odd envelope can't put a nested object into the record.
        def self.finish_reason(envelope)
          reasons = envelope.values_at("stop_reason", "subtype")
          reasons.reverse! if envelope["is_error"]
          reasons.map { |reason| string(reason) }.compact.first || UNREPORTED
        end

        def self.string(value)
          value if value.is_a?(String)
        end

        def self.envelope(stdout)
          return if stdout.nil?

          parsed = JSON.parse(stdout)
          parsed if parsed.is_a?(Hash)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
