#!/usr/bin/env ruby
# frozen_string_literal: true

# md_to_commit — convert a Markdown PR description into a git-commit-friendly body.
#
# Intended for pasting a PR description into a merge commit: GitHub PR bodies are
# Markdown, but a good merge-commit body is plain text with house-style headers,
# hard-wrapped at 72 columns.
#
# Transformations:
#   - `# `/`## Header`   -> `** Header **` underlined with `=` (top-level)
#   - `### ` and deeper  -> `** Header **` underlined with `-`
#   - `**bold**`         -> bold              (inline emphasis stripped)
#   - `[text](url)`      -> text (url)         (links flattened)
#   - prose paragraphs   -> hard-wrapped at WIDTH (default 72, vim `gq` style)
#   - bullets / numbered -> wrapped with a hanging indent, so continuation
#                           lines align under the text and the list is preserved
#   - fenced ``` blocks  -> passed through verbatim (never reflowed)
#   - `| table |` rows   -> passed through verbatim
#   - inline `code`      -> backticks preserved
#
# Usage:  md_to_commit.rb [WIDTH] < pr_body.md
module MdToCommit
  DEFAULT_WIDTH = 72

  HEADER = /\A(\#{1,6})\s+(.*?)\s*\#*\s*\z/
  BULLET = /\A(\s*)([-*+]|\d+\.)\s+(.*)\z/
  FENCE  = /\A\s*```/
  TABLE  = /\A\s*\|/
  BLANK  = /\A\s*\z/

  module_function

  def convert(markdown, width: DEFAULT_WIDTH)
    lines = markdown.split("\n", -1)
    lines.pop if lines.last == "" # ignore the newline that terminates the input

    out = []
    i = 0
    while i < lines.size
      i = consume(lines, i, out, width)
    end
    out.join("\n") + "\n"
  end

  # Dispatch one block starting at `i`, append its rendered lines to `out`,
  # and return the index of the next unconsumed line.
  def consume(lines, i, out, width)
    line = lines[i]

    if fence?(line)
      pass_through_fence(lines, i, out)
    elsif blank?(line)
      out << ""
      i + 1
    elsif (match = HEADER.match(line))
      out.concat(render_header(match[1], match[2]))
      i + 1
    elsif table?(line)
      out << line
      i + 1
    elsif (match = BULLET.match(line))
      render_bullet(lines, i, match, out, width)
    else
      render_paragraph(lines, i, out, width)
    end
  end

  def render_header(hashes, text)
    header = "** #{inline(text)} **"
    rule_char = hashes.length <= 2 ? "=" : "-"
    [header, rule_char * header.length]
  end

  def render_bullet(lines, i, match, out, width)
    lead, marker, rest = match.captures
    first_indent = "#{lead}#{marker} "
    cont_indent  = " " * first_indent.length

    parts = [rest]
    i += 1
    while i < lines.size && plain?(lines[i])
      parts << lines[i]
      i += 1
    end

    out.concat(wrap(inline(parts.join(" ")), first_indent, cont_indent, width))
    i
  end

  def render_paragraph(lines, i, out, width)
    parts = []
    while i < lines.size && plain?(lines[i])
      parts << lines[i]
      i += 1
    end

    out.concat(wrap(inline(parts.join(" ")), "", "", width))
    i
  end

  def pass_through_fence(lines, i, out)
    out << lines[i]
    i += 1
    while i < lines.size && !fence?(lines[i])
      out << lines[i]
      i += 1
    end
    if i < lines.size # closing fence
      out << lines[i]
      i += 1
    end
    i
  end

  # Greedy word wrap. Words longer than the width are left intact, matching `gq`.
  def wrap(text, first_indent, cont_indent, width)
    words = text.split(/\s+/).reject(&:empty?)
    return [] if words.empty?

    lines = []
    current = first_indent + words.shift
    words.each do |word|
      if current.length + 1 + word.length <= width
        current = "#{current} #{word}"
      else
        lines << current
        current = cont_indent + word
      end
    end
    lines << current
    lines
  end

  def inline(text)
    text.gsub(/\*\*(.+?)\*\*/, '\1').gsub(/\[([^\]]+)\]\(([^)]+)\)/, '\1 (\2)')
  end

  # A "plain" line is wrappable prose: not blank, not a structural element.
  def plain?(line)
    !blank?(line) && !HEADER.match?(line) && !BULLET.match?(line) &&
      !fence?(line) && !table?(line)
  end

  def blank?(line) = BLANK.match?(line)
  def fence?(line) = FENCE.match?(line)
  def table?(line) = TABLE.match?(line)
end

if $PROGRAM_NAME == __FILE__
  width = ARGV.first&.match?(/\A\d+\z/) ? Integer(ARGV.shift) : MdToCommit::DEFAULT_WIDTH
  print MdToCommit.convert($stdin.read, width: width)
end
