# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
ScriptTest.load_script("../bin/plistgen")

class PlistgenPureTest < Minitest::Test
  def test_job_spec_derives_script_and_log_from_name
    spec = Plistgen.job_spec("word-study", {}, {}, "com.sebjacobs")
    assert_equal "com.sebjacobs.word-study", spec["label"]
    assert_equal "scripts/word_study_tick.sh", spec["script"]
    assert_equal "log/word_study_drain.log", spec["log"]
    assert_equal Plistgen::DEFAULT_INTERVAL, spec["interval"]
    assert_equal Plistgen::DEFAULT_PATH, spec["path"]
    assert_empty spec["env"]
  end

  def test_job_spec_overrides_win_over_convention
    overrides = { "script" => "bin/custom.sh", "log" => "log/x.log", "interval" => 60 }
    spec = Plistgen.job_spec("odd-one", overrides, {}, "com.sebjacobs")
    assert_equal "bin/custom.sh", spec["script"]
    assert_equal "log/x.log", spec["log"]
    assert_equal 60, spec["interval"]
  end

  def test_job_spec_appends_suffix_to_label_only
    spec = Plistgen.job_spec("word-study", {}, { "suffix" => "-drain" }, "com.sebjacobs")
    assert_equal "com.sebjacobs.word-study-drain", spec["label"]
    assert_equal "scripts/word_study_tick.sh", spec["script"]
    assert_equal "log/word_study_drain.log", spec["log"]
  end

  def test_job_spec_merges_default_and_override_env
    defaults = { "env" => { "SHARED" => "1" } }
    overrides = { "env" => { "PYTHONWARNINGS" => "ignore::DeprecationWarning" } }
    spec = Plistgen.job_spec("dialogue-audio", overrides, defaults, "com.sebjacobs")
    assert_equal({ "SHARED" => "1", "PYTHONWARNINGS" => "ignore::DeprecationWarning" }, spec["env"])
  end

  def test_job_spec_interval_falls_back_to_manifest_default
    spec = Plistgen.job_spec("x", {}, { "interval" => 900 }, "com.sebjacobs")
    assert_equal 900, spec["interval"]
  end

  def test_specs_preserves_declaration_order
    manifest = { "jobs" => { "a" => {}, "b" => {}, "c" => nil } }
    labels = Plistgen.specs(manifest, "com.sebjacobs").map { |s| s["label"] }
    assert_equal %w[com.sebjacobs.a com.sebjacobs.b com.sebjacobs.c], labels
  end

  def test_specs_empty_when_no_jobs
    assert_empty Plistgen.specs({}, "com.sebjacobs")
  end

  def test_prefix_of_defaults_when_absent
    assert_equal "com.sebjacobs", Plistgen.prefix_of({})
    assert_equal "com.example", Plistgen.prefix_of({ "prefix" => "com.example" })
  end

  def test_render_resolves_paths_against_root
    spec = Plistgen.job_spec("word-study", {}, {}, "com.sebjacobs")
    xml = Plistgen.render(spec, "/Users/me/proj")

    assert_includes xml, "<string>com.sebjacobs.word-study</string>"
    assert_includes xml, "<string>/Users/me/proj/scripts/word_study_tick.sh</string>"
    assert_includes xml, "<key>WorkingDirectory</key>\n  <string>/Users/me/proj</string>"
    assert_includes xml, "<string>/Users/me/proj/log/word_study_drain.log</string>"
    assert_includes xml, "<integer>300</integer>"
  end

  def test_render_puts_path_first_then_extra_env_in_order
    spec = Plistgen.job_spec("dialogue-audio",
                             { "env" => { "PYTHONWARNINGS" => "ignore::DeprecationWarning" } },
                             {}, "com.sebjacobs")
    xml = Plistgen.render(spec, "/root")
    path_idx = xml.index("<key>PATH</key>")
    warn_idx = xml.index("<key>PYTHONWARNINGS</key>")
    refute_nil path_idx
    refute_nil warn_idx
    assert path_idx < warn_idx, "PATH should render before extra env vars"
    assert_includes xml, "<string>ignore::DeprecationWarning</string>"
  end

  def test_render_is_valid_parseable_plist
    skip "plutil unavailable" unless system("which plutil > /dev/null 2>&1")

    spec = Plistgen.job_spec("word-study", {}, {}, "com.sebjacobs")
    require "tempfile"
    Tempfile.create(["gen", ".plist"]) do |f|
      f.write(Plistgen.render(spec, "/root"))
      f.flush
      assert system("plutil", "-lint", f.path, out: File::NULL, err: File::NULL),
             "generated plist should pass plutil -lint"
    end
  end

  def test_calendar_entries_are_the_cross_product_of_weekdays_and_times
    entries = Plistgen.calendar_entries({ "weekdays" => [1, 2], "times" => ["08:00", "16:30"] })

    assert_equal 4, entries.length
    assert_equal({ "Weekday" => 1, "Hour" => 8, "Minute" => 0 }, entries.first)
    assert_equal({ "Weekday" => 2, "Hour" => 16, "Minute" => 30 }, entries.last)
  end

  def test_calendar_entries_omit_weekday_when_none_given
    entries = Plistgen.calendar_entries({ "times" => ["09:05"] })

    assert_equal [{ "Hour" => 9, "Minute" => 5 }], entries
  end

  def test_render_emits_a_calendar_array_instead_of_an_interval
    spec = Plistgen.job_spec("uk-refresh",
                             { "calendar" => { "weekdays" => [1, 2, 3, 4, 5], "times" => ["08:00", "12:30", "16:30"] } },
                             {}, "com.sebjacobs")
    xml = Plistgen.render(spec, "/root")

    assert_includes xml, "<key>StartCalendarInterval</key>"
    refute_includes xml, "<key>StartInterval</key>"
    assert_equal 15, xml.scan("<key>Weekday</key>").length
  end

  # A calendar job that fired at load would run at login and at wake — the times
  # its schedule exists to exclude — whereas an interval drain wants a tick as
  # soon as it is installed.
  def test_render_runs_at_load_only_for_interval_jobs
    calendar = Plistgen.job_spec("uk-refresh", { "calendar" => { "times" => ["08:00"] } }, {}, "com.sebjacobs")
    interval = Plistgen.job_spec("word-study", {}, {}, "com.sebjacobs")

    assert_includes Plistgen.render(calendar, "/root"), "<key>RunAtLoad</key>\n  <false/>"
    assert_includes Plistgen.render(interval, "/root"), "<key>RunAtLoad</key>\n  <true/>"
  end

  def test_render_calendar_plist_is_valid_parseable_plist
    skip "plutil unavailable" unless system("which plutil > /dev/null 2>&1")

    spec = Plistgen.job_spec("uk-refresh",
                             { "calendar" => { "weekdays" => [1, 5], "times" => ["08:00", "16:30"] } },
                             {}, "com.sebjacobs")
    require "tempfile"
    Tempfile.create(["gen", ".plist"]) do |f|
      f.write(Plistgen.render(spec, "/root"))
      f.flush
      assert system("plutil", "-lint", f.path, out: File::NULL, err: File::NULL),
             "generated calendar plist should pass plutil -lint"
    end
  end

  # A service has no trigger: launchd starts it at load and restarts it on exit,
  # and the throttle is what stops a program that dies on startup from spinning.
  def test_render_keepalive_job_has_no_trigger_and_restarts_on_exit
    spec = Plistgen.job_spec("web", { "keepalive" => true, "script" => "scripts/web_serve.sh" }, {}, "com.sebjacobs")
    xml = Plistgen.render(spec, "/root")

    assert_includes xml, "<key>RunAtLoad</key>\n  <true/>"
    assert_includes xml, "<key>KeepAlive</key>\n  <true/>"
    assert_includes xml, "<key>ThrottleInterval</key>\n  <integer>10</integer>"
    assert_includes xml, "<string>/root/scripts/web_serve.sh</string>"
    refute_includes xml, "<key>StartInterval</key>"
    refute_includes xml, "<key>StartCalendarInterval</key>"
  end

  def test_render_keepalive_plist_is_valid_parseable_plist
    skip "plutil unavailable" unless system("which plutil > /dev/null 2>&1")

    spec = Plistgen.job_spec("web", { "keepalive" => true }, {}, "com.sebjacobs")
    require "tempfile"
    Tempfile.create(["gen", ".plist"]) do |f|
      f.write(Plistgen.render(spec, "/root"))
      f.flush
      assert system("plutil", "-lint", f.path, out: File::NULL, err: File::NULL),
             "generated keepalive plist should pass plutil -lint"
    end
  end

  def test_scheduled_jobs_do_not_keep_alive
    interval = Plistgen.job_spec("word-study", {}, {}, "com.sebjacobs")
    refute_includes Plistgen.render(interval, "/root"), "<key>KeepAlive</key>"
  end

  def test_xml_escape_escapes_markup_chars
    assert_equal "a &amp; b &lt;c&gt;", Plistgen.xml_escape("a & b <c>")
  end

  def test_filename_is_label_dot_plist
    spec = Plistgen.job_spec("word-study", {}, {}, "com.sebjacobs")
    assert_equal "com.sebjacobs.word-study.plist", Plistgen.filename(spec)
  end
end

class PlistgenAppTest < Minitest::Test
  MANIFEST = <<~YAML
    prefix: com.sebjacobs
    defaults:
      interval: 300
    jobs:
      word-study: {}
      dialogue-audio:
        env:
          PYTHONWARNINGS: ignore::DeprecationWarning
  YAML

  def setup
    @git = FakeGit.new
    @sys = FakeSystem.new
    @out = StringIO.new
    @err = StringIO.new
    @git.main = "/Users/me/proj"
    @git.worktree = "/Users/me/proj/.wt/branch"
    @sys.add_file("/Users/me/proj/scripts/launchd/drains.yml", MANIFEST)
  end

  def test_render_writes_a_plist_per_job_under_the_main_root
    assert_equal 0, build_app.run(["render"])

    ws = @sys.written["/Users/me/proj/scripts/launchd/generated/com.sebjacobs.word-study.plist"]
    da = @sys.written["/Users/me/proj/scripts/launchd/generated/com.sebjacobs.dialogue-audio.plist"]
    refute_nil ws
    refute_nil da
    assert_includes ws, "<string>/Users/me/proj</string>"
    assert_includes da, "<string>ignore::DeprecationWarning</string>"
    assert_includes @out.string, "rendered 2 agent(s) with root /Users/me/proj"
  end

  def test_render_defaults_to_main_root_even_from_a_worktree
    assert_equal 0, build_app.run(["render"])
    assert @sys.written.keys.all? { |k| k.start_with?("/Users/me/proj/scripts/launchd/generated") }
    refute @sys.written.keys.any? { |k| k.include?("/.wt/") }
  end

  def test_worktree_flag_renders_against_the_current_worktree
    @sys.add_file("/Users/me/proj/.wt/branch/scripts/launchd/drains.yml", MANIFEST)
    assert_equal 0, build_app.run(["render", "--worktree"])
    assert @sys.written.keys.all? { |k| k.start_with?("/Users/me/proj/.wt/branch") }
  end

  def test_explicit_root_wins
    @sys.add_file("/elsewhere/scripts/launchd/drains.yml", MANIFEST)
    assert_equal 0, build_app.run(["render", "--root", "/elsewhere"])
    assert @sys.written.keys.all? { |k| k.start_with?("/elsewhere") }
  end

  def test_out_flag_redirects_output_dir
    assert_equal 0, build_app.run(["render", "--out", "/tmp/plists"])
    assert @sys.written.keys.all? { |k| k.start_with?("/tmp/plists/") }
  end

  def test_render_filters_to_named_jobs
    assert_equal 0, build_app.run(["render", "word-study"])
    assert_equal 1, @sys.written.length
    assert @sys.written.keys.first.end_with?("com.sebjacobs.word-study.plist")
  end

  def test_render_accepts_full_label_as_job_name
    assert_equal 0, build_app.run(["render", "com.sebjacobs.dialogue-audio"])
    assert_equal 1, @sys.written.length
  end

  def test_render_errors_on_unknown_job
    assert_equal 1, build_app.run(["render", "nope"])
    assert_includes @err.string, "Unknown job: nope"
    assert_empty @sys.written
  end

  def test_render_errors_when_manifest_missing
    @sys = FakeSystem.new
    assert_equal 1, build_app.run(["render"])
    assert_includes @err.string, "No manifest at"
  end

  def test_render_errors_on_malformed_manifest
    @sys.add_file("/Users/me/proj/scripts/launchd/drains.yml", "jobs: [unterminated")
    assert_equal 1, build_app.run(["render"])
    assert_includes @err.string, "Malformed manifest"
  end

  def test_render_errors_outside_a_git_repo_without_root
    @git.main = nil
    assert_equal 1, build_app.run(["render"])
    assert_includes @err.string, "Not in a git repo"
  end

  def test_unknown_flag_errors
    assert_equal 1, build_app.run(["render", "--bogus"])
    assert_includes @err.string, "Unknown flag: --bogus"
  end

  def test_list_prints_each_job
    assert_equal 0, build_app.run(["list"])
    assert_includes @out.string, "com.sebjacobs.word-study"
    assert_includes @out.string, "scripts/dialogue_audio_tick.sh"
  end

  def test_help_returns_zero
    assert_equal 0, build_app.run(["help"])
    assert_includes @out.string, "Usage: plistgen"
  end

  def test_unknown_command_shows_usage_nonzero
    assert_equal 1, build_app.run(["frobnicate"])
    assert_includes @out.string, "Usage: plistgen"
  end

  private

  def build_app
    Plistgen::App.new(git: @git, sys: @sys, out: @out, err: @err, cwd: "/Users/me/proj/.wt/branch")
  end

  class FakeGit
    attr_accessor :main, :worktree

    def main_root(_cwd) = @main

    def worktree_root(_cwd) = @worktree
  end

  class FakeSystem
    attr_reader :written

    def initialize
      @files = {}
      @written = {}
    end

    def add_file(path, content) = @files[path] = content

    def read(path) = @files.fetch(path)

    def exist?(path) = @files.key?(path)

    def write(path, content) = @written[path] = content
  end
end
