# frozen_string_literal: true

module OmniAI
  module Evals
    module Assertions
      # Passes when the forbidden text does NOT appear.
      module Absence
      module_function

        def call(example:, output:, criterion:)
          needle = Normalize.phrase(criterion.target.fetch("text"))
          present = Normalize.phrase(Normalize.text(output)).include?(needle)
          Result.new(key: criterion.id, score: !present,
            comment: present ? "forbidden text present" : "forbidden text absent")
        end
      end
    end
  end
end
