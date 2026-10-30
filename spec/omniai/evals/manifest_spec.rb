# frozen_string_literal: true

RSpec.describe OmniAI::Evals::Manifest do
  subject(:manifest) do
    described_class.build(
      tool: "run_bench", repo_root: Dir.pwd, argv: ["--plan"],
      now: Time.utc(2026, 9, 2, 18, 4, 11), run_id: "2026-09-02T18:04:11Z-ocr-a1b2c3",
      dataset: { "name" => "demo", "sha256" => "d" }, criteria: { "sha256" => "c" },
      target: { "name" => "ExampleService", "prompt_version" => "sha256:p", "commit" => "1a2b3c4d" },
      model: { "provider" => "google", "id" => "gemini-3.8-flash", "endpoint" => "global" },
      epochs: 5, gems: { "omniai" => "3.8.0" }
    )
  end

  it "carries the five legacy run-manifest fields in the same shape" do
    expect(manifest).to include(
      "tool" => "run_bench", "argv_sanitized" => ["--plan"],
      "ruby_version" => RUBY_VERSION, "ts" => "2026-09-02T18:04:11Z"
    )
    expect(manifest["toolkit_sha"]).to be_a(String)
  end

  it "defaults seed to the string none and reducer to all_epochs" do
    expect(manifest["seed"]).to eq("none")
    expect(manifest["reducer"]).to eq("all_epochs")
  end

  it "computes the comparability key from dataset, criteria, and prompt version" do
    expect(manifest["comparability_key"]).to eq("d|c|sha256:p")
  end

  it "stamps the contract version" do
    expect(manifest["contract"]).to eq(1)
  end

  describe ".sanitize_argv" do
    it "redacts a claimant name given as two arguments" do
      expect(described_class.sanitize_argv(["--claimant", "Jane", "--epochs", "5"]))
        .to eq(["--claimant", "<redacted>", "--epochs", "5"])
    end

    it "redacts a claimant name given with an equals sign" do
      expect(described_class.sanitize_argv(["--claimant=Jane"])).to eq(["--claimant=<redacted>"])
    end

    it "passes every other argument through" do
      expect(described_class.sanitize_argv(["--plan", "--epochs=5"])).to eq(["--plan", "--epochs=5"])
    end
  end

  describe ".toolkit_sha" do
    it "is 'unknown' when the path is not a repository, rather than failing the run" do
      expect(described_class.toolkit_sha(Dir.mktmpdir)).to eq("unknown")
    end
  end

  it "loads the contract's own sample manifest" do
    payload = JSON.parse(File.read(fixture_path("contract", "run_manifest.json")))
    expect(OmniAI::Evals::Contract.check!(payload, path: "m.json")["reducer"]).to eq("all_epochs")
  end
end
