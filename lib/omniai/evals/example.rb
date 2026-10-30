# frozen_string_literal: true

module OmniAI
  module Evals
    # One unit under test. `input` is the section 3.1 input object ("kind" is
    # image/text/messages); `target` is the path to this example's criteria file,
    # relative to the manifest.
    Example = Data.define(:id, :input, :target, :metadata)
  end
end
