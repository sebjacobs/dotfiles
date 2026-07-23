#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
ScriptTest.load_script("../bin/zombie-kill")

class ZombieKillTest < Minitest::Test
  P = ZombieKill::Proc_

  ATTACHED_PPID = 999

  def ps(*rows)
    rows.map { |pid, ucomm, args| P.new(pid, ATTACHED_PPID, "??", ucomm, args) }
  end

  def orphan(pid, ucomm, args)
    P.new(pid, ZombieKill::LAUNCHD_PID, "??", ucomm, args)
  end

  # --- parse_ps ------------------------------------------------------------

  def test_parses_pid_ppid_tty_ucomm_and_the_full_args
    procs = ZombieKill.parse_ps("  501 1 ttys000 node  /usr/local/bin/node server.js --port 3000\n")

    assert_equal 1, procs.length
    assert_equal 501, procs.first.pid
    assert_equal 1, procs.first.ppid
    assert_equal "ttys000", procs.first.tty
    assert_equal "node", procs.first.ucomm
    assert_equal "/usr/local/bin/node server.js --port 3000", procs.first.args
  end

  def test_parses_the_placeholder_tty_of_a_process_with_no_terminal
    procs = ZombieKill.parse_ps("501 1 ?? node /x/node app.js\n")

    assert_equal "??", procs.first.tty
  end

  def test_skips_lines_without_a_numeric_pid
    assert_empty ZombieKill.parse_ps("PID PPID TTY COMMAND ARGS\n")
  end

  def test_skips_lines_without_a_numeric_ppid
    assert_empty ZombieKill.parse_ps("501 - ?? node /x/node\n")
  end

  def test_skips_lines_with_no_args_column
    assert_empty ZombieKill.parse_ps("501 1 ?? node\n")
  end

  # --- candidates: matching ------------------------------------------------

  def test_matches_a_runtime_by_name
    procs = ps([1, "java", "/usr/bin/java -Dgradle.daemon"])

    assert_equal [1], ZombieKill.candidates(procs, 999).map(&:pid)
  end

  def test_matches_are_case_insensitive_so_xcode_is_caught
    procs = ps([1, "Xcode", "/Applications/Xcode.app/Contents/MacOS/Xcode"])

    assert_equal [1], ZombieKill.candidates(procs, 999).map(&:pid)
  end

  def test_ignores_unrelated_processes
    procs = ps([1, "launchd", "/sbin/launchd"], [2, "Finder", "/System/.../Finder"])

    assert_empty ZombieKill.candidates(procs, 999)
  end

  def test_matches_a_version_suffixed_runtime
    procs = ps([1, "python3.13", "/opt/homebrew/bin/python3.13 manage.py"],
               [2, "qemu-system-aarch64", "/x/qemu-system-aarch64 -m 2048"])

    assert_equal [1, 2], ZombieKill.candidates(procs, 999).map(&:pid)
  end

  def test_does_not_match_a_longer_word_that_merely_starts_the_same
    procs = ps([1, "nodemon", "/x/nodemon app.js"],
               [2, "uvicorn", "/x/uvicorn main:app"],
               [3, "javascriptcore", "/x/javascriptcore"])

    assert_empty ZombieKill.candidates(procs, 999)
  end

  # Real regression: Dropbox passes `--capture-python` and
  # `-python-version:3.11.14`, so matching the whole command line listed it as
  # prey. The name is the signal; an argument is hearsay.
  def test_does_not_match_a_process_that_merely_mentions_a_runtime_in_its_args
    procs = ps([1, "Dropbox",
                "/Applications/Dropbox.app/Contents/MacOS/Dropbox --capture-python -python-version:3.11.14"])

    assert_empty ZombieKill.candidates(procs, 999)
  end

  # The other half of that trade-off: a Volta-shimmed language server's ucomm is
  # `volta-shim`, and only its executable path reveals it's really node.
  def test_matches_on_the_executable_basename_when_ucomm_hides_the_runtime
    procs = ps([1, "volta-shim", "/Users/x/.volta/bin/node /x/vtsls.js --stdio"])

    assert_equal [1], ZombieKill.candidates(procs, 999).map(&:pid)
  end

  # --- candidates: never offering up our own machinery ---------------------

  def test_excludes_our_own_pid
    procs = ps([1, "ruby", "/usr/bin/ruby /x/bin/anything"])

    assert_empty ZombieKill.candidates(procs, 1)
  end

  # This script runs as `ruby .../zombie-kill`, so it matches its own PATTERN
  # on \bruby\b and would otherwise list itself as prey.
  def test_excludes_itself_even_under_a_different_pid
    procs = ps([1, "ruby", "/usr/bin/ruby /Users/x/bin/zombie-kill"])

    assert_empty ZombieKill.candidates(procs, 999)
  end

  def test_excludes_the_fzf_it_spawned
    procs = ps([1, "fzf", "fzf --multi --header=tab to select, enter to kill node"])

    assert_empty ZombieKill.candidates(procs, 999)
  end

  # --- orphan tagging ------------------------------------------------------

  def test_tags_a_process_reparented_to_launchd_as_an_orphan
    assert_equal "orphan", ZombieKill.tag(orphan(1, "node", "/x/node app.js"))
  end

  def test_tags_a_process_with_a_living_parent_as_attached
    assert_equal "attached", ZombieKill.tag(ps([1, "node", "/x/node app.js"]).first)
  end

  # A Gradle daemon detaches to launchd on purpose, so the tag cannot be
  # promoted to a filter — it only ranks the list the human picks from.
  def test_orphans_are_still_offered_alongside_attached_processes
    procs = [orphan(2, "java", "java -Dgradle.daemon"), *ps([3, "node", "node a"])]

    assert_equal [2, 3], ZombieKill.candidates(procs, 999).map(&:pid)
  end

  # --- format_line ---------------------------------------------------------

  def test_truncates_args_that_would_wreck_the_pickers_layout
    line = ZombieKill.format_line(P.new(1, ATTACHED_PPID, "??", "node", "/x/node #{'-' * 500}"))

    assert_operator line.length, :<=, 45 + ZombieKill::ARGS_WIDTH
    assert line.end_with?("…"), "expected an ellipsis marking the truncation"
  end

  def test_leaves_short_args_intact
    line = ZombieKill.format_line(P.new(1, ATTACHED_PPID, "ttys000", "node", "/x/node app.js"))

    assert line.end_with?("/x/node app.js")
  end

  def test_leads_the_line_with_the_tag_and_shows_the_tty
    line = ZombieKill.format_line(orphan(7, "node", "/x/node app.js"))

    assert line.start_with?("orphan"), "expected the tag to lead the line, got: #{line}"
    assert_includes line, "??"
  end

  def test_sorts_by_pid
    procs = ps([9, "node", "node a"], [2, "ruby", "ruby b"], [5, "java", "java c"])

    assert_equal [2, 5, 9], ZombieKill.candidates(procs, 999).map(&:pid)
  end

  def test_sorts_orphans_ahead_of_attached_processes
    procs = [*ps([2, "node", "node a"], [4, "ruby", "ruby b"]),
             orphan(9, "java", "java c"), orphan(11, "python", "python d")]

    assert_equal [9, 11, 2, 4], ZombieKill.candidates(procs, 999).map(&:pid)
  end

  # --- selected_pids -------------------------------------------------------

  def test_reads_the_pid_from_each_selected_line
    output = "orphan   501     ttys000 node   /usr/local/bin/node\n" \
             "attached 7       ??      java   /usr/bin/java\n"

    assert_equal [501, 7], ZombieKill.selected_pids(output)
  end

  # An aborted picker (esc) yields an empty string. Expanding that to "kill
  # everything" is the failure mode this tool must never have.
  def test_an_aborted_picker_selects_nothing
    assert_empty ZombieKill.selected_pids("")
    assert_empty ZombieKill.selected_pids(nil)
  end

  def test_ignores_lines_with_no_pid_in_the_second_column
    assert_empty ZombieKill.selected_pids("no pid here\n")
  end

  # The round trip that matters: whatever format_line renders, selected_pids
  # must be able to read a pid back out of.
  def test_reads_back_the_pid_from_a_line_it_rendered
    line = ZombieKill.format_line(orphan(4242, "node", "/x/node app.js"))

    assert_equal [4242], ZombieKill.selected_pids(line)
  end

  # --- usage ---------------------------------------------------------------

  def test_usage_extracts_the_header_block
    source = [
      "# zombie-kill — blurb\n",
      "#\n",
      "# Usage:\n",
      "#   zombie-kill        pick from the matches\n",
      "\n",
      "module ZombieKill\n"
    ]

    assert_equal ["Usage:\n", "  zombie-kill        pick from the matches\n"],
                 ZombieKill.usage(source)
  end

  def test_the_real_header_still_yields_a_usage_block
    refute_empty ZombieKill.usage
  end
end
