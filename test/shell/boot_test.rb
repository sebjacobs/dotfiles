#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require "tmpdir"

module ShellBoot
  REPO_ROOT = File.expand_path("../..", __dir__)

  def self.default_ruby
    env = File.read(File.join(REPO_ROOT, "zsh", "env.zsh"))
    env[/^DEFAULT_RUBY=(\S+)/, 1]
  end

  def self.ruby_bin_dir
    File.join(Dir.home, ".rubies", default_ruby, "bin")
  end

  def self.non_interactive(snippet)
    run(["zsh", "-f", "-c", "source #{REPO_ROOT}/zsh/env.zsh\n#{snippet}"])
  end

  # Boot through a throwaway ZDOTDIR of symlinks to the committed rc files — the
  # way setup.sh installs them into $HOME. Their self-location follows the
  # symlink back to the repo, while compinit's dump stays out of the worktree.
  def self.interactive(snippet, login: false)
    Dir.mktmpdir do |dir|
      %w[.zshenv .zshrc].each do |rc|
        File.symlink(File.join(REPO_ROOT, rc), File.join(dir, rc))
      end
      flags = login ? "-lic" : "-ic"
      run(["zsh", flags, snippet], env: { "ZDOTDIR" => dir })
    end
  end

  def self.run(argv, env: {})
    out, err, status = Open3.capture3(env, *argv)
    Result.new(out, err, status.exitstatus)
  end

  Result = Struct.new(:stdout, :stderr, :status)
end

class NonInteractiveBootTest < Minitest::Test
  def test_boots_cleanly_with_no_stderr
    result = ShellBoot.non_interactive("print -r -- booted")
    assert_equal 0, result.status, "non-interactive shell exited non-zero"
    assert_empty result.stderr, "non-interactive boot wrote to stderr"
    assert_equal "booted", result.stdout.strip
  end

  def test_resolves_the_default_ruby
    skip "#{ShellBoot.default_ruby} not installed" unless Dir.exist?(ShellBoot.ruby_bin_dir)

    result = ShellBoot.non_interactive('print -r -- "$(command -v ruby)|$RUBY_VERSION"')
    path, version = result.stdout.strip.split("|")

    assert_equal File.join(ShellBoot.ruby_bin_dir, "ruby"), path
    assert_equal ShellBoot.default_ruby.delete_prefix("ruby-"), version
  end

  def test_personal_bin_wins_over_homebrew
    result = ShellBoot.non_interactive("print -r -- $PATH")
    entries = result.stdout.strip.split(":")
    home_bin = entries.index(File.join(Dir.home, "bin"))
    homebrew = entries.index { |e| e.include?("/homebrew/") }

    refute_nil home_bin, "~/bin missing from PATH"
    assert home_bin < homebrew, "~/bin should precede Homebrew on PATH" if homebrew
  end
end

class InteractiveBootTest < Minitest::Test
  def test_boots_cleanly_with_no_stderr
    result = ShellBoot.interactive("print -r -- booted")
    assert_equal 0, result.status, "interactive shell exited non-zero:\n#{result.stderr}"
    assert_empty result.stderr, "interactive boot wrote to stderr"
    assert_equal "booted", result.stdout.strip
  end

  def test_login_shell_boots_cleanly
    result = ShellBoot.interactive("print -r -- booted", login: true)
    assert_equal 0, result.status, "login shell exited non-zero:\n#{result.stderr}"
    assert_empty result.stderr, "login boot wrote to stderr"
  end

  def test_resolves_the_default_ruby
    skip "#{ShellBoot.default_ruby} not installed" unless Dir.exist?(ShellBoot.ruby_bin_dir)

    result = ShellBoot.interactive('print -r -- "$(command -v ruby)|$RUBY_VERSION"')
    path, version = result.stdout.strip.split("|")

    assert_equal File.join(ShellBoot.ruby_bin_dir, "ruby"), path
    assert_equal ShellBoot.default_ruby.delete_prefix("ruby-"), version
  end

  def test_loads_project_shell_functions
    result = ShellBoot.interactive("print -r -- ${(M)${(k)functions}:#(gwt|proj)}")
    loaded = result.stdout.strip.split

    assert_includes loaded, "gwt"
    assert_includes loaded, "proj"
  end

  def test_registers_cli_completions
    result = ShellBoot.interactive(
      'print -r -- ${_comps[gwt]} ${_comps[proj]} ${_comps[svc]} ${_comps[dot]} ${_comps[jotter]}'
    )
    registered = result.stdout.strip.split

    %w[_gwt _proj _svc _dot _jotter].each do |fn|
      assert_includes registered, fn, "expected #{fn} bound via compinit"
    end
  end
end
