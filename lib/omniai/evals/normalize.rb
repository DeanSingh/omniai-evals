# frozen_string_literal: true

module OmniAI
  module Evals
    # Text tidying shared by the assertions. Kept in one place so "does the output
    # contain this" means the same thing in every assertion.
    module Normalize
    module_function

      # Output may be a String or the Hash a structured target returned.
      def text(output) = output.is_a?(String) ? output : JSON.generate(output)

      # Collapse whitespace runs; keep the case.
      def squish(value) = value.to_s.gsub(/\s+/, " ").strip

      # Collapse whitespace runs AND case -- the comparison form for contains-checks.
      def phrase(value) = squish(value).downcase
    end
  end
end
