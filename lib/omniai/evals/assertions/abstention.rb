# frozen_string_literal: true

module OmniAI
  module Evals
    module Assertions
      # Passes when the output declines to assert content for a region it cannot read.
      # Two ways to pass: it carries an abstention marker for the region, or it names
      # none of the forbidden terms. Hallucinated confidence is the failure this catches.
      module Abstention
        # "~~~~" is what the production model actually emits for an illegible region --
        # a non-lexical marker, measured on a production baseline page. A run of 3 or
        # more tildes counts, since the model is not consistent about the length.
        #
        # The lexical markers are the fallbacks. A criterion can replace this whole list
        # via target["markers"] when a different target has its own convention.
        MARKERS = ["[illegible]", "[unreadable]", "[not legible]", "cannot read", "unable to read"].freeze
        NON_LEXICAL = /~{3,}/

      module_function

        def call(example:, output:, criterion:)
          raw = Normalize.text(output)
          text = Normalize.phrase(raw)
          markers = Array(criterion.target["markers"]).then { |list| list.empty? ? MARKERS : list }
          forbidden = Array(criterion.target["forbidden_terms"]).map { |term| Normalize.phrase(term) }

          abstained = NON_LEXICAL.match?(raw) || markers.any? { |m| text.include?(Normalize.phrase(m)) }
          asserted = forbidden.select { |term| text.include?(term) }
          score = abstained || asserted.empty?

          Result.new(key: criterion.id, score:, comment: comment(score, abstained, asserted, criterion))
        end

        def comment(score, abstained, asserted, criterion)
          region = criterion.target["region"]
          return "asserted #{asserted.join(', ')} for #{region}" unless score

          abstained ? "abstained on #{region}" : "asserted no forbidden term for #{region}"
        end
      end
    end
  end
end
