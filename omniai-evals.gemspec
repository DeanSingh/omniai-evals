# frozen_string_literal: true

require_relative "lib/omniai/evals/version"

Gem::Specification.new do |spec|
  spec.name = "omniai-evals"
  spec.version = OmniAI::Evals::VERSION
  spec.license = "MIT"
  spec.authors = ["Dean Singh"]
  spec.email = ["dean.singh@gmail.com"]

  spec.summary = "Structure and grading for LLM evals"
  spec.description = "Datasets, boolean criteria, assertions, judges, reducers, and PHI-free " \
    "scorecards. A companion to the omniai gem family."
  spec.homepage = "https://github.com/DeanSingh/omniai-evals"

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("{lib}/**/*") + %w[README.md CHANGELOG.md LICENSE Gemfile]

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  spec.require_paths = ["lib"]

  # `omniai` backs Adapters::OmniAI, which the consumer requires explicitly.
  # The core deliberately does NOT require it (contract invariant 3).
  spec.add_dependency "omniai", "~> 3.8"
end
