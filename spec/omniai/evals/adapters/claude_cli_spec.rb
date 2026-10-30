# frozen_string_literal: true

require "omniai/evals/adapters/claude_cli"

RSpec.describe OmniAI::Evals::Adapters::ClaudeCLI do
  subject(:adapter) { described_class.new(billing: :subscription) }

  around do |example|
    original = ENV.fetch("ANTHROPIC_API_KEY", nil)
    ENV["ANTHROPIC_API_KEY"] = "sk-test-not-a-real-key"
    example.run
    ENV["ANTHROPIC_API_KEY"] = original
  end

  describe "the child environment" do
    it "hides the api key from a subscription child" do
      expect(adapter.child_env).not_to have_key("ANTHROPIC_API_KEY")
    end

    it "hides every other auth switch from a subscription child" do
      expect(adapter.child_env.keys.grep(/KEY|TOKEN|SECRET|AUTH|ANTHROPIC|AWS|GOOGLE|CREDENTIAL/))
        .to be_empty
    end

    it "passes the key through under api billing" do
      expect(described_class.new(billing: :api).child_env)
        .to include("ANTHROPIC_API_KEY" => "sk-test-not-a-real-key")
    end

    it "still gives the child PATH and HOME so claude is findable" do
      expect(adapter.child_env.keys).to include("PATH", "HOME")
    end

    it "keeps CLAUDE_CONFIG_DIR and XDG_CONFIG_HOME on the allowlist" do
      # Stripping these fails SILENTLY-WRONG: a child on a machine whose Claude config was
      # relocated falls back to ~/.claude and may authenticate as a DIFFERENT account.
      expect(described_class::CHILD_ENV_ALLOWLIST).to include("CLAUDE_CONFIG_DIR", "XDG_CONFIG_HOME")
    end

    it "has an allowlist that carries no credential-shaped name" do
      # The boundary is self-enforcing: this fails if a future edit adds one.
      expect(described_class::CHILD_ENV_ALLOWLIST
        .grep(/KEY|TOKEN|SECRET|AUTH|ANTHROPIC|AWS|GOOGLE|CREDENTIAL/)).to be_empty
    end
  end

  describe "billing validation" do
    it "fails fast under api billing with no key, rather than falling back silently" do
      ENV["ANTHROPIC_API_KEY"] = ""
      expect { described_class.new(billing: :api) }
        .to raise_error(described_class::JudgeError, /requires ANTHROPIC_API_KEY/)
    end

    it "rejects an unknown billing mode at construction, not at the first paid call" do
      expect { described_class.new(billing: :free) }.to raise_error(ArgumentError, /unknown billing mode/)
    end
  end

  describe "output parsing" do
    it "parses an unfenced json result" do
      expect(adapter.send(:parse_output, JSON.generate({ "result" => %({"passed":true}) })))
        .to eq({ "passed" => true })
    end

    it "unwraps a fenced json result" do
      envelope = JSON.generate({ "result" => %(```json\n{"passed":true}\n```) })
      expect(adapter.send(:parse_output, envelope)).to eq({ "passed" => true })
    end

    it "recovers json wrapped in prose" do
      envelope = JSON.generate({ "result" => %(Here is my verdict:\n{"passed":false}\nThanks.) })
      expect(adapter.send(:parse_output, envelope)).to eq({ "passed" => false })
    end

    it "raises on an error envelope" do
      expect { adapter.send(:parse_output, JSON.generate({ "is_error" => true, "result" => "x" })) }
        .to raise_error(described_class::JudgeError, /reported an error/)
    end

    it "omits the raw content from an unparseable error, because it can carry PHI" do
      envelope = JSON.generate({ "result" => "the claimant Jane said no json here" })
      expect { adapter.send(:parse_output, envelope) }
        .to raise_error(described_class::JudgeError) { |error|
              expect(error.message).to match(/\d+ bytes/)
              expect(error.message).not_to include("Jane")
            }
    end

    it "raises a PHI-free error when a brace span is still invalid json" do
      envelope = JSON.generate({ "result" => "Jane said {this is not json} today" })
      expect { adapter.send(:parse_output, envelope) }
        .to raise_error(described_class::JudgeError) { |error|
              expect(error.message).not_to include("Jane")
            }
    end

    it "returns the structured_output object under a schema" do
      envelope = JSON.generate({ "structured_output" => { "passed" => true }, "result" => "prose" })
      expect(adapter.send(:parse_structured, envelope)).to eq({ "passed" => true })
    end

    it "raises when structured_output is absent, rather than returning nil silently" do
      expect { adapter.send(:parse_structured, JSON.generate({ "result" => "prose only" })) }
        .to raise_error(described_class::JudgeError, /no structured_output/)
    end

    it "raises on an unparseable envelope" do
      expect { adapter.send(:parse_structured, "not json at all") }
        .to raise_error(described_class::JudgeError, /unparseable/)
    end
  end

  describe "the argv" do
    subject(:argv) do
      captured = nil
      allow(Open3).to receive(:popen3) do |_env, *args, _opts|
        captured = args
        raise Interrupt
      end
      begin
        adapter.call(system: "Grade it.", packet: "PHI", model: "haiku", schema: { "type" => "object" })
      rescue Interrupt
        captured
      end
    end

    it "replaces the system prompt and runs with no tools, MCP servers, saved session, or settings" do
      expect(argv).to eq(["claude", "-p", "--system-prompt", "Grade it.", "--tools", "", "--strict-mcp-config",
                          "--no-session-persistence", "--setting-sources", "", "--model", "haiku",
                          "--output-format", "json", "--json-schema", '{"type":"object"}',])
    end

    it "keeps the packet off argv" do
      expect(argv).not_to include("PHI")
    end
  end

  describe "the calls collector" do
    # A fake `claude` on PATH that prints a canned stdout and exits with a given status.
    let(:fake_dir) { Dir.mktmpdir }
    let(:original_path) { ENV.fetch("PATH") }
    let(:calls) { [] }

    before { ENV["PATH"] = "#{fake_dir}:#{original_path}" }

    after do
      ENV["PATH"] = original_path
      FileUtils.remove_entry(fake_dir)
    end

    def fake_claude(stdout: "", exit_status: 0, sleep_for: 0)
      File.write(File.join(fake_dir, "out"), stdout)
      script = File.join(fake_dir, "claude")
      File.write(script, <<~SH)
        #!/bin/sh
        cat > /dev/null
        #{"exec sleep #{sleep_for}" if sleep_for.positive?}
        cat "#{fake_dir}/out"
        exit #{exit_status}
      SH
      File.chmod(0o755, script)
    end

    def judge(timeout: 5, collector: calls)
      adapter.call(system: "Grade it.", packet: "Jane's records", model: "haiku", timeout:, calls: collector)
    end

    it "records the stop_reason and timings of a successful call" do
      fake_claude(stdout: JSON.generate({ "subtype" => "success", "stop_reason" => "end_turn", "is_error" => false,
                                          "duration_ms" => 1200, "duration_api_ms" => 900,
                                          "result" => %({"passed":true}), }))
      expect(judge).to eq({ "passed" => true })
      expect(calls.size).to eq(1)
      expect(calls.first).to include("finish_reason" => "end_turn", "attempts" => 1,
        "duration_ms" => 1200, "duration_api_ms" => 900)
      expect(calls.first["latency_ms"]).to be_an(Integer)
    end

    it "falls back to the subtype when stop_reason is null" do
      fake_claude(stdout: JSON.generate({ "subtype" => "success", "stop_reason" => nil,
                                          "result" => %({"passed":true}), }))
      judge
      expect(calls.first["finish_reason"]).to eq("success")
    end

    it "records only a string finish_reason, never a nested object" do
      fake_claude(stdout: JSON.generate({ "stop_reason" => { "note" => "Jane" }, "subtype" => "success",
                                          "result" => %({"passed":true}), }))
      judge
      expect(calls.first["finish_reason"]).to eq("success")
    end

    it "records an error envelope with its subtype, then raises" do
      fake_claude(stdout: JSON.generate({ "subtype" => "error_max_turns", "is_error" => true, "result" => "Jane" }))
      expect { judge }.to raise_error(described_class::JudgeError, /reported an error/)
      expect(calls).to eq([{ "finish_reason" => "error_max_turns", "latency_ms" => calls.first["latency_ms"],
                             "attempts" => 1, }])
    end

    it "records a timeout, then raises" do
      fake_claude(sleep_for: 30)
      expect { judge(timeout: 1) }.to raise_error(described_class::TimeoutError)
      expect(calls.map { |c| c.slice("finish_reason", "attempts") }).to eq([{ "finish_reason" => "timeout",
                                                                              "attempts" => 1, }])
      expect(calls.first["latency_ms"]).to be >= 1000
    end

    it "records a non-zero exit as an error, then raises" do
      fake_claude(stdout: JSON.generate({ "subtype" => "success", "result" => "{}" }), exit_status: 1)
      expect { judge }.to raise_error(described_class::JudgeError, /exited 1/)
      expect(calls.map { |c| c["finish_reason"] }).to eq(["error"])
    end

    it "records the subtype of an error envelope from a non-zero exit, then raises" do
      fake_claude(stdout: JSON.generate({ "subtype" => "error_max_turns", "is_error" => true, "result" => "Jane" }),
        exit_status: 1)
      expect { judge }.to raise_error(described_class::JudgeError) { |error|
        expect(error.message).to eq("claude -p exited 1")
      }
      expect(calls.map { |c| c["finish_reason"] }).to eq(["error_max_turns"])
    end

    it "records unreported when the envelope names no reason" do
      fake_claude(stdout: JSON.generate({ "result" => %({"passed":true}) }))
      judge
      expect(calls.first["finish_reason"]).to eq("unreported")
    end

    it "records stdout that is not a JSON object as an error, then raises" do
      fake_claude(stdout: "Jane said no json here")
      expect { judge }.to raise_error(described_class::JudgeError, /unparseable/)
      expect(calls.map { |c| c["finish_reason"] }).to eq(["error"])
    end

    it "keeps result text out of the record, because it can carry PHI" do
      fake_claude(stdout: JSON.generate({ "subtype" => "success", "result" => %({"note":"Jane"}) }))
      judge
      expect(calls.first.keys).to contain_exactly("finish_reason", "latency_ms", "attempts")
      expect(calls.to_s).not_to include("Jane")
    end

    it "behaves as before when no collector is given" do
      fake_claude(stdout: JSON.generate({ "subtype" => "success", "result" => %({"passed":true}) }))
      expect(judge(collector: nil)).to eq({ "passed" => true })
    end
  end

  describe "the subprocess" do
    it "returns stdout for a fast command" do
      expect(adapter.send(:run_with_timeout, ["cat"], "hello", timeout: 5)).to eq("hello")
    end

    it "sends the packet on stdin, never argv" do
      expect(adapter.send(:run_with_timeout, ["wc", "-c"], "12345", timeout: 5).strip).to eq("5")
    end

    it "raises on a nonzero exit" do
      expect { adapter.send(:run_with_timeout, ["false"], "", timeout: 5) }
        .to raise_error(described_class::JudgeError, /exited 1/)
    end

    it "kills a hung process and raises a timeout error" do
      expect { adapter.send(:run_with_timeout, %w[sleep 30], "", timeout: 1) }
        .to raise_error(described_class::TimeoutError, /timeout after 1s/)
    end

    it "strips the inherited environment when an env is given" do
      # unsetenv_others is what makes the allowlist real -- without it Open3 MERGES.
      ENV["OMNIAI_EVALS_LEAK_CANARY"] = "leaked"
      out = adapter.send(:run_with_timeout, ["env"], "", timeout: 5, env: { "PATH" => ENV.fetch("PATH") })
      ENV.delete("OMNIAI_EVALS_LEAK_CANARY")
      expect(out).not_to include("OMNIAI_EVALS_LEAK_CANARY")
    end
  end
end
