# frozen_string_literal: true

require "timeout"

require_relative "../../evals"
require_relative "call_record"

begin
  require "omniai"
rescue LoadError
  raise OmniAI::Evals::AdapterNotLoaded,
    'Adapters::OmniAI needs the omniai gem: add `gem "omniai"` to your Gemfile'
end

module OmniAI
  module Evals
    # Judge adapters. Each reaches a model, so none of them is required by the core --
    # a consumer requires the one it wants.
    module Adapters
      # The default judge adapter: API-billed, structured output via OmniAI::Schema.format.
      #
      # "Default" is a documentation claim, not an implicit require. The core loads on
      # stdlib alone (invariant 3), so requiring this file is the consumer's decision and
      # AdapterNotLoaded names what is missing when the gem is absent.
      #
      # Behaviour-equivalent to Adapters::ClaudeCLI by design, and the signature is the
      # contract's call(system:, packet:, model:, schema:, timeout:) so a runner can swap
      # one for the other without touching the call site. Equivalence is not cosmetic:
      # judge calibration measured on one adapter only transfers to the other if both put
      # the same content in the same role.
      class OmniAI
        # @param client [OmniAI::Client]
        # @param model [String] the default model, overridable per call
        def initialize(client:, model:)
          @client = client
          @model = model
        end

        # @param system [String] the judge's system prompt -- static and PHI-free
        # @param packet [String] the PHI-bearing user content
        # @param schema [Hash] a plain JSON Schema, per Judge.schema
        # @param timeout [Integer, nil] wall-clock cap, matching ClaudeCLI's
        # @param calls [#<<, nil] an optional collector; each call pushes exactly one CallRecord
        #   (the response's verbatim finish reason) however it ends, before any error is raised.
        # @return [Hash] matching `schema`
        def call(system:, packet:, model: nil, schema: nil, timeout: nil, calls: nil)
          # A REAL system turn, not a system prompt glued onto the front of the user
          # message. ClaudeCLI passes it via --system-prompt, and an adapter that
          # instead prepends it to the user content is asking the model a different
          # question -- which silently invalidates any calibration carried across.
          response = CallRecord.capture_response(calls, timeout_error: Timeout::Error) do
            Timeout.timeout(timeout) do
              @client.chat(model: model || @model, format: format_for(schema)) do |prompt|
                prompt.system(system)
                prompt.user(packet)
              end
            end
          end
          JSON.parse(response.text)
        end

        # Schema.format wants an OmniAI::Schema::Object and the core deals in plain JSON
        # Schema Hashes, so the translation belongs here at the boundary.
        def format_for(schema)
          return nil if schema.nil?

          ::OmniAI::Schema.format(name: "verdict", schema: ::OmniAI::Schema.deserialize(schema))
        end
      end
    end
  end
end
