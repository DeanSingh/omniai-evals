# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Assertions do
  let(:example) { OmniAI::Evals::Example.new(id: "one", input: {}, target: "x.json", metadata: {}) }

  def criterion(type:, target:)
    OmniAI::Evals::Criterion.new(id: "one#c1", family: "f", type:, scorer: "assertion",
      target:, provenance: {})
  end

  describe ".for" do
    it "resolves each of the five deterministic types" do
      expect(described_class.registered)
        .to contain_exactly("presence", "absence", "structure", "abstention", "identity")
    end

    it "raises for an unknown type" do
      expect { described_class.for("vibes") }
        .to raise_error(ArgumentError, /no assertion for "vibes"/)
    end

    it "raises for a judge type, which is not an assertion" do
      expect { described_class.for("faithful") }.to raise_error(ArgumentError, /no assertion/)
    end
  end

  describe "presence" do
    it "passes when the text appears, ignoring case and whitespace runs" do
      result = described_class.for("presence").call(
        example:, output: "Signed   by\nthe examiner.",
        criterion: criterion(type: "presence", target: { "text" => "signed by the examiner" })
      )
      expect(result.score).to be(true)
      expect(result.key).to eq("one#c1")
    end

    it "fails when the text is absent" do
      result = described_class.for("presence").call(
        example:, output: "nothing here",
        criterion: criterion(type: "presence", target: { "text" => "signed" })
      )
      expect(result.score).to be(false)
    end

    it "matches a date written in a different format than the key" do
      result = described_class.for("presence").call(
        example:, output: "Examined on March 14, 2019.",
        criterion: criterion(type: "presence", target: { "date" => "2019-03-14" })
      )
      expect(result.score).to be(true)
      expect(result.comment).to include("2019-03-14")
    end

    it "does not match a date by substring when the day differs" do
      result = described_class.for("presence").call(
        example:, output: "Examined on 2019-03-15.",
        criterion: criterion(type: "presence", target: { "date" => "2019-03-14" })
      )
      expect(result.score).to be(false)
    end
  end

  describe "absence" do
    it "passes when the text is absent" do
      result = described_class.for("absence").call(
        example:, output: "clean",
        criterion: criterion(type: "absence", target: { "text" => "DO NOT COPY" })
      )
      expect(result.score).to be(true)
    end

    it "fails when the text is present in a different case" do
      result = described_class.for("absence").call(
        example:, output: "do not copy",
        criterion: criterion(type: "absence", target: { "text" => "DO NOT COPY" })
      )
      expect(result.score).to be(false)
    end
  end

  describe "structure" do
    it "passes when the path resolves to the named type" do
      result = described_class.for("structure").call(
        example:, output: { "exam" => { "date" => "2019-03-14" } },
        criterion: criterion(type: "structure", target: { "path" => %w[exam date], "type" => "string" })
      )
      expect(result.score).to be(true)
    end

    it "fails when the path is missing" do
      result = described_class.for("structure").call(
        example:, output: { "exam" => {} },
        criterion: criterion(type: "structure", target: { "path" => %w[exam date], "type" => "string" })
      )
      expect(result.score).to be(false)
    end

    it "fails when the value is the wrong type" do
      result = described_class.for("structure").call(
        example:, output: { "exam" => { "date" => 20_190_314 } },
        criterion: criterion(type: "structure", target: { "path" => %w[exam date], "type" => "string" })
      )
      expect(result.score).to be(false)
    end

    it "fails when the output is a String rather than a structure" do
      result = described_class.for("structure").call(
        example:, output: "plain text",
        criterion: criterion(type: "structure", target: { "path" => %w[exam date], "type" => "string" })
      )
      expect(result.score).to be(false)
      expect(result.comment).to include("not a structure")
    end
  end

  describe "abstention" do
    it "passes when the output abstains on the region" do
      result = described_class.for("abstention").call(
        example:, output: "line 7: [illegible]",
        criterion: criterion(type: "abstention",
          target: { "region" => "line 7", "forbidden_terms" => %w[approved denied] })
      )
      expect(result.score).to be(true)
    end

    it "fails when the output asserts a forbidden term instead of abstaining" do
      result = described_class.for("abstention").call(
        example:, output: "line 7: approved by the board",
        criterion: criterion(type: "abstention",
          target: { "region" => "line 7", "forbidden_terms" => %w[approved denied] })
      )
      expect(result.score).to be(false)
      expect(result.comment).to include("approved")
    end

    it "passes when no forbidden term is named and no marker is present" do
      result = described_class.for("abstention").call(
        example:, output: "line 7: illegible handwriting was skipped",
        criterion: criterion(type: "abstention",
          target: { "region" => "line 7", "forbidden_terms" => %w[approved denied] })
      )
      expect(result.score).to be(true)
    end
  end

  describe "identity" do
    it "passes on an exact match after whitespace collapse" do
      result = described_class.for("identity").call(
        example:, output: { "claim_number" => "ABC-123 " },
        criterion: criterion(type: "identity", target: { "field" => "claim_number", "value" => "ABC-123" })
      )
      expect(result.score).to be(true)
    end

    it "fails on a near match, because a nearly-right claim number is wrong" do
      result = described_class.for("identity").call(
        example:, output: { "claim_number" => "ABC-1234" },
        criterion: criterion(type: "identity", target: { "field" => "claim_number", "value" => "ABC-123" })
      )
      expect(result.score).to be(false)
    end

    it "fails when the output is not a structure at all" do
      result = described_class.for("identity").call(
        example:, output: "ABC-123",
        criterion: criterion(type: "identity", target: { "field" => "claim_number", "value" => "ABC-123" })
      )
      expect(result.score).to be(false)
    end
  end
end
