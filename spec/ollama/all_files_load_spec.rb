# frozen_string_literal: true

require "spec_helper"

# Every file under lib/ should load in isolation once ollama_client is
# required. This is a blunt but effective regression guard: it's exactly how
# the middleware (class reopened as module), policies (superclass mismatch,
# broken require paths), and Ollama::Tool (missing require in the main load
# path) bugs were found — files that were never `require`d anywhere, so
# nothing ever caught them raising TypeError/NameError/LoadError on load.
#
# This does not assert the files are *wired into* Client's default behavior
# (some deliberately aren't — see lib/ollama/policies/base.rb and
# lib/ollama/agent/executor.rb for two documented examples) — only that
# `require`ing them doesn't raise.
RSpec.describe "every lib/ file" do
  lib_root = File.expand_path("../../lib", __dir__)
  # Shallower paths first: e.g. policies/retry.rb must load before
  # policies/retry/strategies/*.rb, which depend on retry.rb having already
  # established Retry's superclass. Dir.glob's own default ordering visits
  # the retry/ subdirectory before the retry.rb file at the same level.
  all_files = Dir.glob("#{lib_root}/**/*.rb").sort_by { |f| [f.count("/"), f] }

  it "found more than zero files to check" do
    expect(all_files).not_to be_empty
  end

  all_files.each do |path|
    relative = Pathname.new(path).relative_path_from(Pathname.new(lib_root)).to_s.delete_suffix(".rb")

    it "loads #{relative} without raising" do
      expect { require relative }.not_to raise_error
    end
  end
end
