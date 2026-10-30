# frozen_string_literal: true

RSpec.describe "circled options marked by emphasis" do # rubocop:disable RSpec/DescribeClass
  let(:example) { OmniAI::Evals::Example.new(id: "p32", input: {}, target: "x.json", metadata: {}) }

  # Verbatim transcriptions of one physician-completed exam form, from four real configs.
  # "2) Normal" is the option circled in pen. Every config got it right; not one of them
  # wrote the word "circled" -- they all rendered the pen circle as bold, which is what the
  # production prompt asks for when it says to match formatting as closely as possible.
  def self.outputs
    {
      "a" => "A: Physique: 1) Slim **2) Normal** 3) Muscular 4) Overweight 5) Obese",
      "b" => "| **A: Physique:** | 1) Slim | **(2) Normal)** | 3) Muscular |",
      "c" => "**A: Physique:** 1) Slim **(2) Normal** 3) Muscular",
      "d" => "**A: Physique:** 1) Slim **(2) Normal)** 3) Muscular",
    }
  end

  def grade(output, circled)
    criterion = OmniAI::Evals::Criterion.new(id: "p32#c1", family: "structure", type: "structure",
      scorer: "assertion", target: { "circled" => circled },
      provenance: {})
    OmniAI::Evals::Assertions.for("structure").call(example:, output:, criterion:)
  end

  outputs.each do |name, output|
    it "scores the bolded option as circled (config #{name})" do
      result = grade(output, "2) Normal")
      expect(result.score).to be(true)
      expect(result.comment).to eq("marked by emphasis")
    end

    it "does not pass an uncircled option vacuously (config #{name})" do
      # Every one of these lines contains bold, so a "line contains emphasis" check would
      # score all five options as circled. The option must BE the emphasised span.
      expect(grade(output, "3) Muscular").score).to be(false)
    end
  end

  it "survives the stray paren a model leaves where the pen circle was" do
    expect(grade("**(2) Normal)**", "2) Normal").score).to be(true)
  end

  it "refuses a span that wraps several options, which marks none of them" do
    expect(grade("**1) Slim 2) Normal 3) Muscular**", "2) Normal").score).to be(false)
  end

  it "still accepts the lexical marker" do
    result = grade("1) Slim\n2) Normal (circled)\n3) Muscular", "2) Normal")
    expect(result.score).to be(true)
    expect(result.comment).to eq("marked circled")
  end

  it "accepts underscore emphasis as well as asterisks" do
    expect(grade("1) Slim __2) Normal__ 3) Muscular", "2) Normal").score).to be(true)
  end

  it "distinguishes an absent option from an unmarked one" do
    expect(grade("1) Slim 3) Muscular", "2) Normal").comment).to eq("option not found in output")
    expect(grade("1) Slim 2) Normal 3) Muscular", "2) Normal").comment).to eq("option present but not marked")
  end
end
