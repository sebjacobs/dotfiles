#!/usr/bin/env ruby
# frozen_string_literal: true

# gwt — git worktree helpers for .claude/worktrees/.
#
# This is the logic half of `gwt`; the thin zsh wrapper in zsh/gwt.zsh owns the
# one thing a subprocess cannot do — change the interactive shell's directory.
# Commands that need a `cd` write the absolute target to the file named by
# $GWT_CD_FILE; the wrapper cd's there on return. Everything else (resolution,
# fuzzy matching, .worktreeinclude copying, status formatting) lives here, in
# Ruby, so it can be unit-tested without a shell.
#
# .worktreeinclude: matching gitignored files are copied from the main worktree
# into a new worktree on `add`. See the wrapper's header for the full contract;
# the copy set is the intersection of "ignored & untracked" with the patterns in
# .worktreeinclude, and symlinks are dereferenced (cp -L) so the worktree gets a
# real file rather than a dangling link. Regular entries are cloned with one APFS
# clonefile(2) copy-on-write syscall, falling back to a plain deep copy when that
# can't apply (a symlinked entry, cross-volume, or non-APFS).

require "fileutils"
require "fiddle"
require "timeout"

module Gwt
  module_function

  # The verbs gwt dispatches on. They double as a reserved-name list: `gwt add`
  # refuses to create a worktree whose directory name would collide with one, so
  # the bare `gwt <name>` cd shortcut can never be shadowed by a worktree.
  SUBCOMMANDS = %w[add cp cd path zed ls rm prune root status].freeze

  # Encode slashes so a branch maps to a single worktree folder
  # (spike/twitter-classifier -> spike+twitter-classifier).
  def encode_branch(branch) = branch.gsub("/", "+")

  # Reject branch names that don't make a safe worktree slug, mirroring the
  # Claude Code CLI's validateWorktreeSlug: cap the length, and for each
  # "/"-separated segment forbid empties, "." / "..", a reserved ".git" segment,
  # and anything outside [A-Za-z0-9._-]. Returns a reason string, or nil if ok.
  def slug_error(name)
    return "must be 64 characters or fewer (got #{name.length})" if name.length > 64

    name.split("/", -1).each do |segment|
      return "must not contain empty path segments" if segment.empty?
      return %(must not contain "." or ".." path segments) if [".", ".."].include?(segment)
      return %("#{segment}" is a reserved git directory name) if segment.downcase.sub(/\.+\z/, "") == ".git"
      return %("#{segment}" may contain only letters, digits, dots, underscores, and dashes) unless segment.match?(/\A[A-Za-z0-9._-]+\z/)
    end
    nil
  end

  # Resolve a query against existing worktree names: exact match wins, else
  # prefix matches, else substring matches. Mirrors the shell's "exact dir, then
  # ${q}* glob, then *${q}* glob" cascade. Returns an array (0, 1, or many).
  def fuzzy_match(names, query)
    return [query] if names.include?(query)

    prefix = names.select { |n| n.start_with?(query) }
    return prefix unless prefix.empty?

    names.select { |n| n.include?(query) }
  end

  # Format the ahead/behind suffix shown in `status` (" ↑2 ↓1", " ↑2", "").
  def format_position(ahead, behind)
    ahead = ahead.to_i
    behind = behind.to_i
    if ahead.positive? && behind.positive?
      " ↑#{ahead} ↓#{behind}"
    elsif ahead.positive?
      " ↑#{ahead}"
    elsif behind.positive?
      " ↓#{behind}"
    else
      ""
    end
  end

  # Parse `git rev-list --left-right --count main...branch` — a tab-separated
  # "<behind>\t<ahead>" — into [ahead, behind] integers.
  def parse_ahead_behind(rev_list_output)
    behind, ahead = rev_list_output.to_s.strip.split("\t", 2)
    [ahead.to_i, behind.to_i]
  end

  # Parse `git worktree list --porcelain` into [{path:, branch:}] entries, in the
  # order git reports them. A new entry starts at each "worktree <path>" line;
  # "branch refs/heads/<name>", a bare "detached", and "prunable <reason>" (git's
  # flag for a registration whose working directory is gone) attach to the open
  # entry.
  def parse_worktrees(porcelain)
    entries = []
    porcelain.to_s.each_line do |line|
      line = line.chomp
      if line.start_with?("worktree ")
        entries << {path: line.delete_prefix("worktree "), branch: nil}
      elsif line.start_with?("branch ") && entries.last
        entries.last[:branch] = line.delete_prefix("branch ").delete_prefix("refs/heads/")
      elsif line == "detached" && entries.last
        entries.last[:branch] = "(detached)"
      elsif line.start_with?("prunable ") && entries.last
        entries.last[:prunable] = line.delete_prefix("prunable ")
      end
    end
    entries
  end

  # When pwd sits inside a worktree, return that worktree's root path (base plus
  # the first path segment); nil otherwise.
  def current_worktree_path(pwd, wt_base)
    prefix = "#{wt_base}/"
    return nil unless pwd.start_with?(prefix)

    "#{wt_base}/#{pwd[prefix.length..].split("/").first}"
  end

  # Thin git wrapper. `capture` reads stdout (stderr discarded) and reports
  # success; `run` streams straight to the terminal for commands whose output the
  # user should see (worktree add/remove). Injectable for tests.
  class Git
    # With a timeout, spawn git and kill it if it overruns (returns failure);
    # without one, this is a plain blocking read. Timeout.timeout(nil) is a no-op,
    # so the fast path stays a straight popen-equivalent.
    def capture(*args, timeout: nil)
      reader, writer = IO.pipe
      pid = Process.spawn("git", *args, out: writer, err: File::NULL)
      writer.close
      out = +""
      begin
        Timeout.timeout(timeout) do
          out = reader.read
          Process.wait(pid)
        end
      rescue Timeout::Error
        Process.kill("TERM", pid)
        Process.wait(pid)
        return ["", false]
      rescue Errno::ESRCH, Errno::ECHILD
        return [out, false]
      ensure
        reader.close
      end
      [out, $?.success?]
    end

    def run(*args) = system("git", *args)
  end

  # Real filesystem side-effects, behind a seam so tests can fake them.
  class System
    CLONEFILE =
      begin
        Fiddle::Function.new(
          Fiddle.dlopen(nil)["clonefile"],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
          Fiddle::TYPE_INT
        )
      rescue Fiddle::DLError
        nil
      end

    def dir?(path) = File.directory?(path)

    def exist?(path) = File.exist?(path)

    def children(path)
      Dir.children(path).select { |e| File.directory?(File.join(path, e)) }.sort
    end

    def remove(path) = FileUtils.rm_rf(path)

    def copy_into(src, dst)
      FileUtils.mkdir_p(File.dirname(dst))
      return true if !File.symlink?(src) && clonefile(src, dst)

      FileUtils.rm_rf(dst)
      system("cp", "-RL", src, dst)
    end

    def which?(cmd) = system("command -v #{cmd} >/dev/null 2>&1")

    private

    def clonefile(src, dst)
      return false unless CLONEFILE

      CLONEFILE.call(src, dst, 0).zero?
    rescue StandardError
      false
    end
  end

  class App
    def initialize(git:, sys:, out:, err:, cd:, confirm:, pwd:, exec:, worktree_subdir: ".claude/worktrees", root_override: nil, timing: false)
      @git = git
      @sys = sys
      @out = out
      @err = err
      @cd = cd
      @confirm = confirm
      @pwd = pwd
      @exec = exec
      @worktree_subdir = worktree_subdir
      @root_override = root_override
      @timing = timing
    end

    def run(argv)
      cmd, *rest = argv
      return usage(0) if ["help", "-h", "--help"].include?(cmd)

      porcelain, ok = capture_worktree_list
      return error("Not in a git repo") unless ok

      @all_worktrees = Gwt.parse_worktrees(porcelain)
      @root = @all_worktrees.first&.fetch(:path)
      return error("Not in a git repo") if @root.nil? || @root.empty?

      @wt_base = "#{@root}/#{@worktree_subdir}"
      case cmd
      when nil      then usage
      when "add"    then cmd_add(rest)
      when "cp"     then cmd_cp(rest)
      when "cd"     then cmd_cd(rest)
      when "path"   then cmd_path(rest)
      when "zed"    then cmd_zed(rest)
      when "ls"     then cmd_ls
      when "root"   then cmd_root(rest)
      when "status" then cmd_status
      when "rm"     then cmd_rm(rest)
      when "prune"  then cmd_prune(rest)
      else cmd_cd(argv)
      end
    end

    # `git worktree list` is the one call every command depends on. Bound it with
    # a timeout so a wedged git can't hang gwt, and retry once: the list is
    # idempotent and the occasional failure (index lock contention, a dropped
    # pipe) clears on a second look. A non-nil @root_override targets another
    # repo via `git -C`, so `proj <project> <worktree>` can resolve a worktree
    # without the shell first cd-ing into that project.
    def capture_worktree_list
      prefix = @root_override ? ["-C", @root_override] : []
      timed("worktree list") do
        out, ok = @git.capture(*prefix, "worktree", "list", "--porcelain", timeout: 10)
        next [out, ok] if ok

        @git.capture(*prefix, "worktree", "list", "--porcelain", timeout: 10)
      end
    end

    private

    def timed(label)
      return yield unless @timing

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
      @err.puts "gwt[timing] #{label}: #{ms}ms"
      result
    end

    def cmd_add(args)
      create_branch = args.first == "-b"
      args = args.drop(1) if create_branch
      branch = args.first
      return error("Usage: gwt add [-b] <branch>") if branch.nil? || branch.empty?

      if (reason = Gwt.slug_error(branch))
        return error(%(Invalid worktree name "#{branch}": #{reason}))
      end

      if Gwt::SUBCOMMANDS.include?(Gwt.encode_branch(branch))
        return error(%("#{branch}" is a reserved gwt subcommand — pick another name))
      end

      wt_dir = "#{@wt_base}/#{Gwt.encode_branch(branch)}"
      if registered?(wt_dir)
        @out.puts "Worktree already exists, cd-ing into it"
        change_dir(wt_dir)
        return 0
      end

      if @sys.dir?(wt_dir)
        return error(
          "An untracked directory is in the way at #{wt_dir} " \
          "(git does not register it as a worktree). Run `gwt prune` to clear it, then retry."
        )
      end

      ok = timed("worktree add") do
        if create_branch
          @git.run("worktree", "add", "-b", branch, wt_dir)
        else
          @git.run("worktree", "add", wt_dir, branch)
        end
      end
      return 1 unless ok

      timed("worktreeinclude") { apply_include(@root, wt_dir) }
      change_dir(wt_dir)
      0
    end

    def cmd_cp(args)
      force = args.first == "-f"
      args = args.drop(1) if force
      rel = args.first
      return error("Usage: gwt cp [-f] <path>") if rel.nil? || rel.empty?

      src = "#{@root}/#{rel}"
      return error("No such file or directory under root: #{rel}") unless @sys.exist?(src)

      targets = worktree_dirs
      return no_worktrees if targets.empty?

      unless force
        return 1 unless @confirm.call("Copy '#{rel}' from root into #{targets.length} worktree(s)? [y/N] ")
      end

      targets.each do |dir|
        @sys.copy_into(src, "#{dir}/#{rel}")
        @out.puts "gwt: copied #{rel} -> #{File.basename(dir)}"
      end
      0
    end

    def cmd_cd(args)
      name = args.first
      return error("Usage: gwt cd <name>") if name.nil? || name.empty?

      resolve(name) { |path| change_dir(path); 0 }
    end

    def cmd_path(args)
      name = args.first
      if name.nil? || name.empty?
        current = Gwt.current_worktree_path(@pwd, @wt_base)
        return error("Usage: gwt path [<name>]") if current.nil?

        @out.puts current
        return 0
      end

      resolve(name) { |path| @out.puts path; 0 }
    end

    def cmd_zed(args)
      unless @sys.which?("zed")
        return error("gwt zed: 'zed' CLI not found on PATH. Install Zed and enable its CLI (Zed → Install CLI).")
      end

      name = args.first
      target =
        if name && !name.empty? && name != "."
          resolved = nil
          status = resolve(name) { |path| resolved = path; 0 }
          return status unless resolved

          resolved
        else
          toplevel, ok = @git.capture("rev-parse", "--show-toplevel")
          return error("gwt zed: not in a git working tree") unless ok

          toplevel.strip
        end

      @exec.call("zed", "-n", target)
      0
    end

    def cmd_ls
      return no_worktrees if worktrees.empty?

      worktrees.each do |wt|
        dir = wt[:path]
        @out.puts format("%s%-40s %s", marker(dir), File.basename(dir), wt[:branch] || "???")
      end
      0
    end

    def cmd_root(args)
      if args.first == "-p"
        @out.puts @root
      else
        change_dir(@root)
      end
      0
    end

    def cmd_status
      return no_worktrees if worktrees.empty?

      main_branch_out, ok = @git.capture("-C", @root, "rev-parse", "--abbrev-ref", "HEAD")
      main_branch = ok ? main_branch_out.strip : "main"

      worktrees.each do |wt|
        dir = wt[:path]
        name = File.basename(dir)
        branch = wt[:branch] || "???"
        dirty_out, = @git.capture("-C", dir, "status", "--porcelain")
        dirty = dirty_out.strip.empty? ? "" : " [dirty]"
        counts, = @git.capture("-C", dir, "rev-list", "--left-right", "--count", "#{main_branch}...#{branch}")
        ahead, behind = Gwt.parse_ahead_behind(counts)
        position = Gwt.format_position(ahead, behind)
        @out.puts format("%s%-30s %-30s%s%s", marker(dir), name, branch, dirty, position)
      end
      0
    end

    def cmd_rm(args)
      force = args.any? { |a| ["-f", "--force"].include?(a) }
      args = args.reject { |a| ["-f", "--force"].include?(a) }
      name = args.first
      return error("Usage: gwt rm [-f] <name>") if name.nil? || name.empty?

      matches = Gwt.fuzzy_match(worktree_dirs.map { |dir| File.basename(dir) }, Gwt.encode_branch(name))
      if matches.length > 1
        @err.puts "Multiple worktrees match '#{name}':"
        matches.each { |m| @err.puts "  #{m}" }
        return 1
      end

      if matches.length == 1
        wt_dir = "#{@wt_base}/#{matches.first}"
        return 1 unless force || @confirm.call("Remove worktree '#{matches.first}'? [y/N] ")

        change_dir(@root) if @pwd.start_with?(wt_dir)
        git_args = ["worktree", "remove", wt_dir]
        git_args << "--force" if force
        return @git.run(*git_args) ? 0 : 1
      end

      wt_dir = "#{@wt_base}/#{Gwt.encode_branch(name)}"
      return error("No worktree: #{name}") unless @sys.dir?(wt_dir)

      return 1 unless force || @confirm.call("'#{name}' is an orphaned directory git no longer tracks. Remove it? [y/N] ")

      change_dir(@root) if @pwd.start_with?(wt_dir)
      @sys.remove(wt_dir)
      0
    end

    def cmd_prune(args)
      force = args.first == "-f"
      phantoms = phantom_dirs
      strays = stray_dirs

      if phantoms.empty? && strays.empty?
        @out.puts "Nothing to prune under #{@worktree_subdir}/"
        return 0
      end

      unless phantoms.empty?
        @git.run("worktree", "prune")
        phantoms.each { |dir| @out.puts "gwt: cleared stale git registration for #{File.basename(dir)}" }
      end

      strays.each do |dir|
        name = File.basename(dir)
        next unless force || @confirm.call("Remove orphaned directory '#{name}' (git does not track it)? [y/N] ")

        @sys.remove(dir)
        @out.puts "gwt: removed orphaned directory #{name}"
      end
      0
    end

    def usage(code = 1)
      @out.puts <<~USAGE
        Usage: gwt <add|cp|cd|zed|ls|rm|prune|root|status|path> [args]
               gwt <name>           Shorthand for `gwt cd <name>`

          add [-b] <branch>    Create worktree and cd into it
          cp [-f] <path>       Copy <path> from root into every worktree (-f skips the prompt)
          cd <name>           cd into an existing worktree
          zed [<name>]        Open a worktree in a new Zed window (current if no name)
          ls                  List worktrees
          rm [-f] <name>      Remove a worktree or orphaned directory (-f forces a dirty one)
          prune [-f]          Clear phantom git registrations and orphaned dirs (-f skips prompts)
          root [-p]           cd back to the main worktree root (or echo it with -p)
          status              Overview of all worktrees
          path [<name>]       Echo absolute path of a worktree (current if no name)
      USAGE
      code
    end

    # --- shared helpers ------------------------------------------------------

    # Resolve a worktree name and yield its path on a unique match, returning the
    # block's value. Emits the appropriate stderr message and a non-zero code on
    # no/ambiguous match.
    def resolve(name)
      query = Gwt.encode_branch(name)
      matches = Gwt.fuzzy_match(worktree_dirs.map { |dir| File.basename(dir) }, query)
      case matches.length
      when 0
        error("No worktree matching: #{name}")
      when 1
        yield("#{@wt_base}/#{matches.first}")
      else
        @err.puts "Multiple worktrees match '#{name}':"
        matches.each { |m| @err.puts "  #{m}" }
        1
      end
    end

    def apply_include(src_root, dst_root)
      include = "#{src_root}/.worktreeinclude"
      return unless File.file?(include)

      ignored_set, matched = timed("worktreeinclude scan") do
        ignored, = @git.capture("-C", src_root, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory")
        matched, = @git.capture("-C", src_root, "ls-files", "--others", "--ignored", "--exclude-from=#{include}", "--directory")
        [ignored.split("\n"), matched]
      end

      copied = []
      timed("worktreeinclude copy") do
        matched.split("\n").each do |rel|
          next if rel.empty?
          next unless ignored_set.include?(rel)

          rel = rel.chomp("/")
          @sys.copy_into("#{src_root}/#{rel}", "#{dst_root}/#{rel}")
          copied << rel
        end
      end

      @out.puts "gwt: copied #{copied.length} entries from .worktreeinclude: #{copied.join(' ')}" unless copied.empty?
    end

    # Live git-registered worktrees directly under @wt_base, sorted by path.
    # Orphaned directories (on disk but unknown to git) and phantom registrations
    # (known to git but whose directory is gone, flagged "prunable") never appear.
    def worktrees
      prefix = "#{@wt_base}/"
      @all_worktrees
        .reject { |wt| wt[:prunable] }
        .select { |wt| wt[:path].start_with?(prefix) && !wt[:path][prefix.length..].include?("/") }
        .sort_by { |wt| wt[:path] }
    end

    def worktree_dirs = worktrees.map { |wt| wt[:path] }

    def registered?(dir) = @all_worktrees.any? { |wt| wt[:path] == dir && !wt[:prunable] }

    # Directories under @wt_base that git does not register as a live worktree.
    def stray_dirs
      return [] unless @sys.dir?(@wt_base)

      on_disk = @sys.children(@wt_base).map { |name| "#{@wt_base}/#{name}" }
      on_disk - worktree_dirs
    end

    # Worktrees git still registers under @wt_base but whose working directory is
    # gone; git flags these "prunable" and `git worktree prune` clears them.
    def phantom_dirs
      prefix = "#{@wt_base}/"
      @all_worktrees
        .select { |wt| wt[:prunable] && wt[:path].start_with?(prefix) }
        .map { |wt| wt[:path] }
    end

    def marker(dir) = @pwd.start_with?(dir) ? "* " : "  "

    def no_worktrees
      @out.puts "No worktrees in .claude/worktrees/"
      0
    end

    def change_dir(path) = @cd.call(path)

    def error(message)
      @err.puts message
      1
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  cd_sink = lambda do |path|
    file = ENV["GWT_CD_FILE"]
    File.write(file, path) if file && !file.empty?
  end

  confirm = lambda do |prompt|
    $stdout.print(prompt)
    $stdout.flush
    answer = $stdin.getc
    $stdout.puts
    answer&.downcase == "y"
  end

  subdir = ENV.fetch("GWT_WORKTREE_DIR", ".claude/worktrees")
  subdir = ".claude/worktrees" if subdir.empty?

  app = Gwt::App.new(
    git: Gwt::Git.new,
    sys: Gwt::System.new,
    out: $stdout,
    err: $stderr,
    cd: cd_sink,
    confirm: confirm,
    pwd: Dir.pwd,
    exec: ->(*args) { exec(*args) },
    worktree_subdir: subdir,
    timing: !ENV["GWT_TIMING"].to_s.empty?
  )

  exit app.run(ARGV)
end
