# frozen_string_literal: true

require "json"

require_relative "evals/version"
require_relative "evals/errors"
require_relative "evals/contract"
require_relative "evals/result"
require_relative "evals/example"
require_relative "evals/dataset"
require_relative "evals/criterion"
require_relative "evals/criteria"
require_relative "evals/normalize"
require_relative "evals/dates"
require_relative "evals/assertions"
require_relative "evals/reducer"
require_relative "evals/record"
require_relative "evals/results"
require_relative "evals/compare"
require_relative "evals/manifest"
require_relative "evals/scorecard"
require_relative "evals/plan"
require_relative "evals/judge"

# Structure and grading for LLM evals.
#
# The core loads with stdlib and `json` only. Judge adapters reach a model and are
# therefore NOT required here -- a consumer requires the one it wants:
#
#   require "omniai/evals"
#   require "omniai/evals/adapters/omniai"
#
module OmniAI
  # Structure and grading for LLM evals: datasets, boolean criteria, assertions,
  # judges, reducers, and PHI-free scorecards.
  module Evals
  end
end
