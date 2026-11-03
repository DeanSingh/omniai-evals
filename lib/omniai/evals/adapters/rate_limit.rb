# frozen_string_literal: true

require_relative "call_record"

module OmniAI
  module Evals
    module Adapters
      # One run's `claude -p` rate limit, shared by every worker calling the adapter that holds it. A limited process is
      # waited out and run again; one still limited after ATTEMPTS spends the limit, which starts no new call and wakes
      # every call still waiting. State lives here rather than at class level, so a long-lived process isn't stopped for
      # good by one run's limit.
      class RateLimit
        # The api_error_status of a limit that outlasted Claude Code's own retries: rate limited, overloaded.
        STATUSES = [429, 529].freeze
        # Processes per call.
        ATTEMPTS = 5
        # Seconds before the second process, doubling each try, plus up to this much jitter.
        WAIT = 30

        # @param stdout [String, nil] a process's stdout
        # @return [Boolean]
        def self.limited?(stdout)
          envelope = CallRecord.envelope(stdout)
          !envelope.nil? && STATUSES.include?(envelope["api_error_status"])
        end

        # @param attempts [Integer] processes run so far
        # @return [Float] seconds to wait before the next
        def self.delay(attempts)
          (WAIT * (2**(attempts - 1))) + (rand * WAIT)
        end

        def initialize
          @lock = Mutex.new
          @changed = ConditionVariable.new
          @spent = false
        end

        # @return [Boolean]
        def spent?
          @lock.synchronize { @spent }
        end

        # Spends the limit from outside too: a caller whose other calls share the account can stop this adapter's.
        def spend!
          @lock.synchronize do
            @spent = true
            @changed.broadcast
          end
        end

        # @param stdout [String, nil] the last process's stdout
        # @param attempts [Integer] processes run so far
        # @return [Boolean] whether to run another, after waiting when it does
        def run_again?(stdout, attempts)
          return false unless self.class.limited?(stdout)

          spend! if attempts >= ATTEMPTS
          wait(self.class.delay(attempts))
        end

        # @param seconds [Numeric]
        # @return [Boolean] true once the time is up; false, at once, when the limit is spent
        def wait(seconds)
          deadline = clock + seconds
          @lock.synchronize do
            until @spent
              left = deadline - clock
              return true unless left.positive?

              @changed.wait(@lock, left)
            end
            false
          end
        end

      private

        def clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
