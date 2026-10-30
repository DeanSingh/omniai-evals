# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Criteria do
  subject(:criteria) { described_class.load(dataset:) }

  let(:dataset) { OmniAI::Evals::Dataset.load(fixture_path("dataset", "manifest.json")) }

  it "loads every criterion for an example" do
    expect(criteria.for("one").map(&:id)).to eq(["one#c1", "one#c2"])
  end

  it "carries family, type, scorer, and target" do
    criterion = criteria.for("one").first
    expect(criterion.family).to eq("date")
    expect(criterion.type).to eq("presence")
    expect(criterion.scorer).to eq("assertion")
    expect(criterion.target).to eq({ "date" => "2019-03-14" })
  end

  it "returns an empty list for an unknown example" do
    expect(criteria.for("nope")).to eq([])
  end

  it "is stable across loads" do
    expect(criteria.sha256).to eq(described_class.load(dataset:).sha256)
  end

  it "loads the contract's own sample criteria file" do
    payload = JSON.parse(File.read(fixture_path("contract", "criteria.json")))
    expect(OmniAI::Evals::Contract.check!(payload, path: "criteria.json")["criteria"].size).to eq(3)
  end
end
