# frozen_string_literal: true

# The subject is the shipped bench directory, not a class.
RSpec.describe "the demo bench" do # rubocop:disable RSpec/DescribeClass
  let(:dataset) { OmniAI::Evals::Dataset.load(File.expand_path("../../bench/demo/manifest.json", __dir__)) }
  let(:criteria) { OmniAI::Evals::Criteria.load(dataset:) }

  it "loads three examples" do
    expect(dataset.examples.size).to eq(4)
  end

  it "grades a faithful output as all-pass" do
    records = dataset.examples.flat_map do |example|
      output = File.read(dataset.input_path_for(example))
      criteria.for(example.id).map do |criterion|
        result = OmniAI::Evals::Assertions.for(criterion.type).call(example:, output:, criterion:)
        OmniAI::Evals::Record.build(result:, run_id: "demo", example_id: example.id,
          family: criterion.family, scorer: criterion.scorer, epoch: 1)
      end
    end
    scorecard = OmniAI::Evals::Scorecard.build(records:, run_id: "demo", comparability_key: "k")
    expect(scorecard["examples"]).to include("total" => 4, "all_pass" => 4)
  end

  it "contains no criterion that needs a judge, so the bench runs free and offline" do
    expect(criteria.all.map(&:scorer).uniq).to eq(["assertion"])
  end

  it "exercises every deterministic criterion type it has a family for" do
    # The first version of this bench had an "identity" FAMILY graded by a "presence"
    # TYPE, so identity was never executed and its Hash-only implementation looked fine
    # under 125 green examples. Assert on types, which is what actually runs.
    expect(criteria.all.map(&:type).uniq)
      .to contain_exactly("presence", "absence", "abstention", "identity", "structure")
  end
end
