# frozen_string_literal: true

require "digest"

module OmniAI
  module Evals
    # A frozen set of examples, identified by a content hash.
    class Dataset
      attr_reader :name, :examples, :dir

      # @param path [String] the manifest.json to load
      # @raise [ContractError]
      # @return [Dataset]
      def self.load(path)
        payload = Contract.check!(JSON.parse(File.read(path)), path:)
        examples = payload.fetch("examples", []).map do |row|
          Example.new(
            id: row.fetch("id"),
            input: row.fetch("input"),
            target: row.fetch("target"),
            metadata: row.fetch("metadata", {})
          )
        end
        new(name: payload.fetch("name"), examples:, dir: File.dirname(File.expand_path(path)),
          manifest_bytes: File.binread(path))
      end

      def initialize(name:, examples:, dir:, manifest_bytes:)
        @name = name
        @examples = examples.freeze
        @dir = dir
        @manifest_bytes = manifest_bytes
      end

      # Absolute path to an example's input file.
      #
      # @raise [ContractError] for an input with no file behind it. "messages" inputs are
      #   inline, so asking for their path is a caller bug, not a missing file -- saying so
      #   beats returning a path that does not exist.
      def input_path_for(example)
        path = example.input["path"]
        raise ContractError, %(example #{example.id}: input kind "#{example.input['kind']}" has no path) if path.nil?

        File.join(@dir, path)
      end

      # Every example's input file, in manifest order. Inline inputs contribute nothing.
      def input_paths
        @examples.filter_map { |example| example.input["path"] && input_path_for(example) }
      end

      # SHA-256 over the manifest bytes plus every referenced input file, in manifest
      # order. Hashing the file CONTENT rather than its path is what makes a re-render a
      # different dataset -- the manifest is byte-identical when only the pixels changed.
      def sha256
        @sha256 ||= begin
          digest = Digest::SHA256.new
          digest << @manifest_bytes
          input_paths.each { |path| digest << File.binread(path) }
          digest.hexdigest
        end
      end
    end
  end
end
