# frozen_string_literal: true

# Guard for the declared Ruby support floor (G-3, owner decision on issue #53:
# Option B). The gemspec previously declared `>= 3.0.0` while CI exercised
# only 3.2/3.3/3.4 — declared-but-untested support. The owner selected
# Option B: raise the declared floor to `>= 3.2` so the gem's declared support
# matches the CI-tested reality exactly. Static analysis (2026-11-02) found no
# 3.1/3.2-specific constructs, and the runtime floor evidence (suite executed
# on 3.0.7/3.1.6, 463/0) remains archived as historical record; Option B
# narrows the *declared* surface without requiring any code change.
require "spec_helper"
require "yaml"

RSpec.describe Ollama::Client do
  describe "declared Ruby support floor" do
    let(:gemspec_path) { File.expand_path("../../ollama-client.gemspec", __dir__) }
    let(:gemspec) { Gem::Specification.load(gemspec_path) }

    it "declares required_ruby_version >= 3.2.0, matching the CI-tested matrix" do
      expect(gemspec.required_ruby_version.to_s).to eq(">= 3.2.0")
    end

    it "matches the lowest Ruby version exercised by CI (.github/workflows/main.yml)" do
      ci_legs = YAML.safe_load_file(
        File.expand_path("../../.github/workflows/main.yml", __dir__),
        aliases: true
      ).dig("jobs", "test", "strategy", "matrix", "ruby")
      expect(gemspec.required_ruby_version.satisfied_by?(Gem::Version.new(ci_legs.min))).to be(true)
    end
  end
end
