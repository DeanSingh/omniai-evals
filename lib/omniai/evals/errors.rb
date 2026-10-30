# frozen_string_literal: true

module OmniAI
  module Evals
    # Base for every error the gem raises.
    class Error < StandardError; end

    # A file is not the contract version this gem speaks, or is missing a required field.
    class ContractError < Error; end

    # Two runs were compared whose comparability keys do not match.
    class ComparabilityError < Error; end

    # An adapter was used without being required. The core loads on stdlib alone, so
    # "default adapter" is a documentation claim, not an implicit require: naming the
    # missing require is the whole point of this error.
    class AdapterNotLoaded < Error; end
  end
end
