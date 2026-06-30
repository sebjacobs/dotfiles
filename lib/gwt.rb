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

# fileutils and fiddle are only touched by the file-moving subcommands (add, cp,
# mv, rm) — never by `status`, the hot path. Each costs ~10ms to require, so they
# autoload on first reference rather than on every invocation. timeout is cheap
# and `status` uses it (the worktree-list call has a deadline), so it stays eager.
autoload :FileUtils, "fileutils"
autoload :Fiddle, "fiddle"
require "timeout"
require "yaml"

module Gwt
  module_function

  # The verbs gwt dispatches on. They double as a reserved-name list: `gwt add`
  # refuses to create a worktree whose directory name would collide with one, so
  # the bare `gwt <name>` cd shortcut can never be shadowed by a worktree.
  SUBCOMMANDS = %w[add sync promote send cd mv path zed ls rm prune root status].freeze

  # Encode slashes so a branch maps to a single worktree folder
  # (spike/twitter-classifier -> spike+twitter-classifier).
  def encode_branch(branch) = branch.gsub("/", "+")

  # Migrating Claude Code's per-directory session history when a working tree
  # moves on disk. Claude stores transcripts under ~/.claude/projects/<encoded>,
  # keyed by the launch cwd, so a `git worktree move` (or a `proj` project move)
  # orphans them under the old path unless they are re-homed too. Lives here, in
  # the lib proj already requires, so `proj mv` can reuse it: a project move is
  # the same operation as a worktree move, one path level up — every worktree's
  # history dir shares the project's encoded path as a prefix, so a single
  # prefix-rehoming sweep carries the project and all its worktrees at once.
  module ClaudeHistory
    module_function

    # Mirror Claude Code's own scheme: every non-alphanumeric character in the
    # absolute path becomes "-" (so "/", ".", "+" — e.g. a "feature+x" worktree —
    # all collapse). Deterministic forward, but lossy — "a/b/c" and "a+b-c" both
    # encode to "a-b-c" — so a sweep can't tell a child path from a sibling whose
    # name is a superstring. Callers log what they move so that case is visible.
    def encode(abs_path) = abs_path.gsub(/[^A-Za-z0-9]/, "-")

    # The ~/.claude/projects entries to re-home when old_base moves to new_base:
    # the exact match (the moved tree's own history) plus any deeper path under
    # it (a session launched from a subdirectory; for a project move, every
    # worktree beneath it). Returns [[old_name, new_name], ...] of bare entry
    # names, each re-homed by swapping the encoded prefix.
    def rehome_map(names, old_base, new_base)
      old_enc = encode(old_base)
      new_enc = encode(new_base)
      names.filter_map do |name|
        if name == old_enc
          [name, new_enc]
        elsif name.start_with?("#{old_enc}-")
          [name, "#{new_enc}#{name[old_enc.length..]}"]
        end
      end
    end

    def projects_dir(home) = File.join(home, ".claude", "projects")

    # gwt mv: re-home a single moved tree by PREFIX sweep — the worktree's own
    # history plus any session launched from a subdirectory of it. Best-effort by
    # contract: never raises into the caller, because a move that already
    # succeeded must not be undone by a history hiccup.
    def migrate(sys:, home:, old_path:, new_path:, out:, err:, label: "gwt")
      base = projects_dir(home)
      return unless sys.dir?(base)

      apply_renames(sys, base, rehome_map(sys.entries(base), old_path, new_path), out, label: label)
    rescue StandardError => e
      warn_failed(err, label, e)
    end

    # proj mv: re-home an explicit list of [old_path, new_path] pairs, each by
    # EXACT encoded name — no prefix sweep. A project move can't use the sweep:
    # the encoding is lossy, so `cadence`'s prefix would wrongly pull in a sibling
    # `cadence-extra`. The caller enumerates the precise set (project root + its
    # actual worktrees) so only real descendants move. Same best-effort contract.
    def migrate_paths(sys:, home:, pairs:, out:, err:, label: "proj")
      base = projects_dir(home)
      return unless sys.dir?(base)

      names = sys.entries(base)
      renames = pairs.filter_map do |old_path, new_path|
        next if old_path == new_path

        enc = encode(old_path)
        [enc, encode(new_path)] if names.include?(enc)
      end
      apply_renames(sys, base, renames, out, label: label)
    rescue StandardError => e
      warn_failed(err, label, e)
    end

    # The shared move/merge loop: rename each ~/.claude/projects entry, merging
    # the session files in when the destination already exists. Side-effects go
    # through the injected System seam so this stays testable without ~/.claude.
    def apply_renames(sys, base, renames, out, label:)
      renames.each do |old_name, new_name|
        src = File.join(base, old_name)
        dst = File.join(base, new_name)
        next if src == dst

        if sys.exist?(dst)
          sys.entries(src).each { |child| sys.move(File.join(src, child), File.join(dst, child)) }
          sys.remove(src)
          out.puts "#{label}: merged Claude history into #{new_name}"
        else
          sys.move(src, dst)
          out.puts "#{label}: moved Claude history #{old_name} -> #{new_name}"
        end
      end
    end

    def warn_failed(err, label, error)
      err.puts "#{label}: tree moved, but migrating Claude history failed (#{error.message}). " \
               "Move the matching ~/.claude/projects entry by hand."
    end
  end

  # Declarative worktree-lifecycle config read from a `.gwt` file at the repo
  # root — the config sibling to `.worktreeinclude`. YAML (parsed by stdlib psych,
  # no gem), shaped as `seed:` (files to provision into a new worktree) and
  # `hooks:` (commands keyed by lifecycle event — `post-add`, `pre-rm`). A worktree
  # is data, not just a checkout: `.gwt` is how a repo declares how to bring one to
  # life and tear it down. The parser keeps the raw tree and exposes thin accessors
  # so the schema can grow (option forwarding, scrub) without reshaping callers.
  #
  # The `.gwt` location can be relocated with GWT_FILE (e.g. `.local/.gwt`),
  # mirroring dox's DOX_FILE: resolved relative to the repo root, taken from the
  # shell environment first, then a GWT_FILE pinned in the repo's `.env`, else the
  # default `.gwt`. Only the config file moves — every operation still keys off the
  # same root and worktree as before.
  module Config
    module_function

    # Read and parse the repo's `.gwt`, returning the empty config when the file is
    # absent so callers treat "no config" and "empty config" identically. +gwt_file+
    # is the shell-environment GWT_FILE (nil when unset); the `.env` fallback and
    # default are resolved here through the same reader seam.
    def load(root, reader: File, gwt_file: nil)
      path = File.expand_path(config_relpath(root, reader, gwt_file), root)
      return {} unless reader.file?(path)

      parse(reader.read(path))
    end

    # Where the `.gwt` lives, relative to +root+: an explicit GWT_FILE from the
    # shell wins, then a GWT_FILE pinned in `$root/.env`, else the default `.gwt`.
    def config_relpath(root, reader, gwt_file)
      return gwt_file if gwt_file && !gwt_file.empty?

      from_dotenv = dotenv_value(reader, File.expand_path(".env", root), "GWT_FILE")
      from_dotenv && !from_dotenv.empty? ? from_dotenv : ".gwt"
    end

    # Pull KEY's value from a dotenv-style file through the reader seam, or nil when
    # the file or key is absent. Skips blanks, `#` comments, and an `export ` prefix;
    # strips matching surrounding single/double quotes from the value.
    def dotenv_value(reader, path, key)
      return nil unless reader.file?(path)

      reader.read(path).each_line do |line|
        assignment = line.strip.delete_prefix("export ").strip
        next if assignment.empty? || assignment.start_with?("#")

        name, sep, value = assignment.partition("=")
        return unquote(value.strip) if sep == "=" && name.strip == key
      end
      nil
    end

    def unquote(value)
      return value[1...-1] if value.length >= 2 &&
                              ((value.start_with?(%(")) && value.end_with?(%("))) ||
                               (value.start_with?("'") && value.end_with?("'")))

      value
    end

    # Parse `.gwt` YAML into its raw hash. A malformed or non-mapping document
    # yields {} rather than raising — a broken `.gwt` must never block a `gwt cd`.
    def parse(text)
      data = YAML.safe_load(text.to_s, aliases: false)
      data.is_a?(Hash) ? data : {}
    rescue Psych::SyntaxError
      {}
    end

    # The command (argv array) registered for a lifecycle event, or nil when none
    # is declared. `run:` may be given as a single string (split on whitespace) or
    # an explicit argv list; both normalise to an array ready for exec.
    def hook(config, event)
      run = config.dig("hooks", event.to_s, "run")
      case run
      when String then run.split
      when Array  then run.map(&:to_s)
      end
    end

    # The `seed:` section (include source, scrub rules), or {} when unset.
    def seed(config)
      seed = config["seed"]
      seed.is_a?(Hash) ? seed : {}
    end
  end

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

  # Render a unix commit time as `YYYY-MM-DD HH:MM` in the local zone, matching
  # `proj status` and `jotter ls` so the listings read alike.
  def format_time(unix) = Time.at(unix).strftime("%Y-%m-%d %H:%M")

  # The single dir among +dirs+ that contains +pwd+ — pwd itself or its nearest
  # ancestor (longest match wins) — so when the cwd is inside a worktree only
  # that worktree, never its enclosing root, gets the current-marker. Matches are
  # segment-aligned, so a sibling sharing a name prefix (`repo-x` vs `repo`)
  # never counts.
  def current_dir(pwd, dirs)
    dirs.select { |dir| pwd == dir || pwd.start_with?("#{dir}/") }.max_by(&:length)
  end

  # Parse one `git for-each-ref` per-branch metadata dump into
  # { branch => {time:} }. The format is "<branch>|<committerdate:unix>", so one
  # command yields every branch's last-commit time, replacing a per-worktree
  # `log` each. A pure ref read — no merge-base walk — so it stays flat as
  # branches pile up.
  def parse_for_each_ref(output)
    output.to_s.each_line.with_object({}) do |line, map|
      branch, time = line.chomp.split("|", 2)
      next if branch.nil? || branch.empty?

      map[branch] = {time: time.to_i}
    end
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
    # The clonefile(2) binding loads fiddle and dlopens libc, which `status`
    # never needs — resolve it on first copy instead of at class-load time, and
    # memoize the result (including a nil when the symbol is unavailable).
    def self.clonefile_fn
      return @clonefile_fn if defined?(@clonefile_fn)

      @clonefile_fn =
        begin
          Fiddle::Function.new(
            Fiddle.dlopen(nil)["clonefile"],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )
        rescue Fiddle::DLError
          nil
        end
    end

    def dir?(path) = File.directory?(path)

    def exist?(path) = File.exist?(path)

    def file?(path) = File.file?(path)

    def read(path) = File.read(path)

    # Run a `.gwt` lifecycle hook: spawn argv with the worktree as cwd and stream
    # its output to the terminal (the user should see what provisioning does),
    # returning success. Not exec — gwt continues afterwards (cd in, finish the rm).
    def run_in(dir, argv) = system(*argv, chdir: dir)

    def children(path)
      Dir.children(path).select { |e| File.directory?(File.join(path, e)) }.sort
    end

    # Every entry (files and dirs), unlike `children` which keeps only dirs —
    # the history merge moves individual session files out of a source dir.
    def entries(path) = Dir.exist?(path) ? Dir.children(path).sort : []

    def move(src, dst)
      FileUtils.mkdir_p(File.dirname(dst))
      FileUtils.mv(src, dst)
    end

    def remove(path) = FileUtils.rm_rf(path)

    def copy_into(src, dst)
      FileUtils.mkdir_p(File.dirname(dst))
      return true if !File.symlink?(src) && clonefile(src, dst)

      FileUtils.rm_rf(dst)
      system("cp", "-RL", src, dst)
    end

    # Merge +src+ into +dst+ for `gwt sync`/`gwt promote`: bring in what's missing
    # and refresh what's stale, but never delete the destination's own files (no
    # --delete), so a worktree's (or root's) untracked scratch always survives.
    # --update (the default) keeps a destination copy that's newer than the source —
    # a local edit wins unless +force+ makes the source authoritative. -aL
    # dereferences symlinks to real files, matching copy_into. A directory source
    # gets trailing slashes so its contents merge in place rather than nesting a
    # copy inside.
    def sync_into(src, dst, force:)
      flags = ["-aL"]
      flags << "--update" unless force
      if File.directory?(src)
        FileUtils.mkdir_p(dst)
        src += "/"
        dst += "/"
      else
        FileUtils.mkdir_p(File.dirname(dst))
      end
      system("rsync", *flags, src, dst)
    end

    # The itemized dry-run of the merge sync_into would perform, as an array of
    # rsync change lines (empty when src and dst already agree). Reuses the same
    # -aL/--update flags so the preview matches the apply exactly, adds rsync's own
    # -n (transfer nothing) and -i (itemize each change), and touches nothing on
    # disk — no mkdir — so it's safe to run before the caller has confirmed.
    def sync_preview(src, dst, force:)
      flags = ["-aL", "-n", "-i"]
      flags << "--update" unless force
      if File.directory?(src)
        src += "/"
        dst += "/"
      end
      out = IO.popen(["rsync", *flags, src, dst], err: File::NULL, &:read)
      out.to_s.each_line.map(&:chomp).reject(&:empty?)
    end

    def which?(cmd) = system("command -v #{cmd} >/dev/null 2>&1")

    private

    def clonefile(src, dst)
      fn = System.clonefile_fn
      return false unless fn

      fn.call(src, dst, 0).zero?
    rescue StandardError
      false
    end
  end

  class App
    def initialize(git:, sys:, out:, err:, cd:, confirm:, pwd:, exec:, worktree_subdir: ".claude/worktrees", root_override: nil, timing: false, home: Dir.home, gwt_file: nil)
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
      @home = home
      @gwt_file = gwt_file
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
      when nil      then cmd_status
      when "add"    then cmd_add(rest)
      when "sync"   then cmd_sync(rest)
      when "promote" then cmd_promote(rest)
      when "send"   then cmd_send(rest)
      when "cd"     then cmd_cd(rest)
      when "mv"     then cmd_mv(rest)
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
      spec = args.first
      return error("Usage: gwt add [-b] <branch>[:<start-point>]") if spec.nil? || spec.empty?

      # `-b dogs:main` bases the new branch on another branch's tip. main is only a
      # start-point, not checked out, so this works even when main already has a
      # worktree — git's "same branch in two trees" rule never trips. Only the new
      # branch is slug/reserved-checked; the start-point is git's to resolve.
      branch, start_point = spec.split(":", 2)
      if start_point && !create_branch
        return error(%(A start-point (<branch>:<start-point>) only applies with -b — try `gwt add -b #{spec}`))
      end
      return error("Usage: gwt add -b <branch>:<start-point>") if create_branch && start_point == ""
      return error("Usage: gwt add [-b] <branch>[:<start-point>]") if branch.empty?

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
          add_args = ["worktree", "add", "-b", branch, wt_dir]
          add_args << start_point if start_point
          @git.run(*add_args)
        else
          @git.run("worktree", "add", wt_dir, branch)
        end
      end
      return 1 unless ok

      timed("worktreeinclude") { apply_include(@root, wt_dir) }
      run_hook("post-add", wt_dir)
      change_dir(wt_dir)
      0
    end

    # Re-provision an existing worktree by merging the root's `.worktreeinclude`
    # entries back into it — bring in what's missing, refresh what's stale, never
    # delete the worktree's own files. Targets the named worktree, every worktree
    # (--all), or the current one when neither is given. -f makes the root win on a
    # differing entry (default keeps a locally-newer copy); --hooks re-fires the
    # post-add hook after the merge. Unlike a fresh `add`, this merges into a
    # populated tree, hence rsync rather than copy_into.
    def cmd_sync(args)
      force = [args.delete("-f"), args.delete("--force")].any?
      yes   = [args.delete("-y"), args.delete("--yes")].any?
      hooks = !args.delete("--hooks").nil?
      all   = !args.delete("--all").nil?
      name  = args.first

      return error("gwt sync requires rsync, which isn't on PATH") unless @sys.which?("rsync")
      return error("gwt sync: pass either a name or --all, not both") if all && name

      if all
        targets = worktree_dirs
        return no_worktrees if targets.empty?
        return do_sync(targets, force: force, yes: yes, hooks: hooks)
      end

      if name
        return resolve(name) { |dir| do_sync([dir], force: force, yes: yes, hooks: hooks) }
      end

      current = Gwt.current_worktree_path(@pwd, @wt_base)
      return error("Usage: gwt sync [<name>|--all] [-f] [-y] [--hooks]") if current.nil?

      do_sync([current], force: force, yes: yes, hooks: hooks)
    end

    # Merge root's `.worktreeinclude` entries DOWN into each target worktree. The
    # preview/prompt/apply mechanics live in `reconcile`; here we just build the
    # per-worktree op list (root entry -> worktree entry) and, for the worktrees
    # that were actually applied, re-fire the post-add hook when --hooks is given.
    def do_sync(dirs, force:, yes:, hooks:)
      entries = included_entries(@root)
      groups = dirs.map do |dir|
        [dir, entries.map { |rel| ["#{@root}/#{rel}", "#{dir}/#{rel}"] }]
      end

      applied = reconcile(groups, heading: "gwt: sync would merge root -> worktree:", verb: "synced", force: force, yes: yes)
      return 1 if applied == :declined
      return already_in_sync if applied.empty?

      applied.each do |dir, ops|
        @out.puts "gwt: synced #{ops.length} entries -> #{File.basename(dir)}"
        run_hook("post-add", dir) if hooks
      end
      0
    end

    # Reverse of `sync`: merge a worktree's `.worktreeinclude` entries UP into the
    # canonical root, so an edit made in a worktree becomes the source future
    # worktrees provision from. Scans the worktree's own entries (not root's) so a
    # file created in the worktree but absent from root is still promoted. Defaults
    # to the current worktree; single-source only — no --all, since many worktrees
    # can't merge into one root without clobbering each other.
    def cmd_promote(args)
      force = [args.delete("-f"), args.delete("--force")].any?
      yes   = [args.delete("-y"), args.delete("--yes")].any?
      name  = args.first

      return error("gwt promote requires rsync, which isn't on PATH") unless @sys.which?("rsync")

      if name
        return resolve(name) { |dir| do_promote(dir, force: force, yes: yes) }
      end

      current = Gwt.current_worktree_path(@pwd, @wt_base)
      return error("Usage: gwt promote [<name>] [-f] [-y]") if current.nil?

      do_promote(current, force: force, yes: yes)
    end

    def do_promote(dir, force:, yes:)
      entries = included_entries(dir)
      groups = [[@root, entries.map { |rel| ["#{dir}/#{rel}", "#{@root}/#{rel}"] }]]

      applied = reconcile(groups, heading: "gwt: promote would merge #{File.basename(dir)} -> root:", verb: "promoted", force: force, yes: yes)
      return 1 if applied == :declined
      return already_in_sync if applied.empty?

      root_dir, ops = applied.first
      @out.puts "gwt: promoted #{ops.length} entries -> #{File.basename(root_dir)}"
      0
    end

    # Copy one ad-hoc path between any two endpoints — root or a named worktree —
    # chosen with --from/--to (the omitted side defaults to wherever you are).
    # Unlike sync/promote it isn't tied to `.worktreeinclude`: it moves exactly the
    # path you name, file or whole directory (rsync is recursive). Same preview +
    # prompt as the others; -f makes the source win, -y skips the prompt. This is
    # the lateral worktree -> worktree shuttle as well as a one-off up/down copy.
    def cmd_send(args)
      force = [args.delete("-f"), args.delete("--force")].any?
      yes   = [args.delete("-y"), args.delete("--yes")].any?
      from  = take_value(args, "--from")
      to    = take_value(args, "--to")
      path  = args.first

      return error("gwt send requires rsync, which isn't on PATH") unless @sys.which?("rsync")
      return error("Usage: gwt send <path> [--from <src>] [--to <dst>] [-f] [-y]") if path.nil? || path.empty?

      src_dir = from ? endpoint_dir(from) : current_endpoint_dir
      return 1 if src_dir.nil?

      dst_dir = to ? endpoint_dir(to) : current_endpoint_dir
      return 1 if dst_dir.nil?

      if src_dir == dst_dir
        return error("gwt send: source and destination are the same (#{endpoint_label(src_dir)}) — set --from/--to")
      end

      src_path = "#{src_dir}/#{path}"
      return error("gwt send: no such path under #{endpoint_label(src_dir)}: #{path}") unless @sys.exist?(src_path)

      heading = "gwt: send would copy #{endpoint_label(src_dir)} -> #{endpoint_label(dst_dir)}:"
      groups = [[dst_dir, [[src_path, "#{dst_dir}/#{path}"]]]]
      applied = reconcile(groups, heading: heading, verb: "sent", force: force, yes: yes)
      return 1 if applied == :declined
      return already_in_sync if applied.empty?

      @out.puts "gwt: sent #{path} #{endpoint_label(src_dir)} -> #{endpoint_label(dst_dir)}"
      0
    end

    # Resolve a send endpoint token to an absolute directory: the literal "root"
    # maps to the main worktree, anything else is fuzzy-matched against the worktree
    # names like `cd`. Emits an error and returns nil on no/ambiguous match.
    def endpoint_dir(token)
      return @root if token == "root"

      matches = Gwt.fuzzy_match(worktree_dirs.map { |dir| File.basename(dir) }, Gwt.encode_branch(token))
      case matches.length
      when 1 then "#{@wt_base}/#{matches.first}"
      when 0
        error("No worktree matching: #{token}")
        nil
      else
        @err.puts "Multiple worktrees match '#{token}':"
        matches.each { |m| @err.puts "  #{m}" }
        nil
      end
    end

    # Where a send defaults its omitted endpoint: the worktree you're inside, or
    # the root when you're not in one.
    def current_endpoint_dir = Gwt.current_worktree_path(@pwd, @wt_base) || @root

    def endpoint_label(dir) = dir == @root ? "root" : File.basename(dir)

    # Pull a `--flag value` pair out of +args+ in place, returning the value (or nil
    # if the flag is absent). Used for send's --from/--to.
    def take_value(args, flag)
      i = args.index(flag)
      return nil unless i

      value = args.delete_at(i + 1)
      args.delete_at(i)
      value
    end

    # The preview-then-apply core shared by sync, promote, and send. +groups+ is a
    # list of [dir, ops], each op an [src, dst] entry merge; +heading+ titles the
    # preview and +verb+ labels the timing span. Streams rsync's itemized dry-run
    # for every op, prints what would change, and prompts once for the whole batch
    # (skipped by +yes+) before touching disk. Returns :declined if the prompt is
    # refused, otherwise the [dir, ops] groups actually applied ([] when every
    # target is already in sync) — each caller phrases its own success summary.
    def reconcile(groups, heading:, verb:, force:, yes:)
      previewed = groups.filter_map do |dir, ops|
        lines = ops.flat_map { |src, dst| @sys.sync_preview(src, dst, force: force) }
        [dir, ops, lines] unless lines.empty?
      end
      return [] if previewed.empty?

      @out.puts heading
      previewed.each do |dir, _, lines|
        @out.puts "  #{File.basename(dir)}:"
        lines.each { |line| @out.puts "    #{line}" }
      end

      total = previewed.sum { |_, _, lines| lines.length }
      return :declined unless yes || @confirm.call("Apply #{total} change(s)? [y/N] ")

      previewed.map do |dir, ops, _|
        timed("#{verb} merge") { ops.each { |src, dst| @sys.sync_into(src, dst, force: force) } }
        [dir, ops]
      end
    end

    def already_in_sync
      @out.puts "gwt: already in sync — nothing to do"
      0
    end

    def cmd_cd(args)
      name = args.first
      return error("Usage: gwt cd <name>") if name.nil? || name.empty?

      resolve(name) { |path| change_dir(path); 0 }
    end

    # Rename a worktree's directory (and carry its Claude history), leaving the
    # branch untouched — gwt resolves by directory basename, not branch, so the
    # rename stays navigable while the branch shows separately in ls/status. The
    # history migration runs only after `git worktree move` succeeds, so a
    # refused move (locked/dirty) leaves history where it belongs.
    def cmd_mv(args)
      force = args.any? { |a| ["-f", "--force"].include?(a) }
      args = args.reject { |a| ["-f", "--force"].include?(a) }
      old, new = args
      return error("Usage: gwt mv [-f] <name> <new-name>") if [old, new].any? { |a| a.nil? || a.empty? }

      if (reason = Gwt.slug_error(new))
        return error(%(Invalid worktree name "#{new}": #{reason}))
      end

      new_enc = Gwt.encode_branch(new)
      if Gwt::SUBCOMMANDS.include?(new_enc)
        return error(%("#{new}" is a reserved gwt subcommand — pick another name))
      end

      new_path = "#{@wt_base}/#{new_enc}"
      return error("A worktree already exists at #{new_enc}") if registered?(new_path) || @sys.dir?(new_path)

      resolve(old) do |old_path|
        name = File.basename(old_path)
        next 1 unless force || @confirm.call("Move worktree '#{name}' -> '#{new_enc}' (and its Claude history)? [y/N] ")

        next 1 unless timed("worktree move") { @git.run("worktree", "move", old_path, new_path) }

        Gwt::ClaudeHistory.migrate(sys: @sys, home: @home, old_path: old_path, new_path: new_path, out: @out, err: @err)
        run_hook("post-mv", new_path)
        change_dir(new_path) if @pwd.start_with?(old_path)
        0
      end
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
      listed_worktrees.each do |wt|
        dir = wt[:path]
        @out.puts format("%s%-40s %s", marker(dir), display_name(dir), wt[:branch] || "???")
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

    # The root plus every worktree, ordered newest-commit-first, each row showing
    # the dir name, its branch, a [dirty] flag, and the last-commit timestamp. The
    # recency order makes "what was I last on?" the top line; the root sorts in by
    # its own commit time like any other checkout.
    #
    # Each branch's commit time comes from a single `for-each-ref` over refs/heads
    # — one git invocation for the whole repo, rather than a `log` per worktree.
    # It's a pure ref read (no ahead/behind merge-base walk), so it stays flat as
    # branches pile up. Only dirtiness stays per-worktree: `status` reads each
    # working tree's own index, so it can't be batched; a detached worktree (no
    # branch ref in the dump) also falls back to a per-tree `log`.
    #
    # Those per-worktree calls run concurrently — one thread per row. Git#capture
    # spends its life blocked in the subprocess wait, where Ruby releases the GVL,
    # so the threads overlap their git children and the dirty-check cost stays flat
    # as worktrees pile up rather than growing linearly.
    def cmd_status
      refs, = @git.capture("-C", @root, "for-each-ref",
                           "--format=%(refname:short)|%(committerdate:unix)",
                           "refs/heads/")
      meta = Gwt.parse_for_each_ref(refs)

      rows = listed_worktrees.map do |wt|
        Thread.new do
          dir = wt[:path]
          branch = wt[:branch] || "???"
          info = meta[branch]
          time = info ? info[:time] : @git.capture("-C", dir, "log", "-1", "--format=%ct").first.to_s.strip.to_i
          dirty_out, = @git.capture("-C", dir, "status", "--porcelain")
          { dir: dir, name: display_name(dir), branch: branch, time: time,
            dirty: dirty_out.strip.empty? ? "" : " [dirty]" }
        end
      end.map(&:value)

      rows.sort_by { |row| -row[:time] }.each do |row|
        stamp = row[:time].positive? ? " (last: #{Gwt.format_time(row[:time])})" : ""
        @out.puts format("%s%-30s %-30s%s%s", marker(row[:dir]), row[:name], row[:branch],
                         row[:dirty], stamp)
      end
      0
    end

    RM_USAGE = "Usage: gwt rm [-f] [-d|-D] <name>"

    # Parse rm's flags, accepting bundled short forms (-df, -Df) and long forms.
    # Returns [{force:, delete_branch:}, positionals] or nil on an unknown flag.
    # delete_branch is nil, :safe (-d), or :force (-D) — mirroring git branch.
    def parse_rm_flags(args)
      force = false
      delete_branch = nil
      positionals = []
      args.each do |arg|
        case arg
        when "--force" then force = true
        when "--delete-branch" then delete_branch = :safe
        when "--delete-branch-force" then delete_branch = :force
        when /\A-[a-zA-Z]+\z/
          arg.delete_prefix("-").each_char do |ch|
            case ch
            when "f" then force = true
            when "d" then delete_branch = :safe
            when "D" then delete_branch = :force
            else return nil
            end
          end
        else positionals << arg
        end
      end
      [{force: force, delete_branch: delete_branch}, positionals]
    end

    def cmd_rm(args)
      parsed = parse_rm_flags(args)
      return error(RM_USAGE) if parsed.nil?

      flags, positionals = parsed
      force = flags[:force]
      delete_branch = flags[:delete_branch]
      name = positionals.first
      return error(RM_USAGE) if name.nil? || name.empty?

      matches = Gwt.fuzzy_match(worktree_dirs.map { |dir| File.basename(dir) }, Gwt.encode_branch(name))
      if matches.length > 1
        @err.puts "Multiple worktrees match '#{name}':"
        matches.each { |m| @err.puts "  #{m}" }
        return 1
      end

      if matches.length == 1
        dir_name = matches.first
        wt_dir = "#{@wt_base}/#{dir_name}"
        return 1 unless force || @confirm.call("Remove worktree '#{dir_name}'? [y/N] ")

        run_hook("pre-rm", wt_dir)
        change_dir(@root) if @pwd.start_with?(wt_dir)
        git_args = ["worktree", "remove", wt_dir]
        git_args << "--force" if force
        return 1 unless @git.run(*git_args)

        return delete_branch ? remove_branch(dir_name, delete_branch) : 0
      end

      wt_dir = "#{@wt_base}/#{Gwt.encode_branch(name)}"
      return error("No worktree: #{name}") unless @sys.dir?(wt_dir)

      return 1 unless force || @confirm.call("'#{name}' is an orphaned directory git no longer tracks. Remove it? [y/N] ")

      change_dir(@root) if @pwd.start_with?(wt_dir)
      @sys.remove(wt_dir)
      if delete_branch
        @err.puts "gwt: '#{name}' is untracked by git — its branch (if any) is unknown, so none was deleted"
        return 1
      end
      0
    end

    # Delete the local branch a just-removed worktree was on. Reads the branch from
    # the worktree list captured at startup (still cached after the dir is gone), so
    # we delete the branch git actually had checked out — not an assumed basename,
    # which `gwt mv` can leave diverged from the branch. git refuses to delete a
    # branch checked out elsewhere, which is why this runs only after the remove.
    def remove_branch(dir_name, mode)
      wt = worktrees.find { |w| File.basename(w[:path]) == dir_name }
      branch = wt && wt[:branch]
      if branch.nil? || branch == "(detached)"
        @err.puts "gwt: worktree '#{dir_name}' has no branch to delete"
        return 1
      end

      @git.run("branch", mode == :force ? "-D" : "-d", branch) ? 0 : 1
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

        run_hook("pre-prune", dir)
        @sys.remove(dir)
        @out.puts "gwt: removed orphaned directory #{name}"
      end
      0
    end

    def usage(code = 1)
      @out.puts <<~USAGE
        Usage: gwt <add|sync|promote|send|cd|mv|zed|ls|rm|prune|root|status|path> [args]
               gwt <name>           Shorthand for `gwt cd <name>`

          add [-b] <branch>[:<start>]  Create worktree and cd in (-b <new>:<from> branches off another branch)
          sync [<name>|--all] [-f] [-y] [--hooks]  Merge root's .worktreeinclude DOWN into a worktree
                               (previews + prompts; -y skips the prompt; -f: root wins on conflict;
                                --hooks: re-run post-add; default target: current)
          promote [<name>] [-f] [-y]  Merge a worktree's .worktreeinclude UP into root
                               (previews + prompts; -y skips the prompt; -f: worktree wins; default: current)
          send <path> [--from <src>] [--to <dst>] [-f] [-y]  Copy one ad-hoc path (file or dir)
                               between endpoints (root|<worktree>); omitted side = current.
                               Previews + prompts; -y skips, -f source wins
          cd <name>           cd into an existing worktree
          mv [-f] <name> <new-name>  Rename a worktree's directory + Claude history (-f skips the prompt)
          zed [<name>]        Open a worktree in a new Zed window (current if no name)
          ls                  List the root and its worktrees
          rm [-f] [-d|-D] <name>  Remove a worktree (-f forces a dirty one; -d/-D also deletes its branch)
          prune [-f]          Clear phantom git registrations and orphaned dirs (-f skips prompts)
          root [-p]           cd back to the main worktree root (or echo it with -p)
          status              Root + worktrees, newest-commit-first, with timestamps
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

    # The repo's `.gwt` config, loaded once per run through the @sys seam so tests
    # can stub the file without touching disk.
    def config = @config ||= Gwt::Config.load(@root, reader: @sys, gwt_file: @gwt_file)

    # Fire a lifecycle hook if `.gwt` declares one for +event+, running it with
    # +dir+ as cwd. Best-effort: a failing hook warns but doesn't abort the verb —
    # a worktree that's already created (or about to be removed) shouldn't be left
    # half-done because provisioning hit a snag. Returns the hook's success, or nil
    # when no hook is declared.
    def run_hook(event, dir)
      argv = Gwt::Config.hook(config, event)
      return if argv.nil? || argv.empty?

      @out.puts "gwt: #{event}: #{argv.join(' ')}"
      ok = timed("hook #{event}") { @sys.run_in(dir, argv) }
      @err.puts "gwt: #{event} hook failed (exit non-zero): #{argv.join(' ')}" unless ok
      ok
    end

    # The `.worktreeinclude`-matched gitignored entries under +src_root+, as
    # repo-relative paths (trailing slash trimmed), or [] when no `.worktreeinclude`
    # exists. Both `add` (copy into a fresh worktree) and `sync` (merge into an
    # existing one) provision from this same set.
    def included_entries(src_root)
      include = "#{src_root}/.worktreeinclude"
      return [] unless @sys.file?(include)

      ignored_set, matched = timed("worktreeinclude scan") do
        ignored, = @git.capture("-C", src_root, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory")
        matched, = @git.capture("-C", src_root, "ls-files", "--others", "--ignored", "--exclude-from=#{include}", "--directory")
        [ignored.split("\n"), matched]
      end

      matched.split("\n").filter_map do |rel|
        next if rel.empty?
        next unless ignored_set.include?(rel)

        rel.chomp("/")
      end
    end

    def apply_include(src_root, dst_root)
      copied = []
      timed("worktreeinclude copy") do
        included_entries(src_root).each do |rel|
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

    # The main worktree (git always reports it first), prepended to `ls`/`status`
    # so the root checkout lists alongside its worktrees rather than being the one
    # checkout the listing omits.
    def root_entry = @all_worktrees.first

    def listed_worktrees = [root_entry] + worktrees

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

    # The current dir is the longest listed path containing @pwd, so inside a
    # worktree only that worktree is starred — never the root it nests under.
    def current = @current ||= Gwt.current_dir(@pwd, listed_worktrees.map { |wt| wt[:path] })

    def marker(dir) = dir == current ? "* " : "  "

    # Tag the main worktree in ls/status so its row reads as the root rather than
    # just another checkout sharing the listing — it's the one entry `gwt cd`
    # can't resolve by name (only `gwt root` reaches it).
    def display_name(dir) = dir == @root ? "#{File.basename(dir)} (root)" : File.basename(dir)

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
    timing: !ENV["GWT_TIMING"].to_s.empty?,
    gwt_file: ENV["GWT_FILE"]
  )

  exit app.run(ARGV)
end
