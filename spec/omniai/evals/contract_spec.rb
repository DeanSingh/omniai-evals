# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Contract do
  describe "CONTRACT_VERSION" do
    it "is 1" do
      expect(OmniAI::Evals::CONTRACT_VERSION).to eq(1)
    end
  end

  describe ".check!" do
    it "returns the payload when the contract version matches" do
      payload = { "contract" => 1, "name" => "demo" }
      expect(described_class.check!(payload, path: "x.json")).to eq(payload)
    end

    it "raises when the contract version is absent" do
      expect { described_class.check!({ "name" => "demo" }, path: "x.json") }
        .to raise_error(OmniAI::Evals::ContractError, /x\.json.*missing "contract"/)
    end

    it "raises when the contract version does not match" do
      expect { described_class.check!({ "contract" => 2 }, path: "x.json") }
        .to raise_error(OmniAI::Evals::ContractError, /x\.json.*contract 2.*expected 1/)
    end
  end
end
