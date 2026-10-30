# frozen_string_literal: true

require "digest"

module OmniAI
  module Evals
    # Every criterion for a dataset, indexed by example id.
    class Criteria
      # @param dataset [Dataset]
      # @return [Criteria]
      def self.load(dataset:)
        index = {}
        digest = Digest::SHA256.new

        # Manifest order, not directory order: the sha has to be reproducible, and
        # Dir.glob's order is filesystem-dependent.
        dataset.examples.each do |example|
          path = File.join(dataset.dir, example.target)
          digest << File.binread(path)
          payload = Contract.check!(JSON.parse(File.read(path)), path:)
          index[payload.fetch("example_id")] = payload.fetch("criteria").map do |row|
            Criterion.new(
              id: row.fetch("id"),
              family: row.fetch("family"),
              type: row.fetch("type"),
              scorer: row.fetch("scorer"),
              target: row.fetch("target", {}),
              provenance: row.fetch("provenance", {})
            )
          end
        end

        new(index:, sha256: digest.hexdigest)
      end

      attr_reader :sha256

      def initialize(index:, sha256:)
        @index = index.freeze
        @sha256 = sha256
        freeze
      end

      # @return [Array<Criterion>]
      def for(example_id) = @index.fetch(example_id, [])

      # @return [Array<Criterion>]
      def all = @index.values.flatten
    end
  end
end
