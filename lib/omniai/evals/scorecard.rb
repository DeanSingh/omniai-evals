# frozen_string_literal: true

module OmniAI
  module Evals
    # The PHI-free aggregate: counts, all-pass on top, family rates beneath.
    #
    # Counts, not percentages -- small datasets make rates misleading and the reader can
    # divide. Invariant 2 is enforced by construction: this builds a fresh Hash of
    # integers from the records rather than filtering fields out of them, so there is no
    # path by which a comment reaches the scorecard.
    module Scorecard
    module_function

      def build(records:, run_id:, comparability_key:, cost_usd: nil, calls: nil)
        by_key = records.group_by { |record| record.fetch("key") }
        verdicts = by_key.transform_values { |rows| reduce(rows) }

        {
          "contract" => CONTRACT_VERSION,
          "run_id" => run_id,
          "comparability_key" => comparability_key,
          "examples" => examples_for(by_key, verdicts),
          "families" => families_for(by_key, verdicts),
          "cost_usd" => cost_usd,
          "calls" => calls,
        }
      end

      # Comments are dropped here, not carried and filtered later: the Result rebuilt for
      # the reducer takes an empty comment, so PHI has no route into this method's output.
      def reduce(rows)
        Reducer.all_epochs(rows.map { |row| Result.new(key: row.fetch("key"), score: row.fetch("score"), comment: "") })
      end

      # An example is only all_pass when every one of its criteria passed; a single FAIL
      # makes it failed, otherwise a FLAKY makes it flaky.
      def examples_for(by_key, verdicts)
        by_example = Hash.new { |hash, key| hash[key] = [] }
        by_key.each { |key, rows| by_example[rows.first.fetch("example_id")] << verdicts.fetch(key) }

        counts = { "total" => by_example.size, "all_pass" => 0, "flaky" => 0, "failed" => 0 }
        by_example.each_value { |list| counts[bucket(list)] += 1 }
        counts
      end

      def bucket(verdicts)
        return "failed" if verdicts.include?(:fail)
        return "flaky" if verdicts.include?(:flaky)

        "all_pass"
      end

      def families_for(by_key, verdicts)
        by_key.each_with_object({}) do |(key, rows), acc|
          family = rows.first.fetch("family")
          acc[family] ||= { "criteria" => 0, "pass" => 0, "flaky" => 0, "fail" => 0 }
          acc[family]["criteria"] += 1
          acc[family][verdicts.fetch(key).to_s] += 1
        end
      end
    end
  end
end
