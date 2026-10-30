# frozen_string_literal: true

module OmniAI
  module Evals
    # One graded criterion. `key`/`score`/`comment` are the LangSmith / Braintrust /
    # openevals record and the only required fields in a result line.
    #
    # The boolean check is here, at the single point every scorer funnels through, so
    # invariant 1 ("no float ever reaches a result record") cannot be violated by a
    # future scorer that returns a confidence. Data is frozen and setter-free, so a
    # validated score is the score that gets written.
    Result = Data.define(:key, :score, :comment) do
      def initialize(key:, score:, comment:)
        unless score.is_a?(TrueClass) || score.is_a?(FalseClass)
          raise ArgumentError, "score must be true or false, got #{score.class}"
        end

        super(key: key.to_s, score:, comment: comment.to_s)
      end
    end
  end
end
