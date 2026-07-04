#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "tmpdir"

# Acceptance test for the `proj` zsh completion (zsh/completions/_proj).
#
# boot_test.rb proves `_proj` registers via compinit; the drift test proves its
# subcommand list mirrors the Ruby source. Neither exercises what `_proj`
# actually emits when you Tab. This does: it sources the completion in a real
# `zsh -f` with `compadd` stubbed to record each call's group tag, header
# explanation, and candidates, drives the first-argument case, and asserts the
# groups, their order, and the header formatting.
#
# It captures what `_proj` *requests*, not the rendered menu — the blank line
# and colour only paint in a live terminal (checked by eye). But the leading
# newline and the %B/%F escapes that produce them live in the -X explanation,
# so asserting those locks the behaviour that renders them.
module ProjCompletion
  REPO_ROOT = File.expand_path("../..", __dir__)

  # Records every compadd call as `GROUP<::>tag<::>explanation<::>candidates`.
  # Newlines in the explanation are escaped to <NL> so a header that opens with
  # a blank line stays on one record line for the Ruby side to parse.
  DRIVER = <<~'ZSH'
    zmodload zsh/zutil 2>/dev/null
    compadd() {
      local tag='' expl=''
      local -a cands
      while (( $# )); do
        case $1 in
          -J) tag=$2; shift 2 ;;
          -X) expl=$2; shift 2 ;;
          --) shift; cands=("$@"); break ;;
          -*) shift ;;
          *)  cands=("$@"); break ;;
        esac
      done
      expl=${expl//$'\n'/<NL>}
      print -r -- "GROUP<::>${tag}<::>${expl}<::>${(j: :)cands}"
    }
    CURRENT=2
    words=(proj '')
    source $REPO/zsh/completions/_proj
  ZSH

  def self.groups(env)
    out, _err, _status = Open3.capture3(env, "zsh", "-f", "-c", DRIVER)
    out.lines.grep(/^GROUP<::>/).map { |line| line.chomp.split("<::>", 4)[1..] }
  end
end

class ProjCompletionTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    write("keys",  "acme/widget\ncadence\notter\nripgrep\n")
    write("paths", "cadence\t/p/cadence\n")
    write("types", "cadence\tpersonal\notter\tpersonal\nacme/widget\tclient\nripgrep\topensource\n")
    write("tags",  "rust\ncli\n")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_emits_commands_then_project_groups_in_manifest_order
    by_tag = groups.to_h { |tag, _expl, cands| [tag, cands] }

    assert_equal %w[commands personal client opensource], groups.map(&:first)
    assert_equal "ls show status mv init", by_tag["commands"]
    assert_equal "cadence otter", by_tag["personal"]
    assert_equal "acme/widget", by_tag["client"]
    assert_equal "ripgrep", by_tag["opensource"]
  end

  def test_group_headers_open_with_a_blank_line_and_bold_colour
    groups.each do |tag, expl, _cands|
      assert expl.start_with?("<NL>"), "#{tag} header should open with a blank line, got #{expl.inspect}"
      assert_includes expl, "%B", "#{tag} header should be bold"
      assert_includes expl, "%F", "#{tag} header should be coloured"
    end
  end

  private

  def write(name, content) = File.write(File.join(@dir, name), content)

  def groups
    ProjCompletion.groups(
      "REPO" => ProjCompletion::REPO_ROOT,
      "PROJ_CACHE_FILE" => File.join(@dir, "keys"),
      "PROJ_PATHS_FILE" => File.join(@dir, "paths"),
      "PROJ_TYPES_FILE" => File.join(@dir, "types"),
      "PROJ_TAGS_FILE" => File.join(@dir, "tags")
    )
  end
end

# Proves projects.zsh registers a yellow `list-colors` entry for each starred
# project, and only for those. `_proj_apply_star_colors` runs when projects.zsh
# is sourced; zstyle is stubbed to echo its list-colors payload, so the assertion
# is on exactly what the shell asks the completion listing to colour under the
# broad `default`-tag context (the only one list-colors is honoured under). The
# rendered yellow only paints in a live terminal (checked by eye via zpty).
class ProjStarColorsTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)

  DRIVER = <<~'ZSH'
    zstyle() {
      [[ $2 == list-colors ]] && print -r -- "LISTCOLORS<::>${(j: :)@[3,-1]}"
    }
    source $REPO/zsh/projects.zsh
  ZSH

  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "proj"))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_registers_a_yellow_list_color_for_each_starred_project
    write_starred("cadence\notter\n")
    line = list_colors
    assert_includes line, "=cadence=01;33"
    assert_includes line, "=otter=01;33"
  end

  def test_registers_no_list_colors_when_nothing_is_starred
    write_starred("")
    assert_nil list_colors
  end

  private

  def write_starred(content) = File.write(File.join(@dir, "proj", "starred"), content)

  def list_colors
    env = { "REPO" => REPO_ROOT, "XDG_CACHE_HOME" => @dir }
    out, _err, _status = Open3.capture3(env, "zsh", "-f", "-c", DRIVER)
    out.lines.grep(/^LISTCOLORS<::>/).first&.chomp&.split("<::>", 2)&.last
  end
end
