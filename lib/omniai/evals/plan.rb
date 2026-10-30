# frozen_string_literal: true

module OmniAI
  module Evals
    # What a run WOULD do: examples x configs x epochs, estimated calls and cost, and
    # zero model calls.
    #
    # `adapter:` is accepted and deliberately never invoked -- the spec passes one that
    # raises, so invariant 5 is enforced by the signature rather than by convention.
    # Prices come from the consumer: the gem knows nothing about any provider's rates.
    #
    # `configs:` is a PLANNING dimension only. A run is one target version, so each
    # config is its own run with its own manifest and its own results file -- this
    # exists so you can price "default vs effort:low" in one go BEFORE committing the
    # spend, not so two configs share a results file. Results.write refuses to mix
    # run_ids in one file, which is what actually prevents the merge.
    module Plan
    module_function

      def build(dataset:, criteria:, configs:, epochs:, prices:, adapter: nil)
        examples = dataset.examples.size
        judge_criteria = criteria.all.count { |criterion| criterion.scorer == "judge" }
        target_calls = examples * configs.size * epochs
        judge_calls = judge_criteria * configs.size * epochs

        {
          "examples" => examples,
          "configs" => configs.size,
          "epochs" => epochs,
          "judge_criteria" => judge_criteria,
          "calls" => target_calls + judge_calls,
          "target_calls" => target_calls,
          "judge_calls" => judge_calls,
          "target_cost_usd" => cost(target_calls, prices["target"]),
          "judge_cost_usd" => cost(judge_calls, prices["judge"]),
          "cost_usd" => cost(target_calls, prices["target"]) + cost(judge_calls, prices["judge"]),
        }
      end

      # The consumer supplies the price table; an absent price is 0.0 rather than an
      # error, because a bench of pure assertions has no metered call to price.
      def cost(calls, price) = (calls * (price || 0.0)).round(4)

      def render(plan)
        format("%<examples>d examples x %<configs>d configs x %<epochs>d epochs\n" \
          "%<target_calls>d target calls, estimated $%<target_cost>.2f\n" \
          "%<judge_calls>d judge calls, estimated $%<judge_cost>.2f\n" \
          "%<calls>d calls total, estimated $%<cost>.2f\n",
          examples: plan.fetch("examples"), configs: plan.fetch("configs"),
          epochs: plan.fetch("epochs"), calls: plan.fetch("calls"),
          target_calls: plan.fetch("target_calls"), target_cost: plan.fetch("target_cost_usd"),
          judge_calls: plan.fetch("judge_calls"), judge_cost: plan.fetch("judge_cost_usd"),
          cost: plan.fetch("cost_usd"))
      end
    end
  end
end
