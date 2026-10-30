# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Plan do
  subject(:plan) do
    described_class.build(dataset:, criteria:, configs: %w[default low], epochs: 5,
      prices: { "judge" => 0.01 })
  end

  let(:dataset) { OmniAI::Evals::Dataset.load(fixture_path("dataset", "manifest.json")) }
  let(:criteria) { OmniAI::Evals::Criteria.load(dataset:) }

  it "multiplies examples by configs by epochs for the target calls" do
    expect(plan).to include("examples" => 1, "configs" => 2, "epochs" => 5, "target_calls" => 10)
  end

  it "counts judge criteria separately from assertions, which are free" do
    expect(plan["judge_criteria"]).to eq(0)
    expect(plan["judge_cost_usd"]).to eq(0.0)
  end

  it "prices the target calls, which are the metered spend" do
    # A --plan that reports $0.00 for a paid run defeats the gate it exists to be.
    priced = described_class.build(dataset:, criteria:, configs: %w[default low], epochs: 5,
      prices: { "judge" => 0.05, "target" => 0.04 })
    expect(priced["target_cost_usd"]).to eq(0.4)
    expect(priced["cost_usd"]).to eq(0.4)
  end

  it "treats an absent price as free rather than an error" do
    expect(plan["cost_usd"]).to eq(0.0)
  end

  it "renders target and judge lines separately" do
    expect(described_class.render(plan))
      .to include("10 target calls").and include("0 judge calls").and include("10 calls total")
  end

  it "makes zero model calls" do
    adapter = Class.new { def call(**) = raise("network call during --plan") }.new
    expect do
      described_class.build(dataset:, criteria:, configs: ["default"], epochs: 1,
        prices: { "judge" => 0.01 }, adapter:)
    end.not_to raise_error
  end
end
