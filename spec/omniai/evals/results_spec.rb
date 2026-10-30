# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Results do
  subject(:record) do
    OmniAI::Evals::Record.build(result:, run_id: "r1", example_id: "one", family: "date",
      scorer: "assertion", epoch: 1, cost_usd: 0.0, latency_ms: 3)
  end

  let(:result) { OmniAI::Evals::Result.new(key: "one#c1", score: true, comment: "found") }
  let(:path) { File.join(Dir.mktmpdir, "results.jsonl") }

  it "builds a record carrying the three required fields plus ours" do
    expect(record).to include(
      "contract" => 1, "run_id" => "r1", "example_id" => "one", "key" => "one#c1",
      "score" => true, "comment" => "found", "family" => "date", "scorer" => "assertion",
      "epoch" => 1, "cost_usd" => 0.0, "latency_ms" => 3
    )
  end

  it "round-trips through JSONL" do
    described_class.write(path, [record])
    expect(described_class.read(path)).to eq([record])
  end

  it "writes one line per record" do
    described_class.write(path, [record, record])
    expect(File.readlines(path).size).to eq(2)
  end

  it "rejects a line from another contract version" do
    File.write(path, %({"contract":2,"key":"k","score":true,"comment":""}\n))
    expect { described_class.read(path) }
      .to raise_error(OmniAI::Evals::ContractError, /contract 2, expected 1/)
  end

  it "loads the contract's own sample record" do
    payload = JSON.parse(File.read(fixture_path("contract", "result_record.json")))
    expect(OmniAI::Evals::Contract.check!(payload, path: "r.json")).to include("score" => true)
  end
end
