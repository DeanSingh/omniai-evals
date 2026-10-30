# frozen_string_literal: true

RSpec.describe "inputs with no file behind them" do # rubocop:disable RSpec/DescribeClass
  it "says so rather than building a path that cannot exist" do
    example = OmniAI::Evals::Example.new(id: "m1", input: { "kind" => "messages" },
      target: "c.json", metadata: {})
    dataset = OmniAI::Evals::Dataset.load(fixture_path("dataset", "manifest.json"))
    expect { dataset.input_path_for(example) }
      .to raise_error(OmniAI::Evals::ContractError, /kind "messages" has no path/)
  end
end
