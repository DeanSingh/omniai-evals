# frozen_string_literal: true

module OmniAI
  module Evals
    # The comparability key -- (dataset sha, criteria sha, prompt_version) -- and the check
    # that refuses to compare runs it does not match.
    #
    # Invariant 4: a mismatched key is NEVER silently compared. `force:` exists because
    # sometimes you genuinely want to look anyway, but it returns a warning the caller
    # must put in the report rather than quietly proceeding.
    module Compare
    module_function

      def key(dataset_sha:, criteria_sha:, prompt_version:)
        [dataset_sha, criteria_sha, prompt_version].join("|")
      end

      # @raise [ComparabilityError]
      # @return [nil, String] nil when comparable; a warning when forced
      def check!(left, right, force: false)
        a = left["comparability_key"]
        b = right["comparability_key"]

        raise ComparabilityError, "missing comparability_key (#{a.inspect} vs #{b.inspect})" if a.nil? || b.nil?
        return nil if a == b

        message = "comparability keys differ:\n  #{a}\n  #{b}"
        raise ComparabilityError, message unless force

        "FORCED COMPARISON -- #{message}"
      end
    end
  end
end
