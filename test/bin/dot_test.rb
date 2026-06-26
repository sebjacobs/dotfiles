# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
ScriptTest.load_script("../bin/dot")

class DotPureTest < Minitest::Test
  def test_parse_returns_entries_sorted_by_name
    yaml = <<~YAML
      svc:
        desc: launchd agents
        location: bin/svc
        repo: dotfiles
      gwt:
        desc: worktrees
        location: bin/gwt-helper
        repo: dotfiles
    YAML

    names = Dot.parse(yaml).map { |e| e[:name] }
    assert_equal %w[gwt svc], names
  end

  def test_parse_reads_all_fields
    yaml = <<~YAML
      gwt:
        desc: worktrees
        location: bin/gwt-helper
        repo: dotfiles
    YAML

    entry = Dot.parse(yaml).first
    assert_equal({ name: "gwt", desc: "worktrees", location: "bin/gwt-helper", repo: "dotfiles" }, entry)
  end

  def test_parse_tolerates_missing_keys
    entry = Dot.parse("gwt:\n").first
    assert_equal({ name: "gwt", desc: "", location: "", repo: "" }, entry)
  end

  def test_parse_of_blank_manifest_is_empty
    assert_empty Dot.parse("")
    assert_empty Dot.parse(nil)
  end

  def test_resolve_location_joins_relative_against_home
    assert_equal "/home/dot/bin/gwt-helper", Dot.resolve_location("bin/gwt-helper", "/home/dot")
  end

  def test_resolve_location_keeps_absolute_as_is
    assert_equal "/usr/local/bin/dox", Dot.resolve_location("/usr/local/bin/dox", "/home/dot")
  end

  def test_resolve_location_expands_tilde
    assert_equal File.join(Dir.home, ".local/bin/dox"),
                 Dot.resolve_location("~/.local/bin/dox", "/home/dot")
  end

  def test_ls_lines_aligns_descriptions_to_widest_name
    entries = [
      { name: "gwt", desc: "worktrees" },
      { name: "ruby-lsp-reap", desc: "reaper" }
    ]
    lines = Dot.ls_lines(entries)
    assert_equal "gwt            worktrees", lines[0]
    assert_equal "ruby-lsp-reap  reaper", lines[1]
  end

  def test_fuzzy_match_prefers_exact
    assert_equal ["gwt"], Dot.fuzzy_match(%w[gwt gwt-extra], "gwt")
  end

  def test_fuzzy_match_falls_back_to_prefix_then_substring
    assert_equal ["gwt-extra"], Dot.fuzzy_match(%w[gwt-extra proj], "gwt")
    assert_equal ["proj"], Dot.fuzzy_match(%w[gwt proj], "roj")
  end
end

class DotAppTest < Minitest::Test
  MANIFEST = <<~YAML
    gwt:
      desc: Git worktree manager
      location: bin/gwt-helper
      repo: dotfiles
    dox:
      desc: docker-compose helper
      location: ~/.local/bin/dox
      repo: dox
  YAML

  def setup
    @sys = FakeSystem.new
    @out = StringIO.new
    @err = StringIO.new
    @run_calls = []
    @sys.add_file("/cfg/tools.yml", MANIFEST)
  end

  def test_ls_lists_tools_with_descriptions
    assert_equal 0, build_app.run(["ls"])
    out = @out.string
    assert_includes out, "gwt  Git worktree manager"
    assert_includes out, "dox  docker-compose helper"
  end

  def test_bare_invocation_defaults_to_ls
    assert_equal 0, build_app.run([])
    assert_includes @out.string, "Git worktree manager"
  end

  def test_ls_reports_missing_manifest
    @sys = FakeSystem.new
    assert_equal 1, build_app.run(["ls"])
    assert_includes @err.string, "no registry at /cfg/tools.yml"
  end

  def test_ls_reports_empty_registry
    @sys = FakeSystem.new
    @sys.add_file("/cfg/tools.yml", "")
    assert_equal 0, build_app.run(["ls"])
    assert_includes @out.string, "No tools registered"
  end

  def test_show_prints_fields_and_resolved_path
    assert_equal 0, build_app.run(["show", "gwt"])
    out = @out.string
    assert_includes out, "desc     : Git worktree manager"
    assert_includes out, "location : bin/gwt-helper"
    assert_includes out, "repo     : dotfiles"
    assert_includes out, "path     : /home/dot/bin/gwt-helper"
  end

  def test_show_resolves_out_of_repo_tilde_location
    assert_equal 0, build_app.run(["show", "dox"])
    assert_includes @out.string, "path     : #{File.join(Dir.home, '.local/bin/dox')}"
  end

  def test_where_prints_only_the_resolved_path
    assert_equal 0, build_app.run(["where", "gwt"])
    assert_equal "/home/dot/bin/gwt-helper", @out.string.chomp
  end

  def test_where_matches_a_unique_prefix
    assert_equal 0, build_app.run(["where", "gw"])
    assert_equal "/home/dot/bin/gwt-helper", @out.string.chomp
  end

  def test_where_errors_on_unknown_tool
    assert_equal 1, build_app.run(["where", "nope"])
    assert_includes @err.string, "No tool matching: nope"
  end

  def test_show_requires_a_tool_name
    assert_equal 1, build_app.run(["show"])
    assert_includes @err.string, "Usage: dot show <tool>"
  end

  def test_reload_runs_setup_script
    assert_equal 0, build_app.run(["reload"])
    assert_equal ["sh", "/home/dot/setup.sh"], @run_calls.last
  end

  def test_help_prints_usage
    assert_equal 0, build_app.run(["help"])
    assert_includes @out.string, "Usage: dot"
  end

  def test_unknown_command_is_usage_error
    assert_equal 1, build_app.run(["wat"])
    assert_includes @out.string, "Usage: dot"
  end

  private

  def build_app
    Dot::App.new(
      sys: @sys, out: @out, err: @err,
      manifest_path: "/cfg/tools.yml", home: "/home/dot",
      run: ->(*args) { @run_calls << args }
    )
  end

  class FakeSystem
    def initialize = @files = {}

    def add_file(path, contents) = @files[path] = contents

    def read(path) = @files.fetch(path, "")

    def exist?(path) = @files.key?(path)
  end
end
