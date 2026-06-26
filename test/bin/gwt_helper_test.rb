#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
ScriptTest.load_script("../bin/gwt-helper")

class GwtPureTest < Minitest::Test
  def test_encode_branch_replaces_slashes
    assert_equal "spike+twitter-classifier", Gwt.encode_branch("spike/twitter-classifier")
  end

  def test_encode_branch_passes_through_plain_names
    assert_equal "feature-x", Gwt.encode_branch("feature-x")
  end

  def test_encode_branch_replaces_every_slash
    assert_equal "a+b+c", Gwt.encode_branch("a/b/c")
  end

  def test_fuzzy_match_prefers_exact
    assert_equal ["foo"], Gwt.fuzzy_match(%w[foo foobar foo-baz], "foo")
  end

  def test_fuzzy_match_falls_back_to_prefix
    assert_equal %w[foobar foo-baz], Gwt.fuzzy_match(%w[foobar foo-baz other], "foo")
  end

  def test_fuzzy_match_falls_back_to_substring
    assert_equal %w[my-foo-wt], Gwt.fuzzy_match(%w[my-foo-wt other], "foo")
  end

  def test_fuzzy_match_returns_empty_when_nothing_matches
    assert_empty Gwt.fuzzy_match(%w[alpha beta], "zzz")
  end

  def test_format_position_ahead_and_behind
    assert_equal " ↑2 ↓1", Gwt.format_position(2, 1)
  end

  def test_format_position_ahead_only
    assert_equal " ↑3", Gwt.format_position(3, 0)
  end

  def test_format_position_behind_only
    assert_equal " ↓4", Gwt.format_position(0, 4)
  end

  def test_format_position_level
    assert_equal "", Gwt.format_position(0, 0)
  end

  def test_parse_ahead_behind_splits_tab
    assert_equal [3, 1], Gwt.parse_ahead_behind("1\t3")
  end

  def test_parse_ahead_behind_handles_blank
    assert_equal [0, 0], Gwt.parse_ahead_behind("")
  end

  def test_current_worktree_path_inside_a_worktree
    assert_equal "/repo/.claude/worktrees/foo",
                 Gwt.current_worktree_path("/repo/.claude/worktrees/foo/lib/x.rb", "/repo/.claude/worktrees")
  end

  def test_current_worktree_path_outside_returns_nil
    assert_nil Gwt.current_worktree_path("/repo/src", "/repo/.claude/worktrees")
  end

  def test_parse_worktrees_extracts_path_and_branch
    porcelain = <<~PORCELAIN
      worktree /repo
      branch refs/heads/main

      worktree /repo/.claude/worktrees/foo
      branch refs/heads/feature/x

    PORCELAIN
    assert_equal(
      [{path: "/repo", branch: "main"},
       {path: "/repo/.claude/worktrees/foo", branch: "feature/x"}],
      Gwt.parse_worktrees(porcelain)
    )
  end

  def test_parse_worktrees_marks_detached_head
    porcelain = "worktree /repo/wt/d\nHEAD abc123\ndetached\n\n"
    assert_equal [{path: "/repo/wt/d", branch: "(detached)"}], Gwt.parse_worktrees(porcelain)
  end

  def test_parse_worktrees_handles_empty_input
    assert_empty Gwt.parse_worktrees("")
  end

  def test_parse_worktrees_flags_prunable_entries
    porcelain = "worktree /repo/wt/p\nbranch refs/heads/b\n" \
                "prunable gitdir file points to non-existent location\n\n"
    entry = Gwt.parse_worktrees(porcelain).first
    assert_equal "/repo/wt/p", entry[:path]
    assert_equal "gitdir file points to non-existent location", entry[:prunable]
  end

  def test_slug_error_accepts_plain_and_slashed_names
    assert_nil Gwt.slug_error("feature/x")
    assert_nil Gwt.slug_error("spike-2_a.b")
  end

  def test_slug_error_rejects_overlong_names
    assert_match(/64 characters or fewer/, Gwt.slug_error("a" * 65))
  end

  def test_slug_error_rejects_dot_segments
    assert_match(/"\." or "\.\."/, Gwt.slug_error("foo/../bar"))
    assert_match(/"\." or "\.\."/, Gwt.slug_error("."))
  end

  def test_slug_error_rejects_reserved_git_segment
    assert_match(/reserved git directory/, Gwt.slug_error("foo/.git"))
    assert_match(/reserved git directory/, Gwt.slug_error(".GIT"))
  end

  def test_slug_error_rejects_empty_segments
    assert_match(/empty path segments/, Gwt.slug_error("foo//bar"))
    assert_match(/empty path segments/, Gwt.slug_error("/foo"))
  end

  def test_slug_error_rejects_illegal_characters
    assert_match(/letters, digits/, Gwt.slug_error("foo bar"))
    assert_match(/letters, digits/, Gwt.slug_error("foo:bar"))
  end
end

class GwtAppTest < Minitest::Test
  ROOT = "/repo"
  WT_BASE = "/repo/.claude/worktrees"

  # Records git invocations and replays canned captures keyed by joined argv.
  class FakeGit
    attr_reader :runs

    def initialize(captures: {}, run_ok: true)
      @captures = captures
      @run_ok = run_ok
      @runs = []
    end

    def capture(*args, **)
      @captures.fetch(args.join(" "), ["", true])
    end

    def run(*args)
      @runs << args
      @run_ok
    end
  end

  class FakeSys
    attr_reader :copies, :removes

    def initialize(dirs: [], children: {}, which: true, exists: [])
      @dirs = dirs
      @children = children
      @which = which
      @exists = exists
      @copies = []
      @removes = []
    end

    def dir?(path) = @dirs.include?(path)
    def exist?(path) = @exists.include?(path) || @dirs.include?(path)
    def children(path) = @children.fetch(path, [])
    def which?(_cmd) = @which
    def copy_into(src, dst) = @copies << [src, dst]
    def remove(path) = @removes << path
  end

  def build(git: FakeGit.new, sys: FakeSys.new, pwd: ROOT, confirm: ->(_) { true },
            worktree_subdir: ".claude/worktrees", worktrees: [])
    @out = StringIO.new
    @err = StringIO.new
    @cd = []
    @execs = []
    git_with_root = with_root(git, worktrees)
    app = Gwt::App.new(
      git: git_with_root,
      sys: sys,
      out: @out,
      err: @err,
      cd: ->(p) { @cd << p },
      confirm: confirm,
      pwd: pwd,
      exec: ->(*a) { @execs << a },
      worktree_subdir: worktree_subdir
    )
    [app, git_with_root, sys]
  end

  # Every run parses `worktree list --porcelain` first to discover the root and
  # the registered worktrees. Seed it from the requested worktrees ([path, branch]
  # pairs, paths relative to WT_BASE) so tests register worktrees via git, the way
  # the real tool sees them — never by faking directory contents.
  def with_root(git, worktrees = [])
    git.instance_variable_get(:@captures)["worktree list --porcelain"] ||=
      [porcelain(worktrees), true]
    git
  end

  def porcelain(worktrees)
    text = +"worktree /repo\nbranch refs/heads/main\n\n"
    worktrees.each do |name, branch, prunable|
      text << "worktree #{WT_BASE}/#{name}\n"
      text << (branch ? "branch refs/heads/#{branch}\n" : "detached\n")
      text << "prunable #{prunable}\n" if prunable
      text << "\n"
    end
    text
  end

  def test_add_creates_worktree_and_cds_in
    app, git, = build
    status = app.run(["add", "feature/x"])
    assert_equal 0, status
    assert_includes git.runs, ["worktree", "add", "/repo/.claude/worktrees/feature+x", "feature/x"]
    assert_equal ["/repo/.claude/worktrees/feature+x"], @cd
  end

  def test_add_with_dash_b_creates_branch
    app, git, = build
    app.run(["add", "-b", "feature/x"])
    assert_includes git.runs, ["worktree", "add", "-b", "feature/x", "/repo/.claude/worktrees/feature+x"]
  end

  def test_add_on_registered_worktree_cds_without_recreating
    app, git, = build(worktrees: [["feature+x", "feature/x"]])
    status = app.run(["add", "feature/x"])
    assert_equal 0, status
    assert_empty git.runs
    assert_equal ["/repo/.claude/worktrees/feature+x"], @cd
    assert_match(/already exists/, @out.string)
  end

  def test_add_on_untracked_directory_errors_pointing_at_prune
    sys = FakeSys.new(dirs: ["/repo/.claude/worktrees/feature+x"])
    app, git, = build(sys: sys)
    assert_equal 1, app.run(["add", "feature/x"])
    assert_empty git.runs
    assert_empty @cd
    assert_match(/gwt prune/, @err.string)
  end

  def test_add_without_branch_errors
    app, = build
    assert_equal 1, app.run(["add"])
    assert_match(/Usage: gwt add/, @err.string)
  end

  def test_add_rejects_invalid_slug_before_touching_git
    app, git, = build
    assert_equal 1, app.run(["add", "foo/../bar"])
    assert_match(/Invalid worktree name "foo\/\.\.\/bar"/, @err.string)
    assert_empty git.runs
    assert_empty @cd
  end

  def test_add_rejects_a_name_colliding_with_a_subcommand
    app, git, = build
    assert_equal 1, app.run(["add", "cd"])
    assert_match(/"cd" is a reserved gwt subcommand/, @err.string)
    assert_empty git.runs
    assert_empty @cd
  end

  def test_add_rejects_a_reserved_name_with_dash_b
    app, git, = build
    assert_equal 1, app.run(["add", "-b", "status"])
    assert_match(/"status" is a reserved gwt subcommand/, @err.string)
    assert_empty git.runs
    assert_empty @cd
  end

  def test_add_allows_a_slashed_name_whose_segment_matches_a_subcommand
    app, git, = build
    assert_equal 0, app.run(["add", "feature/cd"])
    assert_includes git.runs, ["worktree", "add", "#{WT_BASE}/feature+cd", "feature/cd"]
  end

  def test_cd_exact_match
    app, = build(worktrees: [["foo", "b"]])
    assert_equal 0, app.run(["cd", "foo"])
    assert_equal ["#{WT_BASE}/foo"], @cd
  end

  def test_cd_fuzzy_unique_match
    app, = build(worktrees: [["foobar", "b"], ["other", "b"]])
    assert_equal 0, app.run(["cd", "foo"])
    assert_equal ["#{WT_BASE}/foobar"], @cd
  end

  def test_cd_accepts_slashed_branch_name
    app, = build(worktrees: [["feedback+x", "feedback/x"]])
    assert_equal 0, app.run(["cd", "feedback/x"])
    assert_equal ["#{WT_BASE}/feedback+x"], @cd
  end

  def test_cd_ambiguous_match_errors
    app, = build(worktrees: [["foo-a", "b"], ["foo-b", "b"]])
    assert_equal 1, app.run(["cd", "foo"])
    assert_empty @cd
    assert_match(/Multiple worktrees match 'foo'/, @err.string)
  end

  def test_cd_no_match_errors
    app, = build(worktrees: [["alpha", "b"]])
    assert_equal 1, app.run(["cd", "zzz"])
    assert_match(/No worktree matching: zzz/, @err.string)
  end

  def test_cd_ignores_orphaned_directory
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[orphan] })
    app, = build(sys: sys, worktrees: [])
    assert_equal 1, app.run(["cd", "orphan"])
    assert_empty @cd
    assert_match(/No worktree matching: orphan/, @err.string)
  end

  def test_path_echoes_resolved_path
    app, = build(worktrees: [["foo", "b"]])
    assert_equal 0, app.run(["path", "foo"])
    assert_equal "#{WT_BASE}/foo\n", @out.string
  end

  def test_path_no_arg_inside_worktree
    app, = build(pwd: "#{WT_BASE}/foo/lib")
    assert_equal 0, app.run(["path"])
    assert_equal "#{WT_BASE}/foo\n", @out.string
  end

  def test_path_no_arg_outside_worktree_errors
    app, = build(pwd: "/repo/src")
    assert_equal 1, app.run(["path"])
    assert_match(/Usage: gwt path/, @err.string)
  end

  def test_root_cds_to_main
    app, = build(pwd: "#{WT_BASE}/foo")
    assert_equal 0, app.run(["root"])
    assert_equal [ROOT], @cd
  end

  def test_root_path_echoes_main
    app, = build
    assert_equal 0, app.run(["root", "-p"])
    assert_equal "#{ROOT}\n", @out.string
    assert_empty @cd
  end

  def test_rm_declined_does_not_remove
    app, git, = build(worktrees: [["foo", "b"]], confirm: ->(_) { false })
    assert_equal 1, app.run(["rm", "foo"])
    assert_empty git.runs
    assert_empty @cd
  end

  def test_rm_confirmed_removes_and_cds_out_when_inside
    app, git, = build(worktrees: [["foo", "b"]], pwd: "#{WT_BASE}/foo/lib", confirm: ->(_) { true })
    assert_equal 0, app.run(["rm", "foo"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo"]
    assert_equal [ROOT], @cd
  end

  def test_rm_confirmed_no_cd_when_outside
    app, = build(worktrees: [["foo", "b"]], pwd: "/repo/src", confirm: ->(_) { true })
    app.run(["rm", "foo"])
    assert_empty @cd
  end

  def test_rm_orphaned_directory_falls_back_to_rm
    sys = FakeSys.new(dirs: ["#{WT_BASE}/orphan"])
    app, git, sys = build(sys: sys, worktrees: [], confirm: ->(_) { true })
    assert_equal 0, app.run(["rm", "orphan"])
    assert_empty git.runs
    assert_includes sys.removes, "#{WT_BASE}/orphan"
  end

  def test_rm_orphaned_directory_declined_removes_nothing
    sys = FakeSys.new(dirs: ["#{WT_BASE}/orphan"])
    app, _, sys = build(sys: sys, worktrees: [], confirm: ->(_) { false })
    assert_equal 1, app.run(["rm", "orphan"])
    assert_empty sys.removes
  end

  def test_rm_force_passes_force_to_git_and_skips_confirm
    app, git, = build(worktrees: [["foo", "b"]], confirm: ->(_) { flunk "should not prompt with -f" })
    assert_equal 0, app.run(["rm", "-f", "foo"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo", "--force"]
  end

  def test_rm_force_on_orphan_skips_confirm
    sys = FakeSys.new(dirs: ["#{WT_BASE}/orphan"])
    app, _, sys = build(sys: sys, worktrees: [], confirm: ->(_) { flunk "should not prompt with -f" })
    assert_equal 0, app.run(["rm", "-f", "orphan"])
    assert_includes sys.removes, "#{WT_BASE}/orphan"
  end

  def test_rm_force_accepts_long_flag
    app, git, = build(worktrees: [["foo", "b"]], confirm: ->(_) { flunk "should not prompt with --force" })
    assert_equal 0, app.run(["rm", "--force", "foo"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo", "--force"]
  end

  def test_rm_force_flag_after_name
    app, git, = build(worktrees: [["foo", "b"]], confirm: ->(_) { flunk "should not prompt with --force" })
    assert_equal 0, app.run(["rm", "foo", "--force"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo", "--force"]
  end

  def test_rm_short_flag_after_name
    app, git, = build(worktrees: [["foo", "b"]], confirm: ->(_) { flunk "should not prompt with -f" })
    assert_equal 0, app.run(["rm", "foo", "-f"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo", "--force"]
  end

  def test_rm_accepts_slashed_branch_name_and_removes_encoded_dir
    app, git, = build(worktrees: [["feedback+x", "feedback/x"]], confirm: ->(_) { true })
    assert_equal 0, app.run(["rm", "feedback/x"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/feedback+x"]
  end

  def test_rm_prefix_matches_unique_worktree
    app, git, = build(worktrees: [["feedback+suggestions", "feedback/suggestions"], ["other", "b"]], confirm: ->(_) { true })
    assert_equal 0, app.run(["rm", "feedback/suggestion"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/feedback+suggestions"]
  end

  def test_rm_ambiguous_match_aborts_without_removing
    app, git, = build(worktrees: [["foo-a", "b"], ["foo-b", "b"]], confirm: ->(_) { flunk "should not prompt when ambiguous" })
    assert_equal 1, app.run(["rm", "foo"])
    assert_empty git.runs.select { |r| r.first == "worktree" && r[1] == "remove" }
    assert_match(/Multiple worktrees match 'foo'/, @err.string)
  end

  def test_rm_missing_worktree_errors
    app, = build
    assert_equal 1, app.run(["rm", "nope"])
    assert_match(/No worktree: nope/, @err.string)
  end

  def test_zed_named_execs_in_new_window
    sys = FakeSys.new(which: true)
    app, = build(sys: sys, worktrees: [["foo", "b"]])
    assert_equal 0, app.run(["zed", "foo"])
    assert_equal [["zed", "-n", "#{WT_BASE}/foo"]], @execs
  end

  def test_zed_missing_cli_errors
    sys = FakeSys.new(which: false)
    app, = build(sys: sys)
    assert_equal 1, app.run(["zed"])
    assert_match(/'zed' CLI not found/, @err.string)
    assert_empty @execs
  end

  def test_ls_empty
    app, = build
    assert_equal 0, app.run(["ls"])
    assert_match(/No worktrees/, @out.string)
  end

  def test_ls_lists_with_current_marker
    app, = build(worktrees: [["foo", "feature/x"]], pwd: "#{WT_BASE}/foo")
    assert_equal 0, app.run(["ls"])
    assert_match(/\* foo\s+feature\/x/, @out.string)
  end

  def test_ls_excludes_orphaned_directories
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[foo orphan] })
    app, = build(sys: sys, worktrees: [["foo", "feature/x"]])
    assert_equal 0, app.run(["ls"])
    assert_match(/foo/, @out.string)
    refute_match(/orphan/, @out.string)
  end

  def test_ls_excludes_phantom_worktrees
    app, = build(worktrees: [["foo", "feature/x"], ["phantom", "gone", "gitdir missing"]])
    assert_equal 0, app.run(["ls"])
    assert_match(/foo/, @out.string)
    refute_match(/phantom/, @out.string)
  end

  def test_cd_ignores_phantom_worktree
    app, = build(worktrees: [["phantom", "gone", "gitdir missing"]])
    assert_equal 1, app.run(["cd", "phantom"])
    assert_empty @cd
    assert_match(/No worktree matching: phantom/, @err.string)
  end

  def test_status_shows_dirty_and_position
    captures = {
      "-C #{ROOT} rev-parse --abbrev-ref HEAD" => ["main\n", true],
      "-C #{WT_BASE}/foo status --porcelain" => [" M a.rb\n", true],
      "-C #{WT_BASE}/foo rev-list --left-right --count main...feature/x" => ["1\t2\n", true]
    }
    app, = build(git: FakeGit.new(captures: captures), worktrees: [["foo", "feature/x"]])
    assert_equal 0, app.run(["status"])
    assert_match(/foo/, @out.string)
    assert_match(/\[dirty\]/, @out.string)
    assert_match(/↑2 ↓1/, @out.string)
  end

  def test_bare_name_cds_into_a_matching_worktree
    app, = build(worktrees: [["foo", "b"]])
    assert_equal 0, app.run(["foo"])
    assert_equal ["#{WT_BASE}/foo"], @cd
  end

  def test_bare_name_fuzzy_matches_like_cd
    app, = build(worktrees: [["foobar", "b"], ["other", "b"]])
    assert_equal 0, app.run(["foo"])
    assert_equal ["#{WT_BASE}/foobar"], @cd
  end

  def test_bare_name_with_no_match_errors_like_cd
    app, = build(worktrees: [["alpha", "b"]])
    assert_equal 1, app.run(["zzz"])
    assert_empty @cd
    assert_match(/No worktree matching: zzz/, @err.string)
  end

  def test_no_args_prints_usage
    app, = build
    assert_equal 1, app.run([])
    assert_match(/Usage: gwt/, @out.string)
  end

  def test_help_prints_usage_with_zero_exit
    ["help", "-h", "--help"].each do |flag|
      app, = build
      assert_equal 0, app.run([flag])
      assert_match(/Usage: gwt/, @out.string)
    end
  end

  def test_add_honours_custom_worktree_subdir
    app, git, = build(worktree_subdir: "worktrees")
    app.run(["add", "feature/x"])
    assert_includes git.runs, ["worktree", "add", "/repo/worktrees/feature+x", "feature/x"]
    assert_equal ["/repo/worktrees/feature+x"], @cd
  end

  def test_cd_resolves_under_custom_worktree_subdir
    git = FakeGit.new(captures: {
                        "worktree list --porcelain" =>
                          ["worktree /repo\nbranch refs/heads/main\n\nworktree /repo/wt/foo\nbranch refs/heads/b\n\n", true]
                      })
    app, = build(git: git, worktree_subdir: "wt")
    assert_equal 0, app.run(["cd", "foo"])
    assert_equal ["/repo/wt/foo"], @cd
  end

  def test_not_in_git_repo_errors
    git = FakeGit.new(captures: { "worktree list --porcelain" => ["", false] })
    app, = build(git: git)
    assert_equal 1, app.run(["ls"])
    assert_match(/Not in a git repo/, @err.string)
  end

  def test_worktree_list_retried_once_on_transient_failure
    flaky = Class.new(FakeGit) do
      attr_reader :list_calls
      def capture(*args, **kw)
        if args[0] == "worktree" && args[1] == "list"
          @list_calls = (@list_calls || 0) + 1
          return ["", false] if @list_calls == 1
        end
        super
      end
    end.new
    app, = build(git: flaky)
    assert_equal 0, app.run(["ls"])
    assert_equal 2, flaky.list_calls
  end

  def test_cp_force_copies_root_path_into_all_worktrees
    sys = FakeSys.new(exists: ["#{ROOT}/.env"])
    app, _, sys = build(sys: sys, worktrees: [["foo", "b"], ["bar", "b"]], confirm: ->(_) { false })
    assert_equal 0, app.run(["cp", "-f", ".env"])
    assert_includes sys.copies, ["#{ROOT}/.env", "#{WT_BASE}/foo/.env"]
    assert_includes sys.copies, ["#{ROOT}/.env", "#{WT_BASE}/bar/.env"]
  end

  def test_cp_confirmed_copies_into_all_worktrees
    sys = FakeSys.new(exists: ["#{ROOT}/.env"])
    app, _, sys = build(sys: sys, worktrees: [["foo", "b"]], confirm: ->(_) { true })
    assert_equal 0, app.run(["cp", ".env"])
    assert_includes sys.copies, ["#{ROOT}/.env", "#{WT_BASE}/foo/.env"]
  end

  def test_cp_declined_copies_nothing
    sys = FakeSys.new(exists: ["#{ROOT}/.env"])
    app, _, sys = build(sys: sys, worktrees: [["foo", "b"]], confirm: ->(_) { false })
    assert_equal 1, app.run(["cp", ".env"])
    assert_empty sys.copies
  end

  def test_cp_preserves_nested_path_under_each_worktree
    sys = FakeSys.new(exists: ["#{ROOT}/.claude/settings.local.json"])
    app, _, sys = build(sys: sys, worktrees: [["foo", "b"]])
    assert_equal 0, app.run(["cp", "-f", ".claude/settings.local.json"])
    assert_includes sys.copies,
                    ["#{ROOT}/.claude/settings.local.json", "#{WT_BASE}/foo/.claude/settings.local.json"]
  end

  def test_cp_missing_source_errors
    app, = build(worktrees: [["foo", "b"]])
    assert_equal 1, app.run(["cp", "nope.txt"])
    assert_match(/No such file or directory under root: nope.txt/, @err.string)
  end

  def test_cp_no_worktrees_reports_and_copies_nothing
    sys = FakeSys.new(exists: ["#{ROOT}/.env"])
    app, _, sys = build(sys: sys)
    assert_equal 0, app.run(["cp", "-f", ".env"])
    assert_match(/No worktrees/, @out.string)
    assert_empty sys.copies
  end

  def test_cp_without_path_errors
    app, = build
    assert_equal 1, app.run(["cp"])
    assert_match(/Usage: gwt cp/, @err.string)
  end

  def test_prune_removes_confirmed_orphans_only
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[foo orphan] })
    app, _, sys = build(sys: sys, worktrees: [["foo", "b"]], confirm: ->(_) { true })
    assert_equal 0, app.run(["prune"])
    assert_includes sys.removes, "#{WT_BASE}/orphan"
    refute_includes sys.removes, "#{WT_BASE}/foo"
  end

  def test_prune_declined_removes_nothing
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[orphan] })
    app, _, sys = build(sys: sys, worktrees: [], confirm: ->(_) { false })
    assert_equal 0, app.run(["prune"])
    assert_empty sys.removes
  end

  def test_prune_force_skips_confirmation
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[orphan] })
    app, _, sys = build(sys: sys, worktrees: [], confirm: ->(_) { flunk "should not prompt with -f" })
    assert_equal 0, app.run(["prune", "-f"])
    assert_includes sys.removes, "#{WT_BASE}/orphan"
  end

  def test_prune_reports_when_nothing_to_prune
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[foo] })
    app, git, sys = build(sys: sys, worktrees: [["foo", "b"]])
    assert_equal 0, app.run(["prune"])
    assert_match(/Nothing to prune/, @out.string)
    assert_empty sys.removes
    assert_empty git.runs
  end

  def test_prune_clears_phantom_git_registrations
    app, git, = build(worktrees: [["phantom", "gone", "gitdir missing"]])
    assert_equal 0, app.run(["prune"])
    assert_includes git.runs, ["worktree", "prune"]
    assert_match(/cleared stale git registration for phantom/, @out.string)
  end
end

class GwtSystemCopyTest < Minitest::Test
  def setup
    @sys = Gwt::System.new
    @dir = Dir.mktmpdir("gwt-copy")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_copy_into_materialises_a_symlink_as_a_real_file
    File.write("#{@dir}/target.txt", "canonical contents")
    File.symlink("target.txt", "#{@dir}/link.txt")

    @sys.copy_into("#{@dir}/link.txt", "#{@dir}/out/link.txt")

    refute File.symlink?("#{@dir}/out/link.txt")
    assert_equal "canonical contents", File.read("#{@dir}/out/link.txt")
  end

  def test_copy_into_materialises_a_symlink_with_an_unreachable_relative_target
    FileUtils.mkdir_p("#{@dir}/canon")
    File.write("#{@dir}/canon/note.md", "per-checkout overrides")
    File.symlink("../canon/note.md", "#{@dir}/src/note.md".tap { |p| FileUtils.mkdir_p(File.dirname(p)) })

    @sys.copy_into("#{@dir}/src/note.md", "#{@dir}/deep/nested/note.md")

    refute File.symlink?("#{@dir}/deep/nested/note.md")
    assert_equal "per-checkout overrides", File.read("#{@dir}/deep/nested/note.md")
  end

  def test_copy_into_copies_a_whole_directory_tree
    FileUtils.mkdir_p("#{@dir}/bundle/gems")
    File.write("#{@dir}/bundle/config", "BUNDLE_PATH: .bundle")
    File.write("#{@dir}/bundle/gems/foo.rb", "module Foo; end")

    @sys.copy_into("#{@dir}/bundle", "#{@dir}/wt/.bundle")

    assert_equal "BUNDLE_PATH: .bundle", File.read("#{@dir}/wt/.bundle/config")
    assert_equal "module Foo; end", File.read("#{@dir}/wt/.bundle/gems/foo.rb")
  end
end
