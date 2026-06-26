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
end

class SvcAppTest < Minitest::Test
  def setup
    @launchctl = FakeLaunchctl.new
    @sys = FakeSystem.new
    @out = StringIO.new
    @err = StringIO.new
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

  private

  def build_app
    Svc::App.new(
      launchctl: @launchctl, sys: @sys, out: @out, err: @err,
      prefix: "com.sebjacobs", agents_dir: "/agents", domain: "gui/501"
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
