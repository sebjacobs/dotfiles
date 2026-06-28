# frozen_string_literal: true

require_relative "../test_helper"

# Completion-drift smoke test.
#
# Each CLI we own declares its subcommands twice: once as a SUBCOMMANDS constant
# in its Ruby source (the dispatch's source of truth), and once in its zsh
# completion on the line tagged `# @subcommands`. The two are hand-maintained
# mirrors, so it's easy to add a command to one and forget the other — exactly
# what happened when `gwt mv` and `gwt prune` shipped but never reached the
# completion's command list.
#
# This flags any divergence as a WARNING, never a failure: a stale completion
# costs only a missing tab-suggestion, not a broken tool, so it shouldn't redden
# the suite. A genuinely missing convention marker (no SUBCOMMANDS, no
# `# @subcommands` line) does fail — that means the check itself is blind and
# would silently pass on real drift.
#
# jotter is excluded on purpose: it's a Go/cobra tool distributed via Homebrew
# whose completion asks the binary at runtime (`jotter __complete`), so it has no
# hand-kept copy of the command list to drift from.
module CompletionDrift
  REPO_ROOT = File.expand_path("../..", __dir__)

  TOOLS = [
    { name: "gwt",  source: "lib/gwt.rb",  completion: "zsh/gwt.zsh" },
    { name: "proj", source: "lib/proj.rb", completion: "zsh/projects.zsh" },
    { name: "svc",  source: "bin/svc",     completion: "zsh/completions/_svc" },
    { name: "dot",  source: "bin/dot",     completion: "zsh/completions/_dot" }
  ].freeze

  def self.read(relative_path)
    File.read(File.join(REPO_ROOT, relative_path))
  end

  # The words inside the first `SUBCOMMANDS = %w[...]` of a Ruby source file.
  def self.declared(source)
    read(source)[/SUBCOMMANDS\s*=\s*%w\[([^\]]*)\]/m, 1]&.split || []
  end

  # The words inside the parens of the `# @subcommands`-tagged completion line.
  def self.offered(completion)
    line = read(completion).lines.find { |l| l.include?("# @subcommands") }
    line&.slice(/\(([^)]*)\)/, 1)&.split || []
  end
end

class CompletionDriftTest < Minitest::Test
  CompletionDrift::TOOLS.each do |tool|
    define_method("test_#{tool[:name]}_completion_mirrors_subcommands") do
      declared = CompletionDrift.declared(tool[:source])
      offered = CompletionDrift.offered(tool[:completion])

      refute_empty declared, "no SUBCOMMANDS = %w[...] in #{tool[:source]}"
      refute_empty offered, "no `# @subcommands` line in #{tool[:completion]}"

      missing = declared - offered
      surplus = offered - declared
      warn_drift(tool, missing, surplus) unless missing.empty? && surplus.empty?
    end
  end

  private

  def warn_drift(tool, missing, surplus)
    report = ["completion drift in #{tool[:name]} (#{tool[:completion]}):"]
    report << "  missing from completion: #{missing.join(' ')}" unless missing.empty?
    report << "  not a real subcommand:   #{surplus.join(' ')}" unless surplus.empty?
    warn report.join("\n")
  end
end
