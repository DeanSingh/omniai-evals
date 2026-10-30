# frozen_string_literal: true

module OmniAI
  module Evals
    # The version stamped into every file the gem reads or writes. Bump it in the same
    # commit as any change to a format in docs/contract.md section 3 -- the fixtures under
    # spec/fixtures/contract/ are pinned to it, so a silent format drift fails the suite.
    CONTRACT_VERSION = 1

    # Guards the "contract" field on every file we load.
    module Contract
    module_function

      # @param payload [Hash] a parsed JSON document
      # @param path [String] where it came from, for the error message
      # @raise [ContractError]
      # @return [Hash] the payload, unchanged
      def check!(payload, path:)
        version = payload["contract"]
        raise ContractError, %(#{path}: missing "contract" version) if version.nil?
        raise ContractError, "#{path}: contract #{version}, expected #{CONTRACT_VERSION}" unless
          version == CONTRACT_VERSION

        payload
      end
    end
  end
end
