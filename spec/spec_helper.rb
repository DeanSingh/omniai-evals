# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  enable_coverage :branch
end

require "open3"
require "rbconfig"
require "tmpdir"

require "omniai/evals"

# Absolute path to a file under spec/fixtures/.
def fixture_path(*parts)
  File.join(__dir__, "fixtures", *parts)
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
