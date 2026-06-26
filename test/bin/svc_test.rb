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

  def test_install_name_error_accepts_prefixed_plist
    assert_nil Svc.install_name_error("com.sebjacobs.foo.plist", "com.sebjacobs")
  end

  def test_install_name_error_rejects_non_plist
    assert_equal "not a .plist file",
                 Svc.install_name_error("com.sebjacobs.foo", "com.sebjacobs")
  end

  def test_install_name_error_rejects_wrong_prefix
    reason = Svc.install_name_error("com.other.foo.plist", "com.sebjacobs")
    assert_includes reason, %(must be named "com.sebjacobs.<job>.plist")
  end
end

class SvcAppTest < Minitest::Test
  def setup
    @launchctl = FakeLaunchctl.new
    @sys = FakeSystem.new
    @out = StringIO.new
    @err = StringIO.new
    @exec_calls = []
    @editor_calls = []
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

  def test_install_symlinks_and_bootstraps_a_valid_plist
    src = "/proj/launchd/com.sebjacobs.job.plist"
    @sys.add_file(src)

    assert_equal 0, build_app.run(["install", src])

    assert_equal src, @sys.linked_to("/agents/com.sebjacobs.job.plist")
    assert_equal [["gui/501", "/agents/com.sebjacobs.job.plist"]], @launchctl.bootstrapped
    assert_includes @out.string, "installed and loaded com.sebjacobs.job.plist -> #{src}"
  end

  def test_install_refuses_plist_without_the_prefix
    src = "/proj/com.other.job.plist"
    @sys.add_file(src)

    assert_equal 1, build_app.run(["install", src])
    assert_nil @sys.linked_to("/agents/com.other.job.plist")
    assert_empty @launchctl.bootstrapped
    assert_includes @err.string, "Refusing to install com.other.job.plist"
  end

  def test_install_errors_when_source_missing
    assert_equal 1, build_app.run(["install", "/nope/com.sebjacobs.job.plist"])
    assert_empty @launchctl.bootstrapped
    assert_includes @err.string, "No such file"
  end

  def test_install_is_idempotent_when_already_loaded
    src = "/proj/com.sebjacobs.job.plist"
    @sys.add_file(src)
    @sys.add_symlink("/agents/com.sebjacobs.job.plist", src)
    @launchctl.list = "42\t0\tcom.sebjacobs.job\n"

    assert_equal 0, build_app.run(["install", src])
    assert_empty @launchctl.bootstrapped
    assert_includes @out.string, "already loaded"
  end

  def test_install_refuses_to_clobber_a_link_to_another_target
    src = "/proj/com.sebjacobs.job.plist"
    @sys.add_file(src)
    @sys.add_symlink("/agents/com.sebjacobs.job.plist", "/elsewhere/com.sebjacobs.job.plist")

    assert_equal 1, build_app.run(["install", src])
    assert_empty @launchctl.bootstrapped
    assert_includes @err.string, "already exists, pointing to /elsewhere/com.sebjacobs.job.plist"
  end

  def test_install_surfaces_a_bootstrap_failure
    src = "/proj/com.sebjacobs.job.plist"
    @sys.add_file(src)
    @launchctl.bootstrap_result = ["Bootstrap failed: 5: Input/output error", false]

    assert_equal 1, build_app.run(["install", src])
    assert_includes @err.string, "launchctl bootstrap failed for com.sebjacobs.job.plist"
  end

  def test_install_without_argument_is_usage_error
    assert_equal 1, build_app.run(["install"])
    assert_includes @err.string, "Usage: svc install <plist>"
  end

  def test_edit_opens_the_real_source_then_reloads
    @sys.add_plist("/agents/com.sebjacobs.job.plist", "Label" => "com.sebjacobs.job")
    @sys.add_symlink("/agents/com.sebjacobs.job.plist", "/proj/com.sebjacobs.job.plist")

    assert_equal 0, build_app.run(["edit", "job"])

    assert_equal ["/proj/com.sebjacobs.job.plist"], @editor_calls
    assert_equal [["gui/501", "com.sebjacobs.job"]], @launchctl.booted_out
    assert_equal [["gui/501", "/agents/com.sebjacobs.job.plist"]], @launchctl.bootstrapped
    assert_includes @out.string, "reloaded com.sebjacobs.job"
  end

  def test_edit_opens_the_path_directly_when_not_a_symlink
    @sys.add_plist("/agents/com.sebjacobs.job.plist", "Label" => "com.sebjacobs.job")

    build_app.run(["edit", "job"])
    assert_equal ["/agents/com.sebjacobs.job.plist"], @editor_calls
  end

  def test_edit_surfaces_a_reload_failure
    @sys.add_plist("/agents/com.sebjacobs.job.plist", "Label" => "com.sebjacobs.job")
    @launchctl.bootstrap_result = ["Bootstrap failed", false]

    assert_equal 1, build_app.run(["edit", "job"])
    assert_includes @err.string, "reload failed for com.sebjacobs.job"
  end

  def test_enable_disable_load_unload_restart_act_on_the_resolved_agent
    @sys.add_plist("/agents/com.sebjacobs.job.plist", "Label" => "com.sebjacobs.job")
    app = build_app

    assert_equal 0, app.run(["enable", "job"])
    assert_equal 0, app.run(["disable", "job"])
    assert_equal 0, app.run(["load", "job"])
    assert_equal 0, app.run(["unload", "job"])
    assert_equal 0, app.run(["restart", "job"])

    assert_equal [["gui/501", "com.sebjacobs.job"]], @launchctl.enabled_calls
    assert_equal [["gui/501", "com.sebjacobs.job"]], @launchctl.disabled_calls
    assert_equal [["gui/501", "/agents/com.sebjacobs.job.plist"]], @launchctl.bootstrapped
    assert_equal [["gui/501", "com.sebjacobs.job"]], @launchctl.booted_out
    assert_equal [["gui/501", "com.sebjacobs.job"]], @launchctl.kickstarted
    assert_includes @out.string, "restarted com.sebjacobs.job"
  end

  def test_restart_surfaces_a_failure
    @sys.add_plist("/agents/com.sebjacobs.job.plist", "Label" => "com.sebjacobs.job")
    @launchctl.action_result = ["No such process", false]

    assert_equal 1, build_app.run(["restart", "job"])
    assert_includes @err.string, "restart failed for com.sebjacobs.job: No such process"
  end

  def test_state_verbs_error_on_no_match_without_acting
    assert_equal 1, build_app.run(["enable", "nope"])
    assert_empty @launchctl.enabled_calls
    assert_includes @err.string, "No com.sebjacobs.* agent matching: nope"
  end

  def test_state_verbs_without_argument_are_usage_errors
    assert_equal 1, build_app.run(["restart"])
    assert_includes @err.string, "Usage: svc restart <job>"
  end

  private

  def build_app
    Svc::App.new(
      launchctl: @launchctl, sys: @sys, out: @out, err: @err,
      prefix: "com.sebjacobs", agents_dir: "/agents", domain: "gui/501",
      exec: ->(*args) { @exec_calls << args },
      editor: ->(path) { @editor_calls << path }
    )
  end

  class FakeLaunchctl
    attr_accessor :list, :disabled, :bootstrap_result, :action_result
    attr_reader :bootstrapped, :booted_out, :enabled_calls, :disabled_calls, :kickstarted

    def initialize
      @list = ""
      @disabled = ""
      @bootstrap_result = ["", true]
      @action_result = ["", true]
      @bootstrapped = []
      @booted_out = []
      @enabled_calls = []
      @disabled_calls = []
      @kickstarted = []
    end

    def print_disabled(_domain) = @disabled

    def bootstrap(domain, path)
      @bootstrapped << [domain, path]
      @bootstrap_result
    end

    def bootout(domain, label)
      @booted_out << [domain, label]
      @action_result
    end

    def enable(domain, label)
      @enabled_calls << [domain, label]
      @action_result
    end

    def disable(domain, label)
      @disabled_calls << [domain, label]
      @action_result
    end

    def kickstart(domain, label)
      @kickstarted << [domain, label]
      @action_result
    end
  end

  class FakeSystem
    def initialize
      @plists = {}
      @logs = {}
      @files = {}
      @symlinks = {}
    end

    def add_plist(path, hash) = @plists[path] = hash

    def add_log(path, mtime:, last_line:) = @logs[path] = { mtime: mtime, last_line: last_line }

    def add_file(path) = @files[path] = true

    def add_symlink(link, target) = @symlinks[link] = target

    def linked_to(link) = @symlinks[link]

    def plists(dir, prefix)
      @plists.keys.select { |p| p.start_with?(File.join(dir, "#{prefix}.")) }.sort
    end

    def read_plist(path) = @plists.fetch(path, {})

    def exist?(path) = @logs.key?(path) || @files.key?(path)

    def mtime(path) = @logs.fetch(path)[:mtime]

    def last_line(path) = @logs.fetch(path)[:last_line]

    def realpath(path) = path

    def symlink?(path) = @symlinks.key?(path)

    def readlink(path) = @symlinks.fetch(path)

    def symlink(target, link) = @symlinks[link] = target
  end
end
