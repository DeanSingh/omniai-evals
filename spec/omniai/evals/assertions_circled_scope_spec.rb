# frozen_string_literal: true

RSpec.describe "circled: the mark must belong to this option and this field" do # rubocop:disable RSpec/DescribeClass
  let(:example) { OmniAI::Evals::Example.new(id: "p32", input: {}, target: "x.json", metadata: {}) }
  let(:options) { ["1) Slim", "2) Normal", "3) Muscular"] }

  def grade(output, target)
    criterion = OmniAI::Evals::Criterion.new(id: "p32#c1", family: "structure", type: "structure",
      scorer: "assertion", target:, provenance: {})
    OmniAI::Evals::Assertions.for("structure").call(example:, output:, criterion:)
  end

  it "ignores an option word emphasised in an unrelated field elsewhere on the page" do
    # Option strings repeat across a form: Yes/No, Normal, None, Left/Right. A bolded "No"
    # three sections down must not become a phantom rival that refuses a correct mark.
    page = "B: Smoker: Yes **No**\n\nA: Physique: 1) Slim **2) Normal** 3) Muscular\n"
    result = grade(page, { "circled" => "2) Normal", "among" => options + ["No"] })
    expect(result.score).to be(true)
  end

  it "fails when the lexical marker sits next to a different option" do
    # Anywhere-on-the-line is not discriminating; the marker belongs to "1) Slim" here.
    result = grade("1) Slim (circled) 2) Normal 3) Muscular",
      { "circled" => "2) Normal", "among" => options })
    expect(result.score).to be(false)
  end

  it "passes when the lexical marker sits next to the target option" do
    result = grade("1) Slim 2) Normal (circled) 3) Muscular",
      { "circled" => "2) Normal", "among" => options })
    expect(result.score).to be(true)
    expect(result.comment).to eq("marked circled")
  end

  it "attributes a marker to the option it follows, not the one it precedes" do
    # "(circled)" sits between two options and would otherwise mark both, refusing a correct
    # page as non-discriminating. It belongs to the option before it.
    result = grade("1) Slim 2) Normal (circled) 3) Muscular",
      { "circled" => "3) Muscular", "among" => options })
    expect(result.score).to be(false)
  end

  it "attributes an opening checkbox to the option it precedes, having none before it" do
    result = grade("[x] 2) Normal 3) Muscular",
      { "circled" => "2) Normal", "among" => ["2) Normal", "3) Muscular"] })
    expect(result.score).to be(true)
  end

  it "accepts the option bolded without its enumerator" do
    # Models bold the option text and drop the "2)" that precedes it.
    result = grade("A: Physique: 1) Slim **Normal** 3) Muscular", { "circled" => "2) Normal" })
    expect(result.score).to be(true)
  end

  it "does not invent an emphasised span from a snake_case token" do
    # `_(.+?)_` would match the middle of "field_Normal_name" and mark an option nobody
    # emphasised. Single delimiters require non-word boundaries.
    result = grade("field_Normal_name 1) Slim 2) Normal", { "circled" => "Normal" })
    expect(result.score).to be(false)
  end

  it "still treats an italic option as emphasis" do
    expect(grade("1) Slim *2) Normal* 3) Muscular", { "circled" => "2) Normal" }).score).to be(true)
  end
end
