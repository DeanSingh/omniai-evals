# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Dataset do
  subject(:dataset) { described_class.load(fixture_path("dataset", "manifest.json")) }

  it "loads the name and examples" do
    expect(dataset.name).to eq("demo")
    expect(dataset.examples.map(&:id)).to eq(["one"])
  end

  it "exposes the example's input, target, and metadata" do
    example = dataset.examples.first
    expect(example.input).to eq({ "kind" => "text", "path" => "pages/one.txt" })
    expect(example.target).to eq("criteria/one.json")
    expect(example.metadata).to eq({ "tier" => "easy" })
  end

  it "resolves input paths relative to the manifest" do
    expect(dataset.input_path_for(dataset.examples.first))
      .to eq(fixture_path("dataset", "pages", "one.txt"))
  end

  describe "#sha256" do
    it "is stable across loads" do
      expect(dataset.sha256).to eq(described_class.load(fixture_path("dataset", "manifest.json")).sha256)
    end

    it "covers the referenced input files, not just the manifest" do
      # A re-render is a different dataset: same manifest bytes, different pixels. The
      # original sha must be taken BEFORE the mutation -- `dataset` is lazy, so touching
      # it afterwards would hash the mutated file and compare it to itself.
      before = dataset.sha256
      path = fixture_path("dataset", "pages", "one.txt")
      original = File.read(path)
      begin
        File.write(path, "#{original}mutated")
        expect(described_class.load(fixture_path("dataset", "manifest.json")).sha256).not_to eq(before)
      ensure
        File.write(path, original)
      end
    end
  end

  it "refuses a manifest from another contract version" do
    expect { described_class.load(fixture_path("dataset", "wrong_contract.json")) }
      .to raise_error(OmniAI::Evals::ContractError, /contract 2, expected 1/)
  end
end
