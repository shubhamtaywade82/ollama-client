# frozen_string_literal: true

require_relative "lib/ollama/version"

Gem::Specification.new do |spec|
  spec.name = "ollama-client"
  spec.version = Ollama::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "A low-level, opinionated Ollama client for LLM-based hybrid agents"
  spec.description = "A production-ready Ruby client for Ollama API with schema validation, " \
                     "retries, and agent-safe defaults. Designed for LLM-based hybrid agents, " \
                     "not chatbots."
  spec.homepage = "https://github.com/shubhamtaywade82/ollama-client"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/shubhamtaywade82/ollama-client"
  spec.metadata["changelog_uri"] = "https://github.com/shubhamtaywade82/ollama-client/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "bigdecimal"
  spec.add_dependency "json-schema", "~> 4.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
