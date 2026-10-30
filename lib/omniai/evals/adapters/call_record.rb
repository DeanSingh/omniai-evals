# frozen_string_literal: true

require "json"

module OmniAI
  module Evals
    module Adapters
      # One per-call record for an adapter's optional `calls:` collector: stop codes and numbers
      # only, never result text or stderr (both can carry PHI).
      #
      # `attempts` is always 1: neither adapter retries, and retries inside `claude -p` or the
      # provider client are not reported.
      module CallRecord
        DURATION_KEYS = %w[duration_ms duration_api_ms].freeze
        # A call that finished but named no reason.
        UNREPORTED = "unreported"

        # For Adapters::ClaudeCLI. The block receives a sink to hand the subprocess stdout to
        # (including on a non-zero exit, so an error envelope's subtype is still recorded) and
        # returns that stdout. The stdout stays here; it is parsed only for stop codes and numbers.
        def self.capture(calls, timeout_error:, &block)
          return yield(nil) if calls.nil?

          stdout = nil
          sink = ->(out) { stdout = out }
          measure(calls, timeout_error:, body: -> { block.call(sink) }) do |failure, latency_ms|
            envelope_record(stdout, failure:, latency_ms:)
          end
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
        def self.envelope_record(stdout, failure:, latency_ms:)
          envelope = envelope(stdout)
          return record(failure || "error", latency_ms) if envelope.nil?
          return record(failure, latency_ms) if failure && !envelope["is_error"]

          result = record(finish_reason(envelope), latency_ms)
          DURATION_KEYS.each { |key| result[key] = envelope[key] if envelope[key].is_a?(Numeric) }
          result
        end

        def self.record(finish_reason, latency_ms)
          { "finish_reason" => finish_reason, "latency_ms" => latency_ms, "attempts" => 1 }
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
