# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Compare do
  def manifest(key) = { "run_id" => "r", "comparability_key" => key }

  describe ".key" do
    it "joins dataset, criteria, and prompt version" do
      expect(described_class.key(dataset_sha: "d", criteria_sha: "c", prompt_version: "sha256:p"))
        .to eq("d|c|sha256:p")
    end
  end

  describe ".check!" do
    it "returns nil when the keys match" do
      expect(described_class.check!(manifest("d|c|p"), manifest("d|c|p"))).to be_nil
    end

    it "raises when the keys differ" do
      expect { described_class.check!(manifest("d|c|p"), manifest("d|c|p2")) }
        .to raise_error(OmniAI::Evals::ComparabilityError, /d\|c\|p.*d\|c\|p2/m)
    end

    it "downgrades to a returned warning under force" do
      warning = described_class.check!(manifest("d|c|p"), manifest("d|c|p2"), force: true)
      expect(warning).to include("FORCED COMPARISON")
    end

    it "raises when a manifest has no comparability key at all" do
      expect { described_class.check!({ "run_id" => "r" }, manifest("d|c|p")) }
        .to raise_error(OmniAI::Evals::ComparabilityError, /missing comparability_key/)
    end
  end
end
