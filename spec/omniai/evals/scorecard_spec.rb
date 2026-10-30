# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Scorecard do
  subject(:scorecard) do
    described_class.build(records:, run_id: "r1", comparability_key: "d|c|p", cost_usd: 4.62, calls: 110)
  end

  let(:records) do
    [
      record(key: "one#c1", score: true, epoch: 1), record(key: "one#c1", score: true, epoch: 2),
      record(key: "one#c2", score: true, epoch: 1), record(key: "one#c2", score: false, epoch: 2),
      record(key: "two#c1", score: false, epoch: 1, example_id: "two", family: "abstention"),
      record(key: "two#c1", score: false, epoch: 2, example_id: "two", family: "abstention"),
    ]
  end

  def record(key:, score:, epoch:, family: "date", example_id: "one")
    OmniAI::Evals::Record.build(
      result: OmniAI::Evals::Result.new(key:, score:, comment: "c"),
      run_id: "r1", example_id:, family:, scorer: "assertion", epoch:
    )
  end

  it "counts examples by their worst criterion" do
    expect(scorecard["examples"]).to eq({ "total" => 2, "all_pass" => 0, "flaky" => 1, "failed" => 1 })
  end

  it "counts criteria per family" do
    expect(scorecard["families"]).to eq(
      "date" => { "criteria" => 2, "pass" => 1, "flaky" => 1, "fail" => 0 },
      "abstention" => { "criteria" => 1, "pass" => 0, "flaky" => 0, "fail" => 1 }
    )
  end

  it "carries no field that can hold input or output text" do
    expect(JSON.generate(scorecard)).not_to include("comment")
    expect(scorecard.keys).to contain_exactly(
      "contract", "run_id", "comparability_key", "examples", "families", "cost_usd", "calls"
    )
  end

  it "loads the contract's own sample scorecard" do
    payload = JSON.parse(File.read(fixture_path("contract", "scorecard.json")))
    expect(OmniAI::Evals::Contract.check!(payload, path: "s.json")["examples"]["total"]).to eq(11)
  end
end
