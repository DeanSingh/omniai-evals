# frozen_string_literal: true

RSpec.describe "results file guards" do # rubocop:disable RSpec/DescribeClass
  let(:path) { File.join(Dir.mktmpdir, "results.jsonl") }

  def record(run_id:, scorer: "assertion")
    OmniAI::Evals::Record.build(
      result: OmniAI::Evals::Result.new(key: "one#c1", score: true, comment: "c"),
      run_id:, example_id: "one", family: "date", scorer:, epoch: 1
    )
  end

  it "refuses to append a second run into a file that already holds one" do
    # Appending a second run doubles every epoch and the reducer silently sees 2n, which
    # produces a PASS assembled from two runs nobody asked to combine.
    OmniAI::Evals::Results.write(path, [record(run_id: "run-a")])
    expect { OmniAI::Evals::Results.write(path, [record(run_id: "run-b")]) }
      .to raise_error(OmniAI::Evals::Error, /holds run run-a; refusing to append run run-b/)
  end

  it "still appends further epochs of the same run" do
    OmniAI::Evals::Results.write(path, [record(run_id: "run-a")])
    OmniAI::Evals::Results.write(path, [record(run_id: "run-a")])
    expect(File.readlines(path).size).to eq(2)
  end

  it "refuses a batch that itself spans two runs" do
    expect { OmniAI::Evals::Results.write(path, [record(run_id: "a"), record(run_id: "b")]) }
      .to raise_error(OmniAI::Evals::Error, /span 2 run_ids/)
  end

  it "writes nothing for an empty batch rather than creating the file" do
    OmniAI::Evals::Results.write(path, [])
    expect(File.exist?(path)).to be(false)
  end

  it "rejects a scorer that is not assertion, judge, or label" do
    expect { record(run_id: "a", scorer: "vibes") }
      .to raise_error(ArgumentError, /unknown scorer "vibes"/)
  end
end
