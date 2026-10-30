# frozen_string_literal: true

module OmniAI
  module Evals
    # One line of the results file: (example, criterion, epoch).
    #
    # `key`/`score`/`comment` are the LangSmith / Braintrust / openevals record and the
    # only required fields; the rest are ours. THIS FILE IS PHI-BEARING -- a judge comment
    # may quote output -- so the consumer stores it under its own protected path. The
    # scorecard never carries comments.
    module Record
      # docs/contract.md section 2: a scorer is an assertion, a judge, or a label. A typo
      # here would otherwise reach the scorecard as its own silent family.
      SCORERS = %w[assertion judge label].freeze

    module_function

      def build(result:, run_id:, example_id:, family:, scorer:, epoch:, cost_usd: 0.0, latency_ms: 0)
        raise ArgumentError, "unknown scorer #{scorer.inspect}" unless SCORERS.include?(scorer.to_s)

        {
          "contract" => CONTRACT_VERSION,
          "run_id" => run_id,
          "example_id" => example_id,
          "key" => result.key,
          "score" => result.score,
          "comment" => result.comment,
          "family" => family,
          "scorer" => scorer,
          "epoch" => epoch,
          "cost_usd" => cost_usd,
          "latency_ms" => latency_ms,
        }
      end
    end
  end
end
