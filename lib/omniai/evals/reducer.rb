# frozen_string_literal: true

module OmniAI
  module Evals
    # How the epochs of one criterion combine into one verdict.
    #
    # `all_epochs` is the default and the only reducer in v1. FLAKY is a first-class
    # verdict rather than a rounding decision: a criterion that passes 3 of 5 times is
    # not "60% correct", it is unreliable, and the reader needs to see that.
    module Reducer
    module_function

      # @param results [Array<Result>] one per epoch, for a single criterion
      # @return [Symbol] :pass, :fail, or :flaky
      def all_epochs(results)
        raise ArgumentError, "no epochs to reduce" if results.empty?

        scores = results.map(&:score)
        return :pass if scores.all?
        return :fail if scores.none?

        :flaky
      end
    end
  end
end
