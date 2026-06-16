#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "md_to_commit"

class MdToCommitTest < Minitest::Test
  def convert(md, **opts) = MdToCommit.convert(md, **opts)

  # --- headers -------------------------------------------------------------

  def test_top_level_header_uses_equals_rule
    assert_equal "** Summary **\n=============\n", convert("## Summary")
  end

  def test_h1_also_uses_equals_rule
    assert_equal "** Title **\n===========\n", convert("# Title")
  end

  def test_deep_header_uses_dash_rule
    assert_equal "** Detail **\n------------\n", convert("### Detail")
  end

  def test_rule_matches_header_width
    out = convert("## A longer heading").lines
    assert_equal out[0].chomp.length, out[1].chomp.length
  end

  def test_trailing_hashes_are_stripped_from_header
    assert_equal "** Summary **\n=============\n", convert("## Summary ##")
  end

  # --- inline transforms ---------------------------------------------------

  def test_bold_is_stripped
    assert_equal "a manufacturer here\n", convert("a **manufacturer** here")
  end

  def test_links_are_flattened
    assert_equal "see notes (https://x.com) ok\n",
      convert("see [notes](https://x.com) ok")
  end

  def test_inline_code_backticks_are_preserved
    assert_equal "the `Host#foo` method\n", convert("the `Host#foo` method")
  end

  # --- wrapping ------------------------------------------------------------

  def test_prose_wraps_at_width
    md = "one two three four five"
    assert_equal "one two\nthree four\nfive\n", convert(md, width: 10)
  end

  def test_paragraph_lines_are_joined_before_wrapping
    assert_equal "one two three\n", convert("one\ntwo\nthree", width: 72)
  end

  def test_word_longer_than_width_is_left_intact
    assert_equal "supercalifragilistic\n", convert("supercalifragilistic", width: 10)
  end

  # --- bullets -------------------------------------------------------------

  def test_short_bullets_are_left_alone
    assert_equal "- one\n- two\n", convert("- one\n- two")
  end

  def test_long_bullet_wraps_with_hanging_indent
    md = "- alpha beta gamma delta"
    assert_equal "- alpha beta\n  gamma\n  delta\n", convert(md, width: 12)
  end

  def test_numbered_list_marker_sets_hanging_indent
    md = "1. alpha beta gamma"
    assert_equal "1. alpha\n   beta\n   gamma\n", convert(md, width: 9)
  end

  # --- verbatim blocks -----------------------------------------------------

  def test_fenced_code_is_not_reflowed
    md = "```\na very very very long line that exceeds the width by a lot\n```"
    assert_equal "#{md}\n", convert(md, width: 20)
  end

  def test_table_rows_pass_through
    md = "| a | b |\n|---|---|\n| 1 | 2 |"
    assert_equal "#{md}\n", convert(md, width: 5)
  end

  # --- structure -----------------------------------------------------------

  def test_blank_lines_between_blocks_are_preserved
    assert_equal "a\n\nb\n", convert("a\n\nb")
  end

  # --- fixture snapshots ---------------------------------------------------

  Dir[File.join(__dir__, "fixtures", "*.md")].each do |md_path|
    name = File.basename(md_path, ".md")
    define_method("test_fixture_#{name}") do
      expected = File.read(md_path.sub(/\.md\z/, ".txt"))
      assert_equal expected, convert(File.read(md_path))
    end
  end
end
