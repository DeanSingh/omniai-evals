# frozen_string_literal: true

module OmniAI
  module Evals
    module Assertions
      # "A header name is transcribed AS-IS" (docs/contract.md).
      #
      # Two target shapes, selected by which key is present:
      #
      #   {"text": "Patient: JANE Q."}       text mode -- the output must contain this
      #                                       string exactly, after whitespace collapse
      #   {"field": "claim_number",           structured mode -- the output is a Hash and
      #    "value": "ABC-123"}                that field equals this value
      #
      # Text mode is CASE-SENSITIVE and normalizes nothing but whitespace runs, unlike
      # every other assertion here. That is the point of the type: a banded EHR table
      # whose header names a DIFFERENT patient must be transcribed as-is, and an OCR pass
      # that silently "fixes" the case or the spelling has produced the wrong-patient
      # failure this criterion exists to detect. Case-folding here would hide it.
      #
      # Neither mode is fuzzy. A claim number that is nearly right is wrong.
      module Identity
      module_function

        def call(example:, output:, criterion:)
          criterion.target.key?("text") ? text(output, criterion) : field(output, criterion)
        end

        def text(output, criterion)
          expected = Normalize.squish(criterion.target.fetch("text"))
          actual = Normalize.squish(Normalize.text(output))
          ok = actual.include?(expected)
          Result.new(key: criterion.id, score: ok,
            comment: ok ? "transcribed as-is" : "not transcribed as-is (exact, case-sensitive)")
        end

        def field(output, criterion)
          name = criterion.target.fetch("field")
          expected = Normalize.squish(criterion.target.fetch("value").to_s)
          actual = output.is_a?(Hash) ? Normalize.squish(output[name].to_s) : nil

          ok = !actual.nil? && actual == expected
          Result.new(key: criterion.id, score: ok, comment: ok ? "#{name} matches" : "#{name} mismatch")
        end
      end
    end
  end
end
