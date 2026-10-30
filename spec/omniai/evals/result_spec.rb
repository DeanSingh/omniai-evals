# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Result do
  it "carries key, score, and comment" do
    result = described_class.new(key: "a#c1", score: true, comment: "found")
    expect(result.key).to eq("a#c1")
    expect(result.score).to be(true)
    expect(result.comment).to eq("found")
  end

  it "accepts false as a score" do
    expect(described_class.new(key: "a#c1", score: false, comment: "missing").score).to be(false)
  end

  it "rejects a float score" do
    expect { described_class.new(key: "a#c1", score: 0.9, comment: "close") }
      .to raise_error(ArgumentError, /score must be true or false, got Float/)
  end

  it "rejects nil as a score" do
    expect { described_class.new(key: "a#c1", score: nil, comment: "?") }
      .to raise_error(ArgumentError, /score must be true or false, got NilClass/)
  end

  it "serializes to the three contract fields" do
    result = described_class.new(key: "a#c1", score: true, comment: "found")
    expect(result.to_h).to eq({ key: "a#c1", score: true, comment: "found" })
  end
end
