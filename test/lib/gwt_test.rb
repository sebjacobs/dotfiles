#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
ScriptTest.load_script("../lib/gwt.rb")

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

  def test_parse_for_each_ref_maps_branch_to_time_and_divergence
    out = "feature/x|1782571757|2 4\nmain|1782722947|0 0\n"
    assert_equal(
      {
        "feature/x" => {time: 1782571757, ahead: 2, behind: 4},
        "main" => {time: 1782722947, ahead: 0, behind: 0}
      },
      Gwt.parse_for_each_ref(out)
    )
  end

  def test_parse_for_each_ref_treats_an_empty_ahead_behind_field_as_zero
    assert_equal({"orphan" => {time: 1782571757, ahead: 0, behind: 0}},
                 Gwt.parse_for_each_ref("orphan|1782571757|\n"))
  end

  def test_parse_for_each_ref_handles_empty_input
    assert_empty Gwt.parse_for_each_ref("")
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

  def test_format_time_renders_local_minute_precision
    ENV["TZ"] = "UTC"
    assert_equal "2026-06-28 04:09", Gwt.format_time(1782619757)
  ensure
    ENV.delete("TZ")
  end

  def test_current_dir_picks_the_longest_containing_path
    dirs = ["/repo", "/repo/.claude/worktrees/foo"]
    assert_equal "/repo/.claude/worktrees/foo", Gwt.current_dir("/repo/.claude/worktrees/foo/lib", dirs)
    assert_equal "/repo", Gwt.current_dir("/repo/lib", dirs)
  end

  def test_current_dir_ignores_a_name_prefix_sibling
    assert_nil Gwt.current_dir("/repo-x/lib", ["/repo"])
  end

  def test_current_dir_returns_nil_when_pwd_is_outside_every_dir
    assert_nil Gwt.current_dir("/elsewhere", ["/repo"])
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

class GwtClaudeHistoryTest < Minitest::Test
  PROJECTS = "/home/.claude/projects"

  # Minimal System double for the migrate_paths move/merge loop: entries are
  # keyed by directory path; a path "exists" iff it has an entries record.
  class FakeHistSys
    attr_reader :moves, :removes

    def initialize(entries) = (@entries = entries; @moves = []; @removes = [])
    def dir?(_path) = true
    def entries(path) = @entries.fetch(path, [])
    def exist?(path) = @entries.key?(path)
    def move(src, dst) = @moves << [src, dst]
    def remove(path) = @removes << path
  end

  def migrate_paths(entries, pairs)
    sys = FakeHistSys.new(entries)
    Gwt::ClaudeHistory.migrate_paths(
      sys: sys, home: "/home", pairs: pairs, out: StringIO.new, err: StringIO.new
    )
    sys
  end

  def test_migrate_paths_renames_each_pair_by_exact_name
    sys = migrate_paths(
      { PROJECTS => ["-p-cadence", "-p-cadence--claude-worktrees-foo"] },
      [["/p/cadence", "/p/notes"],
       ["/p/cadence/.claude/worktrees/foo", "/p/notes/.claude/worktrees/foo"]]
    )
    assert_includes sys.moves, ["#{PROJECTS}/-p-cadence", "#{PROJECTS}/-p-notes"]
    assert_includes sys.moves,
                    ["#{PROJECTS}/-p-cadence--claude-worktrees-foo", "#{PROJECTS}/-p-notes--claude-worktrees-foo"]
  end

  # The reason proj mv can't reuse the prefix sweep: a sibling project sharing a
  # name prefix must NOT be dragged along.
  def test_migrate_paths_leaves_a_prefix_sibling_untouched
    sys = migrate_paths(
      { PROJECTS => ["-p-cadence", "-p-cadence-extra"] },
      [["/p/cadence", "/p/notes"]]
    )
    assert_equal [["#{PROJECTS}/-p-cadence", "#{PROJECTS}/-p-notes"]], sys.moves
    refute(sys.moves.any? { |_src, dst| dst.include?("extra") })
  end

  def test_migrate_paths_skips_pairs_with_no_existing_history
    sys = migrate_paths({ PROJECTS => ["-p-cadence"] }, [["/p/never-logged", "/p/whatever"]])
    assert_empty sys.moves
  end

  def test_migrate_paths_merges_into_an_existing_destination
    sys = migrate_paths(
      { PROJECTS => ["-p-cadence"], "#{PROJECTS}/-p-notes" => [], "#{PROJECTS}/-p-cadence" => ["s1.jsonl"] },
      [["/p/cadence", "/p/notes"]]
    )
    assert_includes sys.moves, ["#{PROJECTS}/-p-cadence/s1.jsonl", "#{PROJECTS}/-p-notes/s1.jsonl"]
    assert_includes sys.removes, "#{PROJECTS}/-p-cadence"
  end

  def test_encode_replaces_every_slash_and_dot
    assert_equal "-Users-me-proj--claude-worktrees-foo",
                 Gwt::ClaudeHistory.encode("/Users/me/proj/.claude/worktrees/foo")
  end

  def test_encode_replaces_plus_and_other_non_alphanumerics
    assert_equal "-repo--claude-worktrees-feature-android-vocab-app",
                 Gwt::ClaudeHistory.encode("/repo/.claude/worktrees/feature+android-vocab-app")
  end

  def test_rehome_map_renames_the_exact_match
    names = ["-repo--claude-worktrees-foo", "-unrelated"]
    assert_equal(
      [["-repo--claude-worktrees-foo", "-repo--claude-worktrees-bar"]],
      Gwt::ClaudeHistory.rehome_map(names, "/repo/.claude/worktrees/foo", "/repo/.claude/worktrees/bar")
    )
  end

  def test_rehome_map_also_carries_nested_subdir_sessions
    names = ["-repo--claude-worktrees-foo", "-repo--claude-worktrees-foo-lib"]
    result = Gwt::ClaudeHistory.rehome_map(names, "/repo/.claude/worktrees/foo", "/repo/.claude/worktrees/bar")
    assert_includes result, ["-repo--claude-worktrees-foo", "-repo--claude-worktrees-bar"]
    assert_includes result, ["-repo--claude-worktrees-foo-lib", "-repo--claude-worktrees-bar-lib"]
  end

  def test_rehome_map_ignores_unrelated_entries
    names = ["-repo--claude-worktrees-other", "-elsewhere"]
    assert_empty Gwt::ClaudeHistory.rehome_map(names, "/repo/.claude/worktrees/foo", "/repo/.claude/worktrees/bar")
  end

  # The property proj mv leans on: a project move and every worktree under it
  # share the project's encoded path as a prefix, so one sweep carries them all.
  def test_rehome_map_sweeps_a_project_and_its_worktrees
    names = ["-Users-me-Tech-foo", "-Users-me-Tech-foo--claude-worktrees-wt1"]
    result = Gwt::ClaudeHistory.rehome_map(names, "/Users/me/Tech/foo", "/Users/me/Tech/bar")
    assert_includes result, ["-Users-me-Tech-foo", "-Users-me-Tech-bar"]
    assert_includes result, ["-Users-me-Tech-foo--claude-worktrees-wt1", "-Users-me-Tech-bar--claude-worktrees-wt1"]
  end
end

class GwtAppTest < Minitest::Test
  ROOT = "/repo"
  WT_BASE = "/repo/.claude/worktrees"

  # Records git invocations and replays canned captures keyed by joined argv.
  class FakeGit
    attr_reader :runs

    def initialize(captures: {}, run_ok: true, fail_runs: [])
      @captures = captures
      @run_ok = run_ok
      @fail_runs = fail_runs
      @runs = []
    end

    def capture(*args, **)
      @captures.fetch(args.join(" "), ["", true])
    end

    def run(*args)
      @runs << args
      return false if @fail_runs.any? { |prefix| args.first(prefix.length) == prefix }

      @run_ok
    end
  end

  # A FakeGit that gates every `status --porcelain` (the dirty check) on a
  # barrier, then reports the most that were ever in flight at once. Serial
  # execution can never raise that peak above one — each call would arrive, find
  # itself alone, and time out before the next began — so asserting the peak
  # equals the worktree count proves cmd_status fans the dirty checks out across
  # threads rather than walking them one by one.
  class DirtyCheckConcurrencyProbe < FakeGit
    attr_reader :peak_in_flight

    def initialize(expected:, **kwargs)
      super(**kwargs)
      @expected = expected
      @monitor = Mutex.new
      @all_arrived = ConditionVariable.new
      @arrived = 0
      @in_flight = 0
      @peak_in_flight = 0
    end

    def capture(*args, **)
      await_all_dirty_checks if dirty_check?(args)
      super
    end

    private

    def dirty_check?(args) = args.include?("status") && args.include?("--porcelain")

    def await_all_dirty_checks
      @monitor.synchronize do
        @arrived += 1
        @in_flight += 1
        @peak_in_flight = [@peak_in_flight, @in_flight].max
        @all_arrived.broadcast
        wait_until_all_arrived_or_timeout
        @in_flight -= 1
      end
    end

    # The release gate is @arrived, which only ever climbs — so a woken waiter
    # can't be sent back to sleep by a peer that has already finished and dropped
    # out of flight. Serial callers never lift @arrived past one before the
    # deadline, which is exactly what the peak assertion catches.
    def wait_until_all_arrived_or_timeout
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      while @arrived < @expected
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break if remaining <= 0

        @all_arrived.wait(@monitor, remaining)
      end
    end
  end

  class FakeSys
    attr_reader :copies, :removes, :moves

    def initialize(dirs: [], children: {}, which: true, exists: [], entries: {})
      @dirs = dirs
      @children = children
      @which = which
      @exists = exists
      @entries = entries
      @copies = []
      @removes = []
      @moves = []
    end

    def dir?(path) = @dirs.include?(path)
    def exist?(path) = @exists.include?(path) || @dirs.include?(path)
    def children(path) = @children.fetch(path, [])
    def entries(path) = @entries.fetch(path, [])
    def which?(_cmd) = @which
    def copy_into(src, dst) = @copies << [src, dst]
    def move(src, dst) = @moves << [src, dst]
    def remove(path) = @removes << path
  end

  HOME = "/home"

  def build(git: FakeGit.new, sys: FakeSys.new, pwd: ROOT, confirm: ->(_) { true },
            worktree_subdir: ".claude/worktrees", worktrees: [], home: HOME)
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
      worktree_subdir: worktree_subdir,
      home: home
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

  def test_add_with_dash_b_and_start_point_branches_off_it
    app, git, = build
    assert_equal 0, app.run(["add", "-b", "dogs:main"])
    assert_includes git.runs, ["worktree", "add", "-b", "dogs", "#{WT_BASE}/dogs", "main"]
    assert_equal ["#{WT_BASE}/dogs"], @cd
  end

  def test_add_start_point_names_the_worktree_after_the_new_branch_only
    app, git, = build
    app.run(["add", "-b", "spike/dogs:feature/cats"])
    assert_includes git.runs, ["worktree", "add", "-b", "spike/dogs", "#{WT_BASE}/spike+dogs", "feature/cats"]
  end

  def test_add_validates_only_the_new_branch_half_of_the_spec
    app, git, = build
    assert_equal 1, app.run(["add", "-b", "cd:main"])
    assert_match(/"cd" is a reserved gwt subcommand/, @err.string)
    assert_empty git.runs
  end

  def test_add_start_point_without_dash_b_errors_suggesting_dash_b
    app, git, = build
    assert_equal 1, app.run(["add", "dogs:main"])
    assert_match(/only applies with -b/, @err.string)
    assert_match(/gwt add -b dogs:main/, @err.string)
    assert_empty git.runs
  end

  def test_add_with_empty_start_point_errors
    app, git, = build
    assert_equal 1, app.run(["add", "-b", "dogs:"])
    assert_match(/Usage: gwt add/, @err.string)
    assert_empty git.runs
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

  PROJECTS = "#{HOME}/.claude/projects"
  FOO_HISTORY = "-repo--claude-worktrees-foo"
  BAR_HISTORY = "-repo--claude-worktrees-bar"

  def test_mv_moves_worktree_and_migrates_history_and_cds_when_inside
    sys = FakeSys.new(dirs: [PROJECTS], entries: { PROJECTS => [FOO_HISTORY] })
    app, git, sys = build(sys: sys, worktrees: [["foo", "b"]], pwd: "#{WT_BASE}/foo/lib")
    assert_equal 0, app.run(["mv", "foo", "bar"])
    assert_includes git.runs, ["worktree", "move", "#{WT_BASE}/foo", "#{WT_BASE}/bar"]
    assert_includes sys.moves, ["#{PROJECTS}/#{FOO_HISTORY}", "#{PROJECTS}/#{BAR_HISTORY}"]
    assert_equal ["#{WT_BASE}/bar"], @cd
  end

  def test_mv_does_not_cd_when_outside_the_worktree
    sys = FakeSys.new(dirs: [PROJECTS], entries: { PROJECTS => [] })
    app, = build(sys: sys, worktrees: [["foo", "b"]], pwd: "/repo/src")
    assert_equal 0, app.run(["mv", "foo", "bar"])
    assert_empty @cd
  end

  def test_mv_requires_confirmation
    app, git, = build(worktrees: [["foo", "b"]], confirm: ->(_) { false })
    assert_equal 1, app.run(["mv", "foo", "bar"])
    assert_empty git.runs
    assert_empty @cd
  end

  def test_mv_force_skips_confirmation
    sys = FakeSys.new(dirs: [PROJECTS], entries: { PROJECTS => [] })
    app, git, = build(sys: sys, worktrees: [["foo", "b"]], confirm: ->(_) { flunk "should not prompt with -f" })
    assert_equal 0, app.run(["mv", "-f", "foo", "bar"])
    assert_includes git.runs, ["worktree", "move", "#{WT_BASE}/foo", "#{WT_BASE}/bar"]
  end

  def test_mv_skips_history_migration_when_git_move_fails
    sys = FakeSys.new(dirs: [PROJECTS], entries: { PROJECTS => [FOO_HISTORY] })
    app, _, sys = build(git: FakeGit.new(run_ok: false), sys: sys, worktrees: [["foo", "b"]])
    assert_equal 1, app.run(["mv", "foo", "bar"])
    assert_empty sys.moves
    assert_empty @cd
  end

  def test_mv_merges_into_an_existing_history_dir
    sys = FakeSys.new(
      dirs: [PROJECTS], exists: ["#{PROJECTS}/#{BAR_HISTORY}"],
      entries: { PROJECTS => [FOO_HISTORY], "#{PROJECTS}/#{FOO_HISTORY}" => ["s1.jsonl"] }
    )
    app, _, sys = build(sys: sys, worktrees: [["foo", "b"]])
    assert_equal 0, app.run(["mv", "foo", "bar"])
    assert_includes sys.moves, ["#{PROJECTS}/#{FOO_HISTORY}/s1.jsonl", "#{PROJECTS}/#{BAR_HISTORY}/s1.jsonl"]
    assert_includes sys.removes, "#{PROJECTS}/#{FOO_HISTORY}"
  end

  def test_mv_requires_two_names
    app, git, = build(worktrees: [["foo", "b"]])
    assert_equal 1, app.run(["mv", "foo"])
    assert_match(/Usage: gwt mv/, @err.string)
    assert_empty git.runs
  end

  def test_mv_rejects_an_invalid_new_slug
    app, git, = build(worktrees: [["foo", "b"]])
    assert_equal 1, app.run(["mv", "foo", "bad/../x"])
    assert_match(/Invalid worktree name/, @err.string)
    assert_empty git.runs
  end

  def test_mv_rejects_a_new_name_colliding_with_a_subcommand
    app, git, = build(worktrees: [["foo", "b"]])
    assert_equal 1, app.run(["mv", "foo", "status"])
    assert_match(/reserved gwt subcommand/, @err.string)
    assert_empty git.runs
  end

  def test_mv_rejects_an_occupied_target
    app, git, = build(worktrees: [["foo", "b"], ["bar", "b"]])
    assert_equal 1, app.run(["mv", "foo", "bar"])
    assert_match(/already exists/, @err.string)
    assert_empty git.runs
  end

  def test_mv_errors_on_an_unknown_source
    app, git, = build(worktrees: [["foo", "b"]])
    assert_equal 1, app.run(["mv", "nope", "bar"])
    assert_match(/No worktree matching: nope/, @err.string)
    assert_empty git.runs
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

  def test_rm_delete_branch_removes_worktree_then_branch
    app, git, = build(worktrees: [["foo", "feature/foo"]], confirm: ->(_) { true })
    assert_equal 0, app.run(["rm", "-d", "foo"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo"]
    assert_includes git.runs, ["branch", "-d", "feature/foo"]
  end

  def test_rm_delete_branch_uses_actual_branch_not_dir_name
    app, git, = build(worktrees: [["renamed", "feature/original"]], confirm: ->(_) { true })
    assert_equal 0, app.run(["rm", "-d", "renamed"])
    assert_includes git.runs, ["branch", "-d", "feature/original"]
  end

  def test_rm_delete_branch_force_uses_capital_d
    app, git, = build(worktrees: [["foo", "feature/foo"]], confirm: ->(_) { true })
    assert_equal 0, app.run(["rm", "-D", "foo"])
    assert_includes git.runs, ["branch", "-D", "feature/foo"]
  end

  def test_rm_long_delete_branch_flags
    app, git, = build(worktrees: [["foo", "feature/foo"]], confirm: ->(_) { true })
    assert_equal 0, app.run(["rm", "--delete-branch", "foo"])
    assert_includes git.runs, ["branch", "-d", "feature/foo"]
  end

  def test_rm_bundled_force_and_delete_branch
    app, git, = build(worktrees: [["foo", "feature/foo"]], confirm: ->(_) { flunk "should not prompt with -f" })
    assert_equal 0, app.run(["rm", "-df", "foo"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo", "--force"]
    assert_includes git.runs, ["branch", "-d", "feature/foo"]
  end

  def test_rm_force_does_not_escalate_safe_branch_delete
    app, git, = build(worktrees: [["foo", "feature/foo"]], confirm: ->(_) { true })
    app.run(["rm", "-df", "foo"])
    assert_includes git.runs, ["branch", "-d", "feature/foo"]
    refute_includes git.runs, ["branch", "-D", "feature/foo"]
  end

  def test_rm_without_delete_flag_leaves_branch
    app, git, = build(worktrees: [["foo", "feature/foo"]], confirm: ->(_) { true })
    app.run(["rm", "foo"])
    assert_empty git.runs.select { |r| r.first == "branch" }
  end

  def test_rm_skips_branch_delete_when_worktree_removal_fails
    git = FakeGit.new(fail_runs: [["worktree", "remove"]])
    app, git, = build(git: git, worktrees: [["foo", "feature/foo"]], confirm: ->(_) { true })
    assert_equal 1, app.run(["rm", "-d", "foo"])
    assert_empty git.runs.select { |r| r.first == "branch" }
  end

  def test_rm_returns_nonzero_when_branch_delete_fails
    git = FakeGit.new(fail_runs: [["branch"]])
    app, git, = build(git: git, worktrees: [["foo", "feature/foo"]], confirm: ->(_) { true })
    assert_equal 1, app.run(["rm", "-d", "foo"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo"]
  end

  def test_rm_delete_branch_on_detached_worktree_warns
    app, git, = build(worktrees: [["foo", nil]], confirm: ->(_) { true })
    assert_equal 1, app.run(["rm", "-d", "foo"])
    assert_includes git.runs, ["worktree", "remove", "#{WT_BASE}/foo"]
    assert_empty git.runs.select { |r| r.first == "branch" }
    assert_match(/no branch to delete/, @err.string)
  end

  def test_rm_delete_branch_on_orphan_warns_and_returns_nonzero
    sys = FakeSys.new(dirs: ["#{WT_BASE}/orphan"])
    app, git, sys = build(sys: sys, worktrees: [], confirm: ->(_) { true })
    assert_equal 1, app.run(["rm", "-d", "orphan"])
    assert_includes sys.removes, "#{WT_BASE}/orphan"
    assert_empty git.runs.select { |r| r.first == "branch" }
    assert_match(/untracked by git/, @err.string)
  end

  def test_rm_unknown_flag_errors
    app, = build(worktrees: [["foo", "feature/foo"]])
    assert_equal 1, app.run(["rm", "-x", "foo"])
    assert_match(/Usage: gwt rm/, @err.string)
  end

  def test_zed_named_execs_in_new_window
    sys = FakeSys.new(which: true)
    app, = build(sys: sys, worktrees: [["foo", "b"]])
    assert_equal 0, app.run(["zed", "foo"])
    assert_equal [["zed", "-n", "#{WT_BASE}/foo"]], @execs
  end

  def test_zed_dot_opens_current_worktree
    git = FakeGit.new(captures: { "rev-parse --show-toplevel" => ["#{WT_BASE}/foo\n", true] })
    sys = FakeSys.new(which: true)
    app, = build(git: git, sys: sys, worktrees: [["foo", "b"]])
    assert_equal 0, app.run(["zed", "."])
    assert_equal [["zed", "-n", "#{WT_BASE}/foo"]], @execs
  end

  def test_zed_missing_cli_errors
    sys = FakeSys.new(which: false)
    app, = build(sys: sys)
    assert_equal 1, app.run(["zed"])
    assert_match(/'zed' CLI not found/, @err.string)
    assert_empty @execs
  end

  def test_ls_with_no_worktrees_still_lists_the_root
    app, = build
    assert_equal 0, app.run(["ls"])
    assert_match(/repo \(root\)\s+main/, @out.string)
  end

  def test_ls_lists_the_root_alongside_worktrees
    app, = build(worktrees: [["foo", "feature/x"]], pwd: ROOT)
    assert_equal 0, app.run(["ls"])
    assert_match(/\* repo \(root\)\s+main/, @out.string)
    assert_match(/  foo\s+feature\/x/, @out.string)
  end

  def test_ls_marks_only_the_worktree_not_its_enclosing_root
    app, = build(worktrees: [["foo", "feature/x"]], pwd: "#{WT_BASE}/foo")
    assert_equal 0, app.run(["ls"])
    assert_match(/\* foo\s+feature\/x/, @out.string)
    assert_match(/  repo \(root\)\s+main/, @out.string)
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

  FOR_EACH_REF = "-C #{ROOT} for-each-ref " \
                 "--format=%(refname:short)|%(committerdate:unix)|%(ahead-behind:main) refs/heads/"

  def test_status_shows_dirty_position_and_timestamp
    captures = {
      FOR_EACH_REF => ["feature/x|1782571757|2 1\nmain|1782509451|0 0\n", true],
      "-C #{WT_BASE}/foo status --porcelain" => [" M a.rb\n", true]
    }
    app, = build(git: FakeGit.new(captures: captures), worktrees: [["foo", "feature/x"]])
    assert_equal 0, app.run(["status"])
    assert_match(/foo/, @out.string)
    assert_match(/\[dirty\]/, @out.string)
    assert_match(/↑2 ↓1/, @out.string)
    assert_match(/\(last: #{Regexp.escape(Gwt.format_time(1782571757))}\)/, @out.string)
  end

  def test_status_orders_newest_first_and_includes_the_root
    captures = {
      FOR_EACH_REF => ["feature/x|1782571757|0 0\nmain|1782509451|0 0\n", true]
    }
    app, = build(git: FakeGit.new(captures: captures), worktrees: [["foo", "feature/x"]])
    assert_equal 0, app.run(["status"])
    lines = @out.string.lines.map(&:chomp).reject(&:empty?)
    assert_match(/foo/, lines[0])
    assert_match(/repo \(root\)\s+main/, lines[1])
  end

  def test_status_runs_the_per_worktree_dirty_checks_concurrently
    worktrees = [["a", "fa"], ["b", "fb"], ["c", "fc"]]
    listed = worktrees.length + 1
    refs = "main|1|0 0\nfa|2|0 0\nfb|3|0 0\nfc|4|0 0\n"
    git = DirtyCheckConcurrencyProbe.new(expected: listed, captures: { FOR_EACH_REF => [refs, true] })
    app, = build(git: git, worktrees: worktrees)
    assert_equal 0, app.run(["status"])
    assert_equal listed, git.peak_in_flight
  end

  def test_status_falls_back_to_per_tree_log_for_a_detached_worktree
    captures = {
      FOR_EACH_REF => ["main|1782509451|0 0\n", true],
      "-C #{WT_BASE}/foo log -1 --format=%ct" => ["1782571757\n", true]
    }
    app, = build(git: FakeGit.new(captures: captures), worktrees: [["foo", nil]])
    assert_equal 0, app.run(["status"])
    lines = @out.string.lines.map(&:chomp).reject(&:empty?)
    assert_match(/foo\s+\(detached\)/, lines[0])
    assert_match(/\(last: #{Regexp.escape(Gwt.format_time(1782571757))}\)/, lines[0])
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

  def test_no_args_runs_status
    captures = { FOR_EACH_REF => ["main|1782509451|0 0\n", true] }
    app, = build(git: FakeGit.new(captures: captures))
    assert_equal 0, app.run([])
    assert_match(/repo \(root\)\s+main/, @out.string)
    refute_match(/Usage: gwt/, @out.string)
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

  def test_root_override_resolves_worktree_of_another_repo
    porc = "worktree /other\nbranch refs/heads/main\n\n" \
           "worktree /other/.claude/worktrees/foo\nbranch refs/heads/feature/x\n\n"
    git = FakeGit.new(captures: { "-C /other worktree list --porcelain" => [porc, true] })
    out = StringIO.new
    err = StringIO.new
    cd = []
    app = Gwt::App.new(
      git: git, sys: FakeSys.new, out: out, err: err,
      cd: ->(p) { cd << p }, confirm: ->(_) { false }, pwd: "/elsewhere",
      exec: ->(*) {}, worktree_subdir: ".claude/worktrees", root_override: "/other"
    )
    assert_equal 0, app.run(["cd", "foo"])
    assert_equal ["/other/.claude/worktrees/foo"], cd
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
