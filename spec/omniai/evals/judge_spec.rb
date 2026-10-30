# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Judge do
  let(:criterion) do
    OmniAI::Evals::Criterion.new(id: "one#c3", family: "handwriting", type: "faithful",
      scorer: "judge", target: {}, provenance: {})
  end

  describe ".packet" do
    it "carries the key text and the output" do
      packet = described_class.packet(key_text: "the key", output: "the output")
      expect(packet).to include("the key").and include("the output")
    end

    it "has no parameter through which the example input could be passed" do
      # This is the enforcement of "the judge receives the key text and the output,
      # never the example input" -- there is no argument for the input to arrive in.
      expect(described_class.method(:packet).parameters.map(&:last))
        .to contain_exactly(:key_text, :output)
    end
  end

  describe ".schema" do
    it "is one boolean field plus a short reason" do
      properties = described_class.schema.fetch(:properties)
      expect(properties.keys).to contain_exactly(:passed, :reason)
      expect(properties.fetch(:passed).fetch(:type)).to eq("boolean")
    end
  end

  describe ".result" do
    it "keeps the boolean and the reason" do
      result = described_class.result({ "passed" => false, "reason" => "differs" }, criterion:)
      expect(result.score).to be(false)
      expect(result.comment).to eq("differs")
    end

    it "refuses a non-boolean verdict rather than coercing it" do
      expect { described_class.result({ "passed" => 0.8, "reason" => "maybe" }, criterion:) }
        .to raise_error(OmniAI::Evals::Error, /score must be true or false/)
    end

    it "names the criterion in the error, since a run grades hundreds of them" do
      expect { described_class.result({ "passed" => "true", "reason" => "" }, criterion:) }
        .to raise_error(OmniAI::Evals::Error, /one#c3/)
    end
  end
end
