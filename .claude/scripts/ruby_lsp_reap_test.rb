#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
ScriptTest.load_script("../../bin/ruby-lsp-reap")

class RubyLspReapTest < Minitest::Test
  P = RubyLspReap::Proc_

  def table(*rows)
    rows.each_with_object({}) { |(pid, ppid, cmd), h| h[pid] = P.new(pid, ppid, cmd) }
  end

  # --- ruby_lsp? -----------------------------------------------------------

  def test_matches_the_ruby_lsp_launcher
    assert RubyLspReap.ruby_lsp?("/x/.bundle/ruby/3.4.0/bin/ruby-lsp")
  end

  def test_matches_the_launcher_with_trailing_args
    assert RubyLspReap.ruby_lsp?("/x/bin/ruby-lsp --stdio")
  end

  def test_matches_the_rails_server_child
    assert RubyLspReap.ruby_lsp?("ruby .../ruby_lsp_rails/server.rb")
  end

  def test_ignores_the_reaper_itself
    refute RubyLspReap.ruby_lsp?("/usr/bin/ruby /x/bin/ruby-lsp-reap -l")
  end

  def test_ignores_unrelated_processes
    refute RubyLspReap.ruby_lsp?("/sbin/launchd")
    refute RubyLspReap.ruby_lsp?("/Applications/Zed.app/Contents/MacOS/zed")
  end

  def test_does_not_match_ruby_lsp_substring_elsewhere_in_path
    refute RubyLspReap.ruby_lsp?("/x/ruby-lsp-helpers/run")
  end

  # --- zed_ancestor? -------------------------------------------------------

  def test_detects_a_live_zed_ancestor
    procs = table(
      [100, 50, "/x/bin/ruby-lsp"],
      [50, 1, "/Applications/Zed.app/Contents/MacOS/zed"]
    )
    assert RubyLspReap.zed_ancestor?(100, procs)
  end

  def test_orphan_reparented_to_launchd_has_no_zed_ancestor
    procs = table([100, 1, "/x/bin/ruby-lsp"])
    refute RubyLspReap.zed_ancestor?(100, procs)
  end

  def test_dead_parent_breaks_the_chain
    procs = table([100, 999, "/x/bin/ruby-lsp"])
    refute RubyLspReap.zed_ancestor?(100, procs)
  end

  def test_walks_more_than_one_hop_to_find_zed
    procs = table(
      [100, 90, "/x/bin/ruby-lsp"],
      [90, 80, "/bin/sh"],
      [80, 1, "/Applications/Zed.app/Contents/MacOS/zed"]
    )
    assert RubyLspReap.zed_ancestor?(100, procs)
  end

  def test_terminates_on_a_parent_cycle
    procs = table(
      [100, 200, "/x/bin/ruby-lsp"],
      [200, 100, "/bin/sh"]
    )
    refute RubyLspReap.zed_ancestor?(100, procs)
  end

  # --- candidates / targets ------------------------------------------------

  def test_candidates_exclude_self_and_non_lsp
    procs = table(
      [10, 1, "/x/bin/ruby-lsp"],
      [11, 1, "/sbin/launchd"],
      [12, 1, "/usr/bin/ruby /x/bin/ruby-lsp-reap"]
    )
    assert_equal [10], RubyLspReap.candidates(procs, 12).map(&:pid)
  end

  def test_orphan_targets_spare_servers_with_a_live_zed_ancestor
    procs = table(
      [10, 50, "/x/bin/ruby-lsp"],
      [50, 1, "/Applications/Zed.app/Contents/MacOS/zed"],
      [20, 1, "/y/bin/ruby-lsp"]
    )
    assert_equal [20], RubyLspReap.targets(procs, 0, false).map(&:pid)
  end

  def test_reap_all_targets_every_server_including_in_use
    procs = table(
      [10, 50, "/x/bin/ruby-lsp"],
      [50, 1, "/Applications/Zed.app/Contents/MacOS/zed"],
      [20, 1, "/y/bin/ruby-lsp"]
    )
    assert_equal [10, 20], RubyLspReap.targets(procs, 0, true).map(&:pid).sort
  end

  # --- parse_ps ------------------------------------------------------------

  def test_parses_pid_ppid_and_command_with_spaces
    procs = RubyLspReap.parse_ps("  100   50 /x/bin/ruby-lsp --stdio\n")
    assert_equal 1, procs.size
    assert_equal 50, procs[100].ppid
    assert_equal "/x/bin/ruby-lsp --stdio", procs[100].command
  end

  def test_skips_malformed_lines
    procs = RubyLspReap.parse_ps("garbage\n\n  200 100 /bin/sh\n")
    assert_equal [200], procs.keys
  end
end
