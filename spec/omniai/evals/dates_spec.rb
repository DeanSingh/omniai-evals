# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Dates do
  describe ".parse" do
    it "parses an ISO date" do
      expect(described_class.parse("2019-03-14")).to eq(Date.new(2019, 3, 14))
    end

    it "parses a US-format date to the same day" do
      expect(described_class.parse("03/14/2019")).to eq(Date.new(2019, 3, 14))
    end

    it "parses a long-form date to the same day" do
      expect(described_class.parse("March 14, 2019")).to eq(Date.new(2019, 3, 14))
    end

    it "returns nil for a non-date" do
      expect(described_class.parse("not a date")).to be_nil
    end

    it "returns nil for nil" do
      expect(described_class.parse(nil)).to be_nil
    end
  end

  describe ".scan" do
    it "finds every date-shaped token, whatever the format" do
      text = "Examined 2019-03-14, reviewed March 21, 2019, filed 04/02/2019."
      expect(described_class.scan(text))
        .to contain_exactly(Date.new(2019, 3, 14), Date.new(2019, 3, 21), Date.new(2019, 4, 2))
    end

    it "is empty for text with no dates" do
      expect(described_class.scan("no dates here")).to eq([])
    end
  end

  describe "formats that Date.parse gets wrong" do
    it "reads a slash date as US month-first, not day-first" do
      # Date.parse("04/02/2019") silently returns February 4th. That is the exact
      # wrong-but-plausible failure this gem exists to catch, so it cannot live here.
      expect(described_class.parse("04/02/2019")).to eq(Date.new(2019, 4, 2))
      expect(Date.parse("04/02/2019")).to eq(Date.new(2019, 2, 4))
    end

    it "parses a two-digit year in a slash date" do
      expect(described_class.parse("03/14/19")).to eq(Date.new(2019, 3, 14))
    end

    it "returns nil for an impossible slash date rather than raising" do
      expect(described_class.parse("13/45/2019")).to be_nil
    end
  end
end
