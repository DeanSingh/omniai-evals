# frozen_string_literal: true

# The gem's own consumer: a synthetic, PHI-free bench that runs offline and free.
#
#   ruby bench/demo/run.rb --plan
#   ruby bench/demo/run.rb
#
# The "target" here is a deliberately imperfect echo -- it drops the year from every
# date -- so the bench has both passes and failures and the scorecard shows something.
# Swap it for a real production path and this file is a real runner.

require_relative "../../lib/omniai/evals"

DIR = __dir__

dataset = OmniAI::Evals::Dataset.load(File.join(DIR, "manifest.json"))
criteria = OmniAI::Evals::Criteria.load(dataset:)

if ARGV.include?("--plan")
  plan = OmniAI::Evals::Plan.build(dataset:, criteria:, configs: ["echo"], epochs: 1,
    prices: { "judge" => 0.0 })
  print OmniAI::Evals::Plan.render(plan)
  exit
end

# The target: the production code path being measured. This one mangles dates.
target = lambda do |example:, params:|
  _ = params
  File.read(File.join(DIR, example.input.fetch("path"))).gsub(%r{-\d{4}\b|, \d{4}\b|/\d{4}\b}, "")
end

run_id = "#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}-demo"
records = dataset.examples.flat_map do |example|
  output = target.call(example:, params: {})
  criteria.for(example.id).map do |criterion|
    result = OmniAI::Evals::Assertions.for(criterion.type).call(example:, output:, criterion:)
    OmniAI::Evals::Record.build(result:, run_id:, example_id: example.id,
      family: criterion.family, scorer: criterion.scorer, epoch: 1)
  end
end

scorecard = OmniAI::Evals::Scorecard.build(
  records:, run_id:,
  comparability_key: OmniAI::Evals::Compare.key(dataset_sha: dataset.sha256,
    criteria_sha: criteria.sha256,
    prompt_version: "echo-v1")
)
puts JSON.pretty_generate(scorecard)
