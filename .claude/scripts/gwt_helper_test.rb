#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
ScriptTest.load_script("../../bin/gwt-helper")

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

    def capture(*args)
      @captures.fetch(args.join(" "), ["", true])
    end

    def run(*args)
      @runs << args
      @run_ok
    end
  end

  class FakeSys
    attr_reader :copies

    def initialize(dirs: [], children: {}, which: true)
      @dirs = dirs
      @children = children
      @which = which
      @copies = []
    end

    def dir?(path) = @dirs.include?(path)
    def children(path) = @children.fetch(path, [])
    def empty_dir?(path) = children(path).empty?
    def which?(_cmd) = @which
    def copy_into(src, dst) = @copies << [src, dst]
  end

  def build(git: FakeGit.new, sys: FakeSys.new, pwd: ROOT, confirm: ->(_) { true }, worktree_subdir: ".claude/worktrees")
    @out = StringIO.new
    @err = StringIO.new
    @cd = []
    @execs = []
    git_with_root = with_root(git)
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

  # Every run resolves the main root first; wrap the fake so that capture is
  # pre-seeded without each test repeating it.
  def with_root(git)
    git.instance_variable_get(:@captures)["worktree list --porcelain"] ||=
      ["worktree /repo\n", true]
    git
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

  def test_add_on_existing_worktree_cds_without_recreating
    sys = FakeSys.new(dirs: ["/repo/.claude/worktrees/feature+x"])
    app, git, = build(sys: sys)
    status = app.run(["add", "feature/x"])
    assert_equal 0, status
    assert_empty git.runs
    assert_equal ["/repo/.claude/worktrees/feature+x"], @cd
    assert_match(/already exists/, @out.string)
  end

  def test_add_without_branch_errors
    app, = build
    assert_equal 1, app.run(["add"])
    assert_match(/Usage: gwt add/, @err.string)
  end

  def test_cd_exact_match
    sys = FakeSys.new(dirs: [WT_BASE, "#{WT_BASE}/foo"])
    app, = build(sys: sys)
    assert_equal 0, app.run(["cd", "foo"])
    assert_equal ["#{WT_BASE}/foo"], @cd
  end

  def test_cd_fuzzy_unique_match
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[foobar other] })
    app, = build(sys: sys)
    assert_equal 0, app.run(["cd", "foo"])
    assert_equal ["#{WT_BASE}/foobar"], @cd
  end

  def test_cd_ambiguous_match_errors
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[foo-a foo-b] })
    app, = build(sys: sys)
    assert_equal 1, app.run(["cd", "foo"])
    assert_empty @cd
    assert_match(/Multiple worktrees match 'foo'/, @err.string)
  end

  def test_cd_no_match_errors
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[alpha] })
    app, = build(sys: sys)
    assert_equal 1, app.run(["cd", "zzz"])
    assert_match(/No worktree matching: zzz/, @err.string)
  end

  def test_path_echoes_resolved_path
    sys = FakeSys.new(dirs: [WT_BASE, "#{WT_BASE}/foo"])
    app, = build(sys: sys)
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
    sys = FakeSys.new(dirs: ["#{WT_BASE}/foo"])
    app, git, = build(sys: sys, confirm: ->(_) { false })
    assert_equal 1, app.run(["rm", "foo"])
    assert_empty git.runs
    assert_empty @cd
  end

  def test_rm_confirmed_removes_and_cds_out_when_inside
    sys = FakeSys.new(dirs: ["#{WT_BASE}/foo"])
    app, git, = build(sys: sys, pwd: "#{WT_BASE}/foo/lib", confirm: ->(_) { true })
    assert_equal 0, app.run(["rm", "foo"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo"]
    assert_equal [ROOT], @cd
  end

  def test_rm_confirmed_no_cd_when_outside
    sys = FakeSys.new(dirs: ["#{WT_BASE}/foo"])
    app, = build(sys: sys, pwd: "/repo/src", confirm: ->(_) { true })
    app.run(["rm", "foo"])
    assert_empty @cd
  end

  def test_rm_missing_worktree_errors
    app, = build
    assert_equal 1, app.run(["rm", "nope"])
    assert_match(/No worktree: nope/, @err.string)
  end

  def test_zed_named_execs_in_new_window
    sys = FakeSys.new(dirs: [WT_BASE, "#{WT_BASE}/foo"], which: true)
    app, = build(sys: sys)
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
    git = FakeGit.new(captures: {
                        "-C #{WT_BASE}/foo rev-parse --abbrev-ref HEAD" => ["feature/x\n", true]
                      })
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[foo] })
    app, = build(git: git, sys: sys, pwd: "#{WT_BASE}/foo")
    assert_equal 0, app.run(["ls"])
    assert_match(/\* foo\s+feature\/x/, @out.string)
  end

  def test_status_shows_dirty_and_position
    captures = {
      "-C #{ROOT} rev-parse --abbrev-ref HEAD" => ["main\n", true],
      "-C #{WT_BASE}/foo rev-parse --abbrev-ref HEAD" => ["feature/x\n", true],
      "-C #{WT_BASE}/foo status --porcelain" => [" M a.rb\n", true],
      "-C #{WT_BASE}/foo rev-list --left-right --count main...feature/x" => ["1\t2\n", true]
    }
    sys = FakeSys.new(dirs: [WT_BASE], children: { WT_BASE => %w[foo] })
    app, = build(git: FakeGit.new(captures: captures), sys: sys)
    assert_equal 0, app.run(["status"])
    assert_match(/foo/, @out.string)
    assert_match(/\[dirty\]/, @out.string)
    assert_match(/↑2 ↓1/, @out.string)
  end

  def test_unknown_command_prints_usage
    app, = build
    assert_equal 1, app.run(["bogus"])
    assert_match(/Usage: gwt/, @out.string)
  end

  def test_add_honours_custom_worktree_subdir
    app, git, = build(worktree_subdir: "worktrees")
    app.run(["add", "feature/x"])
    assert_includes git.runs, ["worktree", "add", "/repo/worktrees/feature+x", "feature/x"]
    assert_equal ["/repo/worktrees/feature+x"], @cd
  end

  def test_cd_resolves_under_custom_worktree_subdir
    sys = FakeSys.new(dirs: ["/repo/wt", "/repo/wt/foo"])
    app, = build(sys: sys, worktree_subdir: "wt")
    assert_equal 0, app.run(["cd", "foo"])
    assert_equal ["/repo/wt/foo"], @cd
  end

  def test_not_in_git_repo_errors
    git = FakeGit.new(captures: { "worktree list --porcelain" => ["", false] })
    app, = build(git: git)
    assert_equal 1, app.run(["ls"])
    assert_match(/Not in a git repo/, @err.string)
  end
end
