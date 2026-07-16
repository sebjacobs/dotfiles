# frozen_string_literal: true

require_relative "../test_helper"
require "yaml"

# Registry-drift smoke test.
#
# `dot` reads a hand-edited registry (.config/dot/tools.yml, symlinked to
# ~/.config) that is meant to be the directory of every CLI I own. Nothing ties
# it to bin/, so the failure mode is silent: a script lands, setup.sh symlinks
# it onto PATH, it works perfectly — and never reaches `dot ls`, the one tool
# whose whole job is telling me it exists. That had already happened to seven
# scripts by the time this check was written.
#
# Both checks warn rather than fail, mirroring completion_drift_test.rb: an
# unregistered tool costs a line in `dot ls`, a dangling location costs a wrong
# `dot where`. Neither breaks a tool, so neither should redden the suite. A
# blind check does fail — an unreadable registry or an empty bin/ means this
# test would sail past real drift while looking healthy.
#
# Only tools whose location is relative (i.e. in this repo) are checked for
# existence. The ~/absolute ones — dox, gwt, jotter, notes, tasks — live in
# other repos and are installed per-machine, so asserting on them here would
# fail on a fresh checkout for reasons that have nothing to do with drift.
module RegistryDrift
  REPO_ROOT = File.expand_path("../..", __dir__)
  REGISTRY = ".config/dot/tools.yml"

  # Executables in bin/ that are deliberately absent from the registry. A tool
  # belongs here only if it isn't a CLI in its own right — not merely because
  # registering it hasn't got round to happening yet.
  EXEMPT = {
    "dot" => "the registry's reader — it renders the directory rather than appearing in it",
    "yt-dlp-innit" => "a one-line yt-dlp wrapper: no shebang, no flags, no usage of its own",
    "yt-dlp-mp4" => "a one-line yt-dlp wrapper: no shebang, no flags, no usage of its own"
  }.freeze

  def self.path(*parts) = File.join(REPO_ROOT, *parts)

  # Every executable file directly in bin/, minus the exempt ones.
  def self.executables
    Dir.children(path("bin"))
       .reject { |name| File.directory?(path("bin", name)) }
       .select { |name| File.executable?(path("bin", name)) }
       .reject { |name| EXEMPT.key?(name) }
       .sort
  end

  def self.registry
    YAML.safe_load(File.read(path(REGISTRY))) || {}
  rescue SystemCallError, Psych::SyntaxError
    {}
  end

  # Registered names, keyed however the tool is invoked.
  def self.registered_names = registry.keys.sort

  # name => location for entries that resolve inside this repo.
  def self.in_repo_locations
    registry.filter_map do |name, attrs|
      location = (attrs || {})["location"].to_s
      next if location.empty? || location.start_with?("~", "/")

      [name, location]
    end.to_h
  end
end

class RegistryDriftTest < Minitest::Test
  def test_registry_is_readable_and_populated
    refute_empty RegistryDrift.registered_names,
                 "no tools parsed from #{RegistryDrift::REGISTRY} — this check is blind"
  end

  def test_bin_has_executables_to_check
    refute_empty RegistryDrift.executables,
                 "no executables found in bin/ — this check is blind"
  end

  def test_every_bin_executable_is_registered
    unregistered = RegistryDrift.executables - RegistryDrift.registered_names
    return if unregistered.empty?

    warn <<~DRIFT
      registry drift (#{RegistryDrift::REGISTRY}):
        in bin/ but not registered, so invisible to `dot ls`:
      #{unregistered.map { |name| "    #{name}" }.join("\n")}
        register each with a desc + location, or add it to RegistryDrift::EXEMPT with a reason.
    DRIFT
  end

  def test_registered_in_repo_tools_exist
    dangling = RegistryDrift.in_repo_locations.reject do |_name, location|
      File.exist?(RegistryDrift.path(location))
    end
    return if dangling.empty?

    warn <<~DRIFT
      registry drift (#{RegistryDrift::REGISTRY}):
        registered but the location does not exist, so `dot where` lies:
      #{dangling.map { |name, location| "    #{name} -> #{location}" }.join("\n")}
    DRIFT
  end
end
