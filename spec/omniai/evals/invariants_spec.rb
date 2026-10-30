# frozen_string_literal: true

require "omniai/evals/adapters/omniai"

# The six promises in docs/contract.md section 5. They live together because they are the
# contract's guarantees rather than any one class's behaviour, and a reviewer should be
# able to read them in one place.
RSpec.describe "the contract invariants" do # rubocop:disable RSpec/DescribeClass
  describe "1. scores are booleans" do
    it "has no float path into a result record" do
      expect { OmniAI::Evals::Result.new(key: "k", score: 1.0, comment: "") }
        .to raise_error(ArgumentError)
    end
  end

  describe "2. scorecards and run manifests carry no text-bearing field" do
    it "keeps a judge comment out of the scorecard" do
      records = [OmniAI::Evals::Record.build(
        result: OmniAI::Evals::Result.new(key: "one#c1", score: true, comment: "PHI HERE"),
        run_id: "r", example_id: "one", family: "f", scorer: "assertion", epoch: 1
      )]
      scorecard = OmniAI::Evals::Scorecard.build(records:, run_id: "r", comparability_key: "k")
      expect(JSON.generate(scorecard)).not_to include("PHI HERE")
    end

    it "keeps a claimant name out of the run manifest" do
      manifest = OmniAI::Evals::Manifest.build(
        tool: "t", repo_root: Dir.pwd, run_id: "r", argv: ["--claimant", "Jane"],
        dataset: { "name" => "d", "sha256" => "d" }, criteria: { "sha256" => "c" },
        target: { "name" => "T", "prompt_version" => "p" },
        model: { "provider" => "google", "id" => "gemini-3.8-flash" }, epochs: 1
      )
      expect(JSON.generate(manifest)).not_to include("Jane")
    end
  end

  describe "3. the core loads with stdlib and json only" do
    it "loads in a child ruby with rubygems disabled" do
      # Shelling out is the only honest test: anything the suite already required would
      # mask a stray dependency.
      script = 'require "./lib/omniai/evals"; print OmniAI::Evals::VERSION'
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "--disable-gems", "-e", script)
      expect(stderr).to eq("")
      expect(status).to be_success
      expect(stdout.strip).to eq(OmniAI::Evals::VERSION)
    end

    it "does not require the omniai gem" do
      script = 'require "./lib/omniai/evals"; print $LOADED_FEATURES.grep(%r{/omniai/chat}).size'
      stdout, = Open3.capture3(RbConfig.ruby, "-e", script)
      expect(stdout.strip).to eq("0")
    end
  end

  describe "4. a mismatched comparability key is never silently compared" do
    it "raises rather than returning a falsy value" do
      expect { OmniAI::Evals::Compare.check!({ "comparability_key" => "a" }, { "comparability_key" => "b" }) }
        .to raise_error(OmniAI::Evals::ComparabilityError)
    end
  end

  describe "5. --plan performs no network I/O" do
    it "never touches the adapter it is handed" do
      dataset = OmniAI::Evals::Dataset.load(fixture_path("dataset", "manifest.json"))
      adapter = instance_double(OmniAI::Evals::Adapters::OmniAI)
      allow(adapter).to receive(:call).and_raise("network call during --plan")

      OmniAI::Evals::Plan.build(dataset:, criteria: OmniAI::Evals::Criteria.load(dataset:),
        configs: ["a"], epochs: 1, prices: {}, adapter:)

      expect(adapter).not_to have_received(:call)
    end
  end

  describe "6. every format has a loadable sample" do
    %w[dataset_manifest criteria result_record run_manifest scorecard].each do |name|
      it "loads spec/fixtures/contract/#{name}.json at the current contract version" do
        payload = JSON.parse(File.read(fixture_path("contract", "#{name}.json")))
        expect { OmniAI::Evals::Contract.check!(payload, path: name) }.not_to raise_error
      end
    end
  end
end
