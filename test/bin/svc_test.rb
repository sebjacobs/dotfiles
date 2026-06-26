# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
ScriptTest.load_script("../bin/svc")

class SvcPureTest < Minitest::Test
  def test_schedule_of_weekday_calendar
    plist = { "StartCalendarInterval" => { "Weekday" => 1, "Hour" => 9, "Minute" => 5 } }
    assert_equal "Mon 09:05 (calendar)", Svc.schedule_of(plist)
  end

  def test_schedule_of_calendar_without_weekday
    plist = { "StartCalendarInterval" => { "Hour" => 7, "Minute" => 0 } }
    assert_equal "07:00 (calendar)", Svc.schedule_of(plist)
  end

  def test_schedule_of_calendar_defaults_missing_hour_and_minute_to_zero
    assert_equal "00:00 (calendar)", Svc.schedule_of({ "StartCalendarInterval" => {} })
  end

  def test_schedule_of_array_calendar_is_summarised
    plist = { "StartCalendarInterval" => [{ "Hour" => 1 }, { "Hour" => 13 }] }
    assert_equal "multiple (calendar)", Svc.schedule_of(plist)
  end

  def test_schedule_of_interval
    assert_equal "every 3600s", Svc.schedule_of({ "StartInterval" => 3600 })
  end

  def test_schedule_of_run_at_load
    assert_equal "at login", Svc.schedule_of({ "RunAtLoad" => true })
  end

  def test_schedule_of_falls_back_to_on_demand
    assert_equal "on demand", Svc.schedule_of({})
  end

  def test_disabled_matches_disabled_form
    output = %("com.sebjacobs.brewup" => disabled\n)
    assert Svc.disabled?(output, "com.sebjacobs.brewup")
  end

  def test_disabled_matches_true_form
    output = %("com.sebjacobs.brewup" => true\n)
    assert Svc.disabled?(output, "com.sebjacobs.brewup")
  end

  def test_disabled_false_when_enabled
    output = %("com.sebjacobs.brewup" => false\n)
    refute Svc.disabled?(output, "com.sebjacobs.brewup")
  end

  def test_disabled_false_when_absent
    refute Svc.disabled?("", "com.sebjacobs.brewup")
  end

  def test_exit_status_reads_status_column
    list = "12\t0\tcom.sebjacobs.brewup\n-\t1\tcom.sebjacobs.reap\n"
    assert_equal "0", Svc.exit_status(list, "com.sebjacobs.brewup")
    assert_equal "1", Svc.exit_status(list, "com.sebjacobs.reap")
  end

  def test_exit_status_nil_when_label_absent
    assert_nil Svc.exit_status("12\t0\tcom.other.thing\n", "com.sebjacobs.brewup")
  end

  def test_fuzzy_match_prefers_exact_then_prefix_then_substring
    names = %w[brewup brew-extra ruby-lsp-reap]
    assert_equal %w[brewup], Svc.fuzzy_match(names, "brewup")
    assert_equal %w[brewup brew-extra], Svc.fuzzy_match(names, "brew")
    assert_equal %w[ruby-lsp-reap], Svc.fuzzy_match(names, "reap")
  end

  def test_fuzzy_match_empty_when_nothing_matches
    assert_empty Svc.fuzzy_match(%w[brewup reap], "zzz")
  end

  def test_program_of_prefers_bare_program
    assert_equal "/usr/bin/foo", Svc.program_of({ "Program" => "/usr/bin/foo" })
  end

  def test_program_of_joins_program_arguments
    assert_equal "ruby /bin/job --flag",
                 Svc.program_of({ "ProgramArguments" => ["ruby", "/bin/job", "--flag"] })
  end

  def test_program_of_none_when_neither_present
    assert_equal "(none)", Svc.program_of({})
    assert_equal "(none)", Svc.program_of({ "ProgramArguments" => [] })
  end
end

class SvcAppTest < Minitest::Test
  def setup
    @launchctl = FakeLaunchctl.new
    @sys = FakeSystem.new
    @out = StringIO.new
    @err = StringIO.new
    @exec_calls = []
  end

  def test_ls_reports_no_agents_when_none_match
    app = build_app
    assert_equal 0, app.run(["ls"])
    assert_includes @out.string, "No com.sebjacobs.* agents in /agents"
  end

  def test_ls_prints_label_schedule_state_and_log
    path = "/agents/com.sebjacobs.brewup.plist"
    @sys.add_plist(path, "Label" => "com.sebjacobs.brewup",
                         "StartInterval" => 3600,
                         "StandardOutPath" => "/log/brewup.log")
    @sys.add_log("/log/brewup.log", mtime: Time.new(2026, 6, 26, 9, 0), last_line: "done")
    @launchctl.list = "42\t0\tcom.sebjacobs.brewup\n"

    assert_equal 0, build_app.run(["ls"])

    out = @out.string
    assert_includes out, "com.sebjacobs.brewup"
    assert_includes out, "schedule : every 3600s"
    assert_includes out, "state    : enabled   last exit: 0"
    assert_includes out, "last log : 2026-06-26 09:00 — done"
  end

  def test_ls_marks_disabled_agents
    path = "/agents/com.sebjacobs.reap.plist"
    @sys.add_plist(path, "Label" => "com.sebjacobs.reap", "RunAtLoad" => true)
    @launchctl.disabled = %("com.sebjacobs.reap" => disabled\n)

    build_app.run(["ls"])
    assert_includes @out.string, "state    : DISABLED   last exit: never run"
  end

  def test_ls_falls_back_to_filename_label_and_no_log
    @sys.add_plist("/agents/com.sebjacobs.ghost.plist", "StartInterval" => 60)

    build_app.run(["ls"])
    out = @out.string
    assert_includes out, "com.sebjacobs.ghost"
    assert_includes out, "last log : (no log yet)"
  end

  def test_bare_invocation_defaults_to_ls
    assert_equal 0, build_app.run([])
    assert_includes @out.string, "No com.sebjacobs.* agents"
  end

  def test_help_prints_usage
    assert_equal 0, build_app.run(["help"])
    assert_includes @out.string, "Usage: svc"
  end

  def test_unknown_command_is_usage_error
    assert_equal 1, build_app.run(["wat"])
    assert_includes @out.string, "Usage: svc"
  end

  def test_tail_follows_log_resolved_from_short_name
    @sys.add_plist("/agents/com.sebjacobs.brewup.plist",
                   "Label" => "com.sebjacobs.brewup", "StandardOutPath" => "/log/brewup.log")

    assert_equal 0, build_app.run(["tail", "brewup"])
    assert_equal ["tail", "-f", "-n", "50", "/log/brewup.log"], @exec_calls.last
  end

  def test_tail_accepts_full_label
    @sys.add_plist("/agents/com.sebjacobs.brewup.plist",
                   "Label" => "com.sebjacobs.brewup", "StandardOutPath" => "/log/brewup.log")

    assert_equal 0, build_app.run(["tail", "com.sebjacobs.brewup"])
    assert_equal ["tail", "-f", "-n", "50", "/log/brewup.log"], @exec_calls.last
  end

  def test_tail_errors_on_ambiguous_match_without_exec
    @sys.add_plist("/agents/com.sebjacobs.brewup.plist", "Label" => "com.sebjacobs.brewup")
    @sys.add_plist("/agents/com.sebjacobs.brew-extra.plist", "Label" => "com.sebjacobs.brew-extra")

    assert_equal 1, build_app.run(["tail", "brew"])
    assert_empty @exec_calls
    assert_includes @err.string, "Multiple agents match 'brew'"
  end

  def test_tail_errors_on_no_match
    @sys.add_plist("/agents/com.sebjacobs.brewup.plist", "Label" => "com.sebjacobs.brewup")

    assert_equal 1, build_app.run(["tail", "zzz"])
    assert_empty @exec_calls
    assert_includes @err.string, "No com.sebjacobs.* agent matching: zzz"
  end

  def test_tail_errors_when_agent_has_no_standardoutpath
    @sys.add_plist("/agents/com.sebjacobs.silent.plist", "Label" => "com.sebjacobs.silent")

    assert_equal 1, build_app.run(["tail", "silent"])
    assert_empty @exec_calls
    assert_includes @err.string, "has no StandardOutPath"
  end

  def test_tail_without_argument_is_usage_error
    assert_equal 1, build_app.run(["tail"])
    assert_empty @exec_calls
    assert_includes @err.string, "Usage: svc tail <job>"
  end

  def test_show_prints_path_schedule_state_program_and_log
    @sys.add_plist("/agents/com.sebjacobs.brewup.plist",
                   "Label" => "com.sebjacobs.brewup",
                   "StartCalendarInterval" => { "Weekday" => 1, "Hour" => 10, "Minute" => 0 },
                   "ProgramArguments" => ["/Users/me/bin/brewup"],
                   "StandardOutPath" => "/log/brewup.log")
    @sys.add_log("/log/brewup.log", mtime: Time.new(2026, 6, 26, 10, 1), last_line: "ok")
    @launchctl.list = "-\t0\tcom.sebjacobs.brewup\n"

    assert_equal 0, build_app.run(["show", "brewup"])

    out = @out.string
    assert_includes out, "plist    : /agents/com.sebjacobs.brewup.plist"
    assert_includes out, "schedule : Mon 10:00 (calendar)"
    assert_includes out, "state    : enabled   last exit: 0"
    assert_includes out, "program  : /Users/me/bin/brewup"
    assert_includes out, "log      : /log/brewup.log"
    assert_includes out, "last log : 2026-06-26 10:01 — ok"
  end

  def test_show_reports_missing_log_path_as_none
    @sys.add_plist("/agents/com.sebjacobs.silent.plist", "Label" => "com.sebjacobs.silent")

    build_app.run(["show", "silent"])
    assert_includes @out.string, "log      : (none)"
  end

  def test_show_errors_on_no_match
    assert_equal 1, build_app.run(["show", "nope"])
    assert_includes @err.string, "No com.sebjacobs.* agent matching: nope"
  end

  def test_show_without_argument_is_usage_error
    assert_equal 1, build_app.run(["show"])
    assert_includes @err.string, "Usage: svc show <job>"
  end

  private

  def build_app
    Svc::App.new(
      launchctl: @launchctl, sys: @sys, out: @out, err: @err,
      prefix: "com.sebjacobs", agents_dir: "/agents", domain: "gui/501",
      exec: ->(*args) { @exec_calls << args }
    )
  end

  class FakeLaunchctl
    attr_accessor :list, :disabled

    def initialize
      @list = ""
      @disabled = ""
    end

    def print_disabled(_domain) = @disabled
  end

  class FakeSystem
    def initialize
      @plists = {}
      @logs = {}
    end

    def add_plist(path, hash) = @plists[path] = hash

    def add_log(path, mtime:, last_line:) = @logs[path] = { mtime: mtime, last_line: last_line }

    def plists(dir, prefix)
      @plists.keys.select { |p| p.start_with?(File.join(dir, "#{prefix}.")) }.sort
    end

    def read_plist(path) = @plists.fetch(path, {})

    def exist?(path) = @logs.key?(path)

    def mtime(path) = @logs.fetch(path)[:mtime]

    def last_line(path) = @logs.fetch(path)[:last_line]
  end
end
