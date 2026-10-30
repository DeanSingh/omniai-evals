# frozen_string_literal: true

module OmniAI
  module Evals
    # One atomic, binary check on one example. `type` selects the assertion (or the judge
    # prompt, for "faithful"); `target` shape is per type and documented in docs/contract.md.
    Criterion = Data.define(:id, :family, :type, :scorer, :target, :provenance)
  end
end
