# frozen_string_literal: true

RSpec.describe "circled: emphasis only counts when it singles one option out" do # rubocop:disable RSpec/DescribeClass
  let(:example) { OmniAI::Evals::Example.new(id: "p32", input: {}, target: "x.json", metadata: {}) }
  let(:options) { ["1) Slim", "2) Normal", "3) Muscular"] }

  def grade(output, target)
    criterion = OmniAI::Evals::Criterion.new(id: "p32#c1", family: "structure", type: "structure",
      scorer: "assertion", target:, provenance: {})
    OmniAI::Evals::Assertions.for("structure").call(example:, output:, criterion:)
  end

  it "fails a page where every option is bold, because that marks none of them" do
    result = grade("**1) Slim** **2) Normal** **3) Muscular**",
      { "circled" => "2) Normal", "among" => options })
    expect(result.score).to be(false)
    expect(result.comment).to include("3 of the options are marked")
  end

  it "passes a page where exactly one option is bold" do
    result = grade("1) Slim **2) Normal** 3) Muscular",
      { "circled" => "2) Normal", "among" => options })
    expect(result.score).to be(true)
  end

  it "still passes when a non-option is bold, such as the field label" do
    # The measured form bolds "**A: Physique:**" as well. A rule of "exactly one emphasised
    # span on the page" would fail every correct transcription; only the caller knows which
    # strings are options, which is why "among" is supplied rather than inferred.
    result = grade("**A: Physique:** 1) Slim **(2) Normal)** 3) Muscular",
      { "circled" => "2) Normal", "among" => options })
    expect(result.score).to be(true)
  end

  it "leaves the check weaker, not wrong, when among is omitted" do
    result = grade("**1) Slim** **2) Normal** **3) Muscular**", { "circled" => "2) Normal" })
    expect(result.score).to be(true)
  end

  it "accepts a caller-supplied marker for a target with its own convention" do
    target = { "circled" => "2) Normal", "markers" => ["<<ringed>>"] }
    expect(grade("2) Normal <<ringed>>", target).score).to be(true)
    expect(grade("2) Normal (circled)", target).score).to be(false)
  end
end
