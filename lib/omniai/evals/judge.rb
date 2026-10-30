# frozen_string_literal: true

module OmniAI
  module Evals
    # The shape of a judge criterion: one boolean field plus a short reason.
    #
    # `packet` takes key_text and output and NOTHING else. That is the enforcement of
    # "the judge receives the key text and the output, never the example input" -- there
    # is no parameter through which the input could arrive, so no caller can leak it.
    #
    # The schema is a plain JSON Schema Hash, not an omniai type: the core loads on
    # stdlib alone (invariant 3), and both adapters want raw JSON Schema anyway --
    # ClaudeCLI passes it to --json-schema, and Adapters::OmniAI deserializes it.
    module Judge
    module_function

      def schema
        {
          type: "object",
          properties: {
            passed: { type: "boolean", description: "true when the output is faithful to the key" },
            reason: { type: "string", description: "one sentence, under 200 characters" },
          },
          required: %i[passed reason],
        }
      end

      def packet(key_text:, output:)
        <<~PACKET
          KEY (human-authored ground truth):
          #{key_text}

          OUTPUT (model under test):
          #{output}
        PACKET
      end

      # @raise [Error] when the verdict's score is not a boolean. A lax provider can
      #   return 0.8 or "true"; the raw ArgumentError from Result names the class but not
      #   the criterion, which is useless in a run over hundreds of them.
      def result(verdict, criterion:)
        Result.new(key: criterion.id, score: verdict["passed"], comment: verdict["reason"].to_s)
      rescue ArgumentError => e
        raise Error, "judge verdict for #{criterion.id}: #{e.message}"
      end
    end
  end
end
