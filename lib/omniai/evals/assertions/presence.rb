# frozen_string_literal: true

module OmniAI
  module Evals
    module Assertions
      # Passes when the key's date (compared parsed) or text (compared with case and
      # whitespace runs normalized) appears in the output.
      module Presence
      module_function

        def call(example:, output:, criterion:)
          text = Normalize.text(output)
          key = criterion.target

          score, comment = key.key?("date") ? date(text, key) : text_match(text, key)
          Result.new(key: criterion.id, score:, comment:)
        end

        def date(text, key)
          wanted = Dates.parse(key.fetch("date"))
          found = Dates.scan(text)
          hit = found.include?(wanted)
          [hit, hit ? "date #{wanted} found (parsed)" : "date #{wanted} not among #{found.size} parsed dates"]
        end

        def text_match(text, key)
          hit = Normalize.phrase(text).include?(Normalize.phrase(key.fetch("text")))
          [hit, hit ? "text found" : "text not found"]
        end
      end
    end
  end
end
