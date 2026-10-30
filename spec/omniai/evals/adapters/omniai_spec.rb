# frozen_string_literal: true

require "omniai/evals/adapters/omniai"

RSpec.describe OmniAI::Evals::Adapters::OmniAI do
  subject(:adapter) { described_class.new(client:, model: "gemini-3.8-flash") }

  let(:response) { instance_double(OmniAI::Chat::Response, text: %({"passed":true,"reason":"matches"})) }
  let(:client) { instance_double(OmniAI::Client, chat: response) }

  it "returns the parsed verdict" do
    expect(adapter.call(system: "judge", packet: "key vs output", schema: OmniAI::Evals::Judge.schema))
      .to eq({ "passed" => true, "reason" => "matches" })
  end

  it "puts the judge prompt in a real system turn and the packet in a user turn" do
    # Not "a block was passed" -- the block is run against a real OmniAI::Chat::Prompt and
    # the roles are read back. ClaudeCLI passes system via --system-prompt, so an
    # adapter that prepends it to the user content is asking a different question, and any
    # calibration measured on one adapter would not transfer to the other.
    captured = nil
    allow(client).to receive(:chat) { |**, &block|
      captured = block
      response
    }

    adapter.call(system: "judge instructions", packet: "key vs output",
      schema: OmniAI::Evals::Judge.schema)

    prompt = OmniAI::Chat::Prompt.build(&captured)
    roles = prompt.messages.map { |message| [message.role, Array(message.content).map(&:text).join] }
    expect(roles).to eq([["system", "judge instructions"], ["user", "key vs output"]])
  end

  it "constrains the answer with the schema and uses the configured model" do
    adapter.call(system: "judge", packet: "key vs output", schema: OmniAI::Evals::Judge.schema)
    expect(client).to have_received(:chat).with(
      model: "gemini-3.8-flash", format: an_instance_of(OmniAI::Schema::Format)
    )
  end

  it "honours the timeout rather than accepting and ignoring it" do
    allow(client).to receive(:chat) { sleep 0.2 }
    expect { adapter.call(system: "j", packet: "p", schema: nil, timeout: 0.01) }
      .to raise_error(Timeout::Error)
  end

  describe "the calls collector" do
    let(:calls) { [] }

    def judge(timeout: nil)
      adapter.call(system: "j", packet: "p", schema: nil, timeout:, calls:)
    end

    it "records the provider's verbatim finish reason" do
      allow(response).to receive(:finish_reason)
        .and_return(OmniAI::Chat::FinishReason.new(reason: :stop, value: "end_turn"))
      expect(judge).to eq({ "passed" => true, "reason" => "matches" })
      expect(calls).to eq([{ "finish_reason" => "end_turn", "latency_ms" => calls.first["latency_ms"],
                             "attempts" => 1, }])
      expect(calls.first["latency_ms"]).to be_an(Integer)
    end

    it "records unreported when the response has no finish reason" do
      allow(response).to receive(:finish_reason).and_return(nil)
      judge
      expect(calls.first["finish_reason"]).to eq("unreported")
    end

    it "records a timeout, then raises" do
      allow(client).to receive(:chat) { sleep 0.2 }
      expect { judge(timeout: 0.01) }.to raise_error(Timeout::Error)
      expect(calls.map { |c| c["finish_reason"] }).to eq(["timeout"])
    end

    it "records a failed request as an error, then raises" do
      allow(client).to receive(:chat).and_raise(IOError, "connection reset")
      expect { judge }.to raise_error(IOError)
      expect(calls.map { |c| c["finish_reason"] }).to eq(["error"])
    end
  end

  it "takes the same signature as the claude CLI adapter, so runners can swap them" do
    require "omniai/evals/adapters/claude_cli"
    signature = ->(klass) { klass.instance_method(:call).parameters.sort }
    expect(signature.call(described_class)).to eq(signature.call(OmniAI::Evals::Adapters::ClaudeCLI))
  end
end
