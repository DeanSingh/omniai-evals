# frozen_string_literal: true

module OmniAI
  module Evals
    module Assertions
      # "Row count of a banded table; which option is circled" (docs/contract.md) -- a
      # different skill from transcription, so it gets its own type.
      #
      # Three target shapes, selected by which key is present:
      #
      #   {"table_rows": 12}                  text mode -- the output's markdown table has
      #                                       this many BODY rows (header and the ---
      #                                       separator excluded)
      #   {"circled": "Option B"}             text mode -- the output marks this option as
      #                                       circled/selected
      #   {"path": ["exam", "date"],          structured mode -- the output is a Hash, the
      #    "type": "string"}                  path resolves, the value has that JSON type
      #
      # Text mode exists because the first consumer's target emits markdown, not JSON.
      # A Hash-only assertion silently fails every example of a text bench, which reads
      # identically to a model that got everything wrong.
      module Structure
        TYPES = {
          "string" => [String],
          "number" => [Numeric],
          "boolean" => [TrueClass, FalseClass],
          "array" => [Array],
          "object" => [Hash],
        }.freeze

        # A markdown separator row: | --- | :--: | and friends. Never a body row.
        SEPARATOR = /\A\s*\|[\s:|-]+\|\s*\z/
        ROW = /\A\s*\|/

      module_function

        def call(example:, output:, criterion:)
          target = criterion.target
          return table_rows(output, criterion) if target.key?("table_rows")
          return Circled.call(output:, criterion:) if target.key?("circled")

          path(output, criterion)
        end

        # Body rows only: the header row and the --- separator are table syntax, not data,
        # and counting them would make every key off by two.
        def table_rows(output, criterion)
          rows = Normalize.text(output).lines.grep(ROW).grep_v(SEPARATOR)
          body = [rows.size - 1, 0].max # the first remaining row is the header
          expected = criterion.target.fetch("table_rows")
          ok = body == expected
          Result.new(key: criterion.id, score: ok, comment: "#{body} body rows, expected #{expected}")
        end

        def path(output, criterion)
          return failure(criterion, "output is not a structure (#{output.class})") unless output.is_a?(Hash)

          steps = criterion.target.fetch("path")
          expected = criterion.target.fetch("type")
          value = dig(output, steps)
          return failure(criterion, "path #{steps.join('.')} missing") if value.nil?

          if matches?(value, expected)
            pass(criterion, "#{steps.join('.')} is #{expected}")
          else
            failure(criterion, "#{steps.join('.')} is #{value.class}")
          end
        end

        # Walks the path, giving up (nil) the moment a step lands on a non-Hash.
        def dig(output, steps)
          steps.reduce(output) { |node, step| node.is_a?(Hash) ? node[step] : nil }
        end

        def matches?(value, expected)
          klasses = TYPES.fetch(expected) { raise ArgumentError, %(unknown structure type "#{expected}") }
          klasses.any? { |klass| value.is_a?(klass) }
        end

        def pass(criterion, comment) = Result.new(key: criterion.id, score: true, comment:)
        def failure(criterion, comment) = Result.new(key: criterion.id, score: false, comment:)
      end
    end
  end
end
