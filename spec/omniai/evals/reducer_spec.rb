# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Reducer do
  def results(*scores)
    scores.map.with_index { |score, i| OmniAI::Evals::Result.new(key: "k", score:, comment: "e#{i}") }
  end

  describe ".all_epochs" do
    it "is PASS when every epoch passed" do
      expect(described_class.all_epochs(results(true, true, true))).to eq(:pass)
    end

    it "is FAIL when every epoch failed" do
      expect(described_class.all_epochs(results(false, false))).to eq(:fail)
    end

    it "is FLAKY when the epochs disagree" do
      expect(described_class.all_epochs(results(true, false, true))).to eq(:flaky)
    end

    it "is PASS for a single passing epoch" do
      expect(described_class.all_epochs(results(true))).to eq(:pass)
    end

    it "raises on no epochs, rather than inventing a verdict" do
      expect { described_class.all_epochs([]) }.to raise_error(ArgumentError, /no epochs/)
    end
  end
end
