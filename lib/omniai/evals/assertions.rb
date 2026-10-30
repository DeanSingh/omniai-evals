# frozen_string_literal: true

require_relative "assertions/presence"
require_relative "assertions/absence"
require_relative "assertions/circled"
require_relative "assertions/structure"
require_relative "assertions/abstention"
require_relative "assertions/identity"

module OmniAI
  module Evals
    # The deterministic, free scorers -- one per criterion type in docs/contract.md 3.2.
    # "faithful" is deliberately absent: it is a judge, not an assertion, and asking for
    # it here should fail loudly rather than fall back to a string compare.
    module Assertions
      REGISTRY = {
        "presence" => Presence,
        "absence" => Absence,
        "structure" => Structure,
        "abstention" => Abstention,
        "identity" => Identity,
      }.freeze

    module_function

      # @raise [ArgumentError]
      def for(type)
        REGISTRY.fetch(type.to_s) { raise ArgumentError, %(no assertion for "#{type}") }
      end

      def registered = REGISTRY.keys
    end
  end
end
