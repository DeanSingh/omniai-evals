# frozen_string_literal: true

RSpec.describe "text-mode assertion targets" do # rubocop:disable RSpec/DescribeClass
  let(:example) { OmniAI::Evals::Example.new(id: "one", input: {}, target: "x.json", metadata: {}) }

  def criterion(type:, target:)
    OmniAI::Evals::Criterion.new(id: "one#c1", family: "f", type:, scorer: "assertion",
      target:, provenance: {})
  end

  def grade(type, target, output)
    OmniAI::Evals::Assertions.for(type).call(example:, output:, criterion: criterion(type:, target:))
  end

  describe "identity in text mode" do
    it "passes when the header is transcribed as-is" do
      expect(grade("identity", { "text" => "Patient: JANE Q." }, "| Patient: JANE Q. | DOB |").score)
        .to be(true)
    end

    it "is case-sensitive, because OCR must not silently fix a wrong-patient header" do
      # This is the whole point of the type. Case-folding here hides the failure it exists
      # to detect: a banded table whose header names a DIFFERENT patient.
      expect(grade("identity", { "text" => "Patient: JANE Q." }, "Patient: Jane T.").score)
        .to be(false)
    end

    it "still collapses whitespace runs, which are a rendering artifact and not content" do
      expect(grade("identity", { "text" => "Patient: JANE Q." }, "Patient:   JANE\n Q.").score)
        .to be(true)
    end

    it "keeps working on structured output via the field shape" do
      expect(grade("identity", { "field" => "claim", "value" => "ABC-123" }, { "claim" => "ABC-123" }).score)
        .to be(true)
    end
  end

  describe "structure in text mode" do
    let(:table) do
      <<~MD
        | Date | Finding |
        | --- | --- |
        | 2019-03-14 | normal |
        | 2019-03-21 | normal |
        | 2019-04-02 | abnormal |
      MD
    end

    it "counts markdown body rows, excluding the header and the separator" do
      expect(grade("structure", { "table_rows" => 3 }, table).score).to be(true)
    end

    it "fails on the wrong row count and says both numbers" do
      result = grade("structure", { "table_rows" => 5 }, table)
      expect(result.score).to be(false)
      expect(result.comment).to eq("3 body rows, expected 5")
    end

    it "grades which option was circled" do
      expect(grade("structure", { "circled" => "Option B" }, "Option A\nOption B (circled)\n").score)
        .to be(true)
    end

    it "fails when the option is present but not marked" do
      expect(grade("structure", { "circled" => "Option B" }, "Option A\nOption B\n").score).to be(false)
    end

    it "keeps working on structured output via the path shape" do
      expect(grade("structure", { "path" => %w[exam date], "type" => "string" },
        { "exam" => { "date" => "2019-03-14" } }).score).to be(true)
    end
  end

  describe "abstention markers" do
    let(:target) { { "region" => "line 7", "forbidden_terms" => %w[approved denied] } }

    it "recognises the non-lexical marker the production model actually emits" do
      result = grade("abstention", target, "line 7: ~~~~")
      expect(result.score).to be(true)
      expect(result.comment).to eq("abstained on line 7")
    end

    it "accepts a run of three or more tildes, since the model is not consistent" do
      expect(grade("abstention", target, "line 7: ~~~").comment).to eq("abstained on line 7")
    end

    it "lets a criterion override the marker list for a target with its own convention" do
      overridden = target.merge("markers" => ["<unreadable>"])
      expect(grade("abstention", overridden, "line 7: <unreadable>").comment).to eq("abstained on line 7")
    end

    it "still fails when the model asserts a forbidden term" do
      expect(grade("abstention", target, "line 7: approved").score).to be(false)
    end
  end
end
