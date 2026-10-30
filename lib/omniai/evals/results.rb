# frozen_string_literal: true

module OmniAI
  module Evals
    # The JSONL results file.
    module Results
    module_function

      # Appends rather than truncates: a run writes epoch by epoch, and losing the
      # earlier epochs to a reopen would silently change every reduced verdict.
      #
      # Appending is therefore also the hazard. Re-running a runner into a path that
      # already holds another run doubles every epoch, and the reducer sees 2n epochs
      # without anything raising -- a PASS built from two runs it was never asked to
      # combine. So a file holds exactly one run_id, and a second one is refused.
      #
      # @param records [Array<Hash>]
      # @raise [Error] when the records do not belong to the file's existing run
      def write(path, records)
        return if records.empty?

        guard_run_id!(path, records)
        File.open(path, "a") do |file|
          records.each { |record| file.puts(JSON.generate(record)) }
        end
      end

      def guard_run_id!(path, records)
        incoming = records.map { |record| record.fetch("run_id") }.uniq
        raise Error, "records span #{incoming.size} run_ids: #{incoming.join(', ')}" unless incoming.size == 1
        return unless File.exist?(path) && !File.empty?(path)

        existing = JSON.parse(File.foreach(path).first).fetch("run_id")
        return if existing == incoming.first

        raise Error, "#{path} holds run #{existing}; refusing to append run #{incoming.first}"
      end

      # @raise [ContractError]
      # @return [Array<Hash>]
      def read(path)
        File.readlines(path).reject { |line| line.strip.empty? }.map.with_index(1) do |line, number|
          Contract.check!(JSON.parse(line), path: "#{path}:#{number}")
        end
      end
    end
  end
end
