#!/usr/bin/env ruby
# frozen_string_literal: true

# proj — quick cd into personal, client, or open-source projects.
#
# This is the logic half of `proj`; the thin zsh wrapper in zsh/projects.zsh
# owns the one thing a subprocess cannot do — change the interactive shell's
# directory. Commands that resolve to a directory write the absolute target to
# the file named by $PROJ_CD_FILE; the wrapper cd's there on return. Everything
# else (map building, current-root resolution, fuzzy matching) lives here, in
# Ruby, so it can be unit-tested without a shell.
#
# `proj <project> <worktree>` cd's into the project, then delegates to gwt
# (required in-process, with the project as its root) to land inside that worktree
# under <project>/.claude/worktrees/. The project-root cd happens first, so an
# unresolved worktree name still leaves the shell in the project root.
#
# Project trees are derived from the $PROJ_ROOT/.projroot manifest (see
# load_trees / parse_manifest) — adding a kind of project is a one-line entry
# there, picked up by both the name->path map and the current-root resolver
# with no other edits.
#
# The set of project display-names is written to $PROJ_CACHE_FILE on every run,
# and the name->path map to $PROJ_PATHS_FILE, so tab-completion can list a
# project's worktrees without paying a Ruby boot per keypress — it only shells
# out (`--list`) once, to warm a cold cache.

require "fileutils"
require "open3"

# Pulls in the sibling gwt.rb for Gwt::ClaudeHistory (project-history migration)
# and Gwt::System (the filesystem seam). Its `__FILE__ == $PROGRAM_NAME` guard
# keeps gwt's CLI dormant when required rather than run directly.
require_relative "gwt"

module Proj
  module_function

  # The completable subcommands, in display order — the single source of truth
  # the dispatch in App#run and the zsh completion (zsh/projects.zsh) both mirror.
  # The completion-drift smoke test (test/shell/completion_drift_test.rb) flags
  # any divergence between this list and the completion's. The bare `.` and
  # `--list` forms are internal (current-root jump / cache warm), not offered as
  # completions, so they are deliberately absent.
  SUBCOMMANDS = %w[ls status mv].freeze

  PROJ_ROOT = ENV.fetch("PROJ_ROOT", File.join(Dir.home, "Tech/Projects"))

  # The manifest at $PROJ_ROOT/.projroot declares which directories are project
  # categories; the tree list below is derived from it rather than hardcoded.
  MANIFEST_FILE = ".projroot"

  # Directory names that are never a project in any category — ARCHIVE (archived
  # work) and session-logs (a jotter store) — excluded globally rather than per
  # line in the manifest.
  GLOBAL_EXCLUDE = ["ARCHIVE", "session-logs"].freeze

  # Parse a manifest into ordered tree hashes. Each non-comment line is
  # `<dir> [depth=N] [type=NAME]`, with <dir> relative to +root+: a bare line
  # derives `type` from the dir's last segment and `depth` 1. Line order is
  # precedence (later trees overwrite earlier ones on a key collision) and the
  # group display order. A category nested inside another (e.g. personal/PRIVATE
  # under personal) is auto-excluded from its parent's walk, replacing a manual
  # exclude. Kept pure (string + root in, trees out) so it's unit-tested
  # directly and a future manifest writer stays symmetric.
  def parse_manifest(content, root)
    trees = content.to_s.each_line.filter_map do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      rel, *opts = line.split(/\s+/)
      options = opts.each_with_object({}) do |opt, acc|
        key, _, value = opt.partition("=")
        acc[key] = value
      end
      { dir: File.join(root, rel), depth: (options["depth"] || "1").to_i,
        type: options["type"].to_s.empty? ? rel.split("/").last : options["type"],
        exclude: GLOBAL_EXCLUDE.dup }
    end
    apply_nested_excludes(trees)
  end

  # Skip any subdir that is itself a declared category root: each tree excludes
  # the first segment of every other tree nested directly beneath it, so a parent
  # category never lists a nested one as one of its projects.
  def apply_nested_excludes(trees)
    trees.map do |tree|
      nested = trees.filter_map do |other|
        next if other.equal?(tree)

        descend(other[:dir], tree[:dir])&.split("/")&.first
      end
      tree.merge(exclude: (tree[:exclude] + nested).uniq)
    end
  end

  # Build the tree list from $root/.projroot when present; otherwise fall back to
  # scanning every top-level dir as a depth-1 category typed by its basename, so
  # `proj` still works on a checkout with no manifest yet.
  def load_trees(root = PROJ_ROOT)
    manifest = File.join(root, MANIFEST_FILE)
    return parse_manifest(File.read(manifest), root) if File.file?(manifest)

    Dir.glob(File.join(root, "*"))
      .select { |dir| File.directory?(dir) }
      .sort
      .map { |dir| { dir: dir, depth: 1, type: File.basename(dir), exclude: GLOBAL_EXCLUDE.dup } }
  end

  # Build the display-name -> path map by walking every tree in precedence order.
  def build_map(trees = load_trees)
    trees.each_with_object({}) do |tree, map|
      project_dirs(tree).each { |dir| map[key_for(dir, tree[:depth])] = dir }
    end
  end

  # Build the display-name -> type map, walking trees in the same precedence
  # order as build_map so a collision's type matches its winning path.
  def build_types(trees = load_trees)
    trees.each_with_object({}) do |tree, types|
      project_dirs(tree).each { |dir| types[key_for(dir, tree[:depth])] = tree[:type] }
    end
  end

  # Group project keys by type for `ls`: +order+ (the manifest's type order)
  # first, any unrecognised type after (sorted), keys sorted within each group.
  # Returns [[type, [keys]], ...] with empty groups dropped, so the caller just
  # prints what it is handed.
  def group_by_type(keys, types, order)
    grouped = keys.group_by { |k| types[k] }
    ordered = order.select { |type| grouped.key?(type) }
    extras = (grouped.keys - order).compact.sort
    (ordered + extras).map { |type| [type, grouped[type].sort] }
  end

  # A project's optional, gitignored `.proj` file declares per-checkout metadata
  # that doesn't belong in the repo. Tags (orthogonal to the structural type) are
  # the first use; the format is forgiving `key: value` lines so it can grow
  # (description, default branch, …) without breaking older parsers — blank lines
  # and `#` comments are skipped and unknown keys ignored.
  PROJ_FILE = ".proj"

  def parse_proj_file(content)
    content.to_s.each_line.each_with_object({}) do |line, config|
      line = line.strip
      next if line.empty? || line.start_with?("#") || !line.include?(":")

      key, _, value = line.partition(":")
      config[key.strip] = value.strip
    end
  end

  # Tokenise a tag value on commas or whitespace, so `tags: a, b c` is [a, b, c].
  def split_tags(value) = value.to_s.split(/[,\s]+/).reject(&:empty?)

  # An indented `ls` row: bare name when untagged, name padded then "[tag …]"
  # when tagged, so the tag columns line up down the listing.
  def format_ls_row(key, tags)
    return "  #{key}" if tags.nil? || tags.empty?

    format("  %-28s [%s]", key, tags.join(" "))
  end

  def tags_for(content) = split_tags(parse_proj_file(content)["tags"])

  # Pull the most-recent branch and its commit time from a single
  # `git for-each-ref --sort=-committerdate --count=1` line (tab-separated
  # `branch<TAB>unix`). Returns [branch, unix_int] or nil when the project has
  # no branches (a repo with no commits), so `recent` skips it. Kept pure so the
  # parsing is unit-tested without spawning git.
  def parse_for_each_ref(output)
    line = output.to_s.lines.first&.strip
    return nil if line.nil? || line.empty?

    branch, _, unix = line.partition("\t")
    return nil if branch.empty? || unix.empty?

    [branch, unix.to_i]
  end

  # Order `recent` entries newest-first, tie-broken by name so the listing is
  # stable when two projects share a commit second. Entries are
  # {key:, branch:, time:} hashes; +time+ is a unix int.
  def sort_recent(entries) = entries.sort_by { |entry| [-entry[:time], entry[:key]] }

  # Format a unix timestamp the way `jotter ls` does — `YYYY-MM-DD HH:MM` in the
  # local zone — so the two listings read alike.
  def format_time(unix) = Time.at(unix).strftime("%Y-%m-%d %H:%M")

  # A `recent` row: project name, its most-recent branch, then the timestamp in
  # the same `(last: …)` shape jotter uses. Columns are padded so names and
  # branches line up down the listing.
  def format_recent_row(key, branch, time_str)
    format("%-28s %-24s (last: %s)", key, branch, time_str)
  end

  def read_proj(dir)
    path = File.join(dir, PROJ_FILE)
    File.file?(path) ? File.read(path) : ""
  end

  # Build the display-name -> tags map by reading each project's .proj. Takes the
  # already-resolved name->path map so a project's tags come from its winning
  # directory, consistent with build_types.
  def build_tags(map)
    map.transform_values { |dir| tags_for(read_proj(dir)) }
  end

  # Parse `ls` arguments into a {type:, tags:} filter. The lone positional (if
  # any) is the type; --tag (repeatable, also --tag=x and comma-joined) collects
  # tags. Kept pure so the precedence and tokenising are unit-tested directly.
  def parse_ls_args(args)
    type = nil
    tags = []
    i = 0
    while i < args.length
      arg = args[i]
      if arg == "--tag"
        i += 1
        tags.concat(split_tags(args[i]))
      elsif arg.start_with?("--tag=")
        tags.concat(split_tags(arg.split("=", 2)[1]))
      elsif type.nil? && !arg.start_with?("-")
        type = arg
      end
      i += 1
    end
    { type: type, tags: tags }
  end

  # Resolve the project root containing +pwd+, or nil if it sits outside every
  # tree (or inside an excluded segment such as ARCHIVE). The first tree that
  # claims +pwd+ wins, so the precedence order above settles overlaps.
  def root_from_pwd(pwd, trees = load_trees)
    trees.each do |tree|
      rel = descend(pwd, tree[:dir])
      next if rel.nil?

      segs = rel.split("/")
      next if segs.length < tree[:depth]

      root_segs = segs.first(tree[:depth])
      next if (root_segs & tree[:exclude]).any?

      return File.join(tree[:dir], *root_segs)
    end
    nil
  end

  # Resolve a query against the map keys: prefix matches win, else substring
  # matches. When the query contains `/`, each segment is matched independently
  # against namespaced keys, so `acm/wid` resolves
  # `acme/widget-tracker`. Returns an array (0, 1, or many). Exact
  # matches are handled by the caller before this is reached.
  def fuzzy_match(keys, query)
    if query.include?("/")
      qc, qp = query.split("/", 2)
      namespaced = keys.select { |k| k.include?("/") }
      by_prefix = namespaced.select { |k| segments_match?(k, qc, qp, :start_with?) }
      return by_prefix unless by_prefix.empty?

      namespaced.select { |k| segments_match?(k, qc, qp, :include?) }
    else
      by_prefix = keys.select { |k| k.start_with?(query) }
      return by_prefix unless by_prefix.empty?

      keys.select { |k| k.include?(query) }
    end
  end

  def project_dirs(tree)
    glob = File.join(tree[:dir], *Array.new(tree[:depth], "*"))
    Dir.glob(glob)
      .select { |dir| File.directory?(dir) }
      .reject { |dir| (segments(dir, tree[:depth]) & tree[:exclude]).any? }
      .sort
  end

  def key_for(path, depth) = segments(path, depth).join("/")

  def segments(path, depth) = path.split("/").last(depth)

  # The remainder of +pwd+ below +base+ (a strict, segment-aligned descendant),
  # or nil. Equal paths and prefix-only siblings (`<base>-x`) return nil.
  def descend(pwd, base)
    prefix = "#{base}/"
    pwd.start_with?(prefix) ? pwd[prefix.length..] : nil
  end

  def segments_match?(key, qc, qp, op)
    kc, kp = key.split("/", 2)
    kc.public_send(op, qc) && kp.public_send(op, qp)
  end

  # Drives a single `proj` invocation. Side-effecting actions are injected so the
  # resolution logic above stays pure and testable: +cd+ receives the directory
  # to change into, +cache+ receives the key list to persist for completion.
  class App
    def initialize(trees:, pwd:, out:, err:, cd:, cache:, paths: ->(_) {}, types: ->(_) {}, tags: ->(_) {}, worktree: nil,
                   sys: nil, git: nil, home: Dir.home, confirm: ->(_) { false }, jotter: ->(*) {})
      @trees = trees
      @pwd = pwd
      @out = out
      @err = err
      @cd = cd
      @cache = cache
      @paths = paths
      @types = types
      @tags = tags
      @worktree = worktree
      @sys = sys || Gwt::System.new
      @git = git || Gwt::Git.new
      @home = home
      @confirm = confirm
      @jotter = jotter
    end

    def run(argv)
      name = argv[0]
      worktree = argv[1]
      root = Proj.root_from_pwd(@pwd, @trees)

      return goto_current_root(root) if name == "."

      map = Proj.build_map(@trees)
      types = Proj.build_types(@trees)
      tags = Proj.build_tags(map)
      @cache.call(map.keys.sort)
      @paths.call(map)
      @types.call(types)
      @tags.call(tags)

      return 0 if name == "--list"
      return cmd_ls(map, types, tags, argv.drop(1)) if name == "ls"
      return cmd_status(map) if name == "status"
      return cmd_mv(map, argv.drop(1)) if name == "mv"
      return print_current_or_list(root, map, types, tags) if name.nil? || name.empty?

      path = resolve_project(name, map)
      return 1 if path.nil?

      enter(path, worktree)
    end

    private

    # Resolve a project query to its path: exact key wins, else a unique fuzzy
    # match. Emits the no-match / ambiguous message and returns nil otherwise, so
    # the caller stays where it is rather than guessing.
    def resolve_project(name, map)
      return map[name] if map.key?(name)

      matches = Proj.fuzzy_match(map.keys, name)
      case matches.length
      when 0
        error("No project matching: #{name}")
        nil
      when 1
        map[matches[0]]
      else
        @err.puts "Multiple projects match '#{name}':"
        matches.each { |m| @err.puts "  #{m}" }
        nil
      end
    end

    # cd into the resolved project, then — when a worktree name follows — hand
    # off to gwt to land inside that worktree. The project-root cd happens first
    # so an unresolved worktree leaves us somewhere useful; gwt overwrites the cd
    # target (it shares this @cd sink) on a unique match. Returns gwt's exit code.
    def enter(path, worktree)
      return change_dir(path) if worktree.nil? || worktree.empty?

      change_dir(path)
      @worktree.call(path, worktree)
    end

    def goto_current_root(root)
      return change_dir(root) if root

      error("proj: not inside a known project tree (#{@trees.map { |t| t[:dir] }.join(', ')})")
    end

    # List projects grouped by type, optionally narrowed by a type positional
    # and/or repeated --tag flags (a project must carry every requested tag).
    # Each project's tags show inline. A bad type errors with the known set so a
    # typo is obvious. `ls` shadows any project literally named "ls" — an
    # accepted edge, since no real project dir carries that name.
    # The manifest's type order, derived from the tree list, driving both the
    # group display order and the "known types" set for the bad-type error.
    def type_order = @trees.map { |tree| tree[:type] }.uniq

    def cmd_ls(map, types, tags, args)
      filter = Proj.parse_ls_args(args)
      keys = map.keys

      if (type = filter[:type])
        known = type_order.select { |t| types.value?(t) }
        return error("proj ls: no such type '#{type}' (known: #{known.join(', ')})") unless known.include?(type)

        keys = keys.select { |key| types[key] == type }
      end

      unless filter[:tags].empty?
        keys = keys.select { |key| (filter[:tags] - (tags[key] || [])).empty? }
      end

      Proj.group_by_type(keys, types, type_order).each_with_index do |(type, group_keys), i|
        @out.puts "" unless i.zero?
        @out.puts type
        group_keys.each { |key| @out.puts Proj.format_ls_row(key, tags[key]) }
      end
      0
    end

    # List every git project newest-first by its most-recent commit, showing the
    # project name, the branch carrying that commit, and the timestamp (the same
    # `(last: …)` shape `jotter ls` uses). One `for-each-ref` per project sees all
    # local branches at once — main and every worktree's branch share the repo's
    # refs — so the top line is the latest branch and its time in a single call.
    # Non-git directories (for-each-ref fails) and commit-less repos (no branch)
    # drop out, so only dated projects appear. `status` shadows any project
    # literally named "status" — an accepted edge, as with `ls`/`mv`.
    def cmd_status(map)
      entries = map.filter_map do |key, dir|
        out, ok = @git.capture("-C", dir, "for-each-ref", "--sort=-committerdate", "--count=1",
                               "refs/heads", "--format=%(refname:short)%09%(committerdate:unix)")
        next unless ok

        branch, time = Proj.parse_for_each_ref(out)
        next if branch.nil?

        { key: key, branch: branch, time: time }
      end

      Proj.sort_recent(entries).each do |entry|
        @out.puts Proj.format_recent_row(entry[:key], entry[:branch], Proj.format_time(entry[:time]))
      end
      0
    end

    # Rename a project's directory to <new-name> within the same parent, then
    # carry the per-checkout history that keys off its path: Claude transcripts
    # (project root + every worktree, migrated precisely) and jotter logs (whose
    # project name is the dir basename — delegated to `jotter mv`). Confirms
    # first; the history moves run only after the directory move succeeds.
    # `mv` shadows any project literally named "mv" — an accepted edge.
    def cmd_mv(map, args)
      old, new = args
      return error("Usage: proj mv <project> <new-name>") if [old, new].any? { |a| a.nil? || a.empty? }
      return error("proj mv: <new-name> must be a single path segment (no '/')") if new.include?("/")

      old_path = resolve_project(old, map)
      return 1 if old_path.nil?

      new_path = File.join(File.dirname(old_path), new)
      return error("proj mv: '#{new}' already exists at #{new_path}") if File.exist?(new_path)

      old_name = File.basename(old_path)
      return 1 unless @confirm.call("Move project '#{old_name}' -> '#{new}' (directory, Claude history, jotter logs)? [y/N] ")

      begin
        @sys.move(old_path, new_path)
      rescue StandardError => e
        return error("proj mv: failed to move #{old_path} -> #{new_path} (#{e.message})")
      end

      migrate_claude_history(old_path, new_path)
      repair_worktrees(new_path)
      migrate_jotter_logs(old_name, new, new_path)
      change_dir(new_path + @pwd[old_path.length..]) if @pwd == old_path || @pwd.start_with?("#{old_path}/")
      0
    end

    # Moving the whole project tree relocates each linked worktree too, so git's
    # stored gitdir pointers (and the repo's back-references) still name the old
    # path and the worktrees show up "prunable" until repaired. `git worktree
    # repair`, run from the new root with each worktree's new path, rewrites both
    # ends. No-op when the project has no worktrees or isn't a git repo. Returns
    # nothing of interest — best-effort, like the history and jotter moves.
    def repair_worktrees(new_path)
      worktrees = Dir.glob(File.join(new_path, ".claude", "worktrees", "*")).select { |wt| File.directory?(wt) }
      return if worktrees.empty? || !File.exist?(File.join(new_path, ".git"))

      @git.run("-C", new_path, "worktree", "repair", *worktrees)
    end

    # The precise set of paths whose Claude history must follow the move: the
    # project root plus each actual worktree under it (enumerated post-move from
    # the new location). Exact pairs, so a sibling project sharing a name prefix
    # is never swept in.
    def migrate_claude_history(old_path, new_path)
      pairs = [[old_path, new_path]]
      Dir.glob(File.join(new_path, ".claude", "worktrees", "*")).each do |wt|
        next unless File.directory?(wt)

        name = File.basename(wt)
        pairs << [File.join(old_path, ".claude", "worktrees", name), File.join(new_path, ".claude", "worktrees", name)]
      end
      Gwt::ClaudeHistory.migrate_paths(sys: @sys, home: @home, pairs: pairs, out: @out, err: @err)
    end

    # Hand the jotter log rename to jotter itself (it owns its git-backed store),
    # but only for a git repo — jotter keys logs by the toplevel basename and has
    # nothing to migrate for a plain directory.
    def migrate_jotter_logs(old_name, new_name, new_path)
      return unless File.exist?(File.join(new_path, ".git"))

      @jotter.call(old_name, new_name, new_path)
    end

    # Inside a project, echo its root (handy for `cd "$(proj)"`); outside any
    # project, fall back to the full grouped listing.
    def print_current_or_list(root, map, types, tags)
      if root
        @out.puts root
        return 0
      end

      cmd_ls(map, types, tags, [])
    end

    def change_dir(path)
      @cd.call(path)
      0
    end

    def error(message)
      @err.puts message
      1
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  cd_sink = lambda do |path|
    file = ENV["PROJ_CD_FILE"]
    File.write(file, path) if file && !file.empty?
  end

  cache_sink = lambda do |keys|
    file = ENV["PROJ_CACHE_FILE"]
    next if file.nil? || file.empty?

    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, keys.join("\n"))
  end

  paths_sink = lambda do |map|
    file = ENV["PROJ_PATHS_FILE"]
    next if file.nil? || file.empty?

    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, map.map { |key, path| "#{key}\t#{path}" }.join("\n"))
  end

  types_sink = lambda do |map|
    file = ENV["PROJ_TYPES_FILE"]
    next if file.nil? || file.empty?

    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, map.map { |key, type| "#{key}\t#{type}" }.join("\n"))
  end

  # The unique tag set, sorted, so completion can offer `proj ls --tag <TAB>`
  # values without booting Ruby. Project->tags would be richer, but completion
  # only needs the flat vocabulary.
  tags_sink = lambda do |map|
    file = ENV["PROJ_TAGS_FILE"]
    next if file.nil? || file.empty?

    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, map.values.flatten.uniq.sort.join("\n"))
  end

  # Pull in the sibling gwt.rb for its Gwt module; its `__FILE__ == $PROGRAM_NAME`
  # guard keeps its CLI body dormant when required rather than run directly.
  require_relative "gwt"

  subdir = ENV.fetch("GWT_WORKTREE_DIR", ".claude/worktrees")
  subdir = ".claude/worktrees" if subdir.empty?

  # Resolve a worktree under the named project by driving gwt in-process
  # with the project as its root. It shares cd_sink, so a unique match overwrites
  # the project-root cd target written moments earlier.
  worktree_sink = lambda do |project_path, name|
    Gwt::App.new(
      git: Gwt::Git.new,
      sys: Gwt::System.new,
      out: $stdout,
      err: $stderr,
      cd: cd_sink,
      confirm: ->(_) { false },
      pwd: project_path,
      exec: ->(*args) { exec(*args) },
      worktree_subdir: subdir,
      root_override: project_path
    ).run(["cd", name])
  end

  confirm = lambda do |prompt|
    $stdout.print(prompt)
    $stdout.flush
    answer = $stdin.getc
    $stdout.puts
    answer&.downcase == "y"
  end

  # Hand a project-logs rename to jotter, which owns its git-backed store. Run
  # from inside the moved project so jotter resolves the right data_dir from the
  # .jotter config that travelled with the directory. Best-effort: a project
  # with no logs makes jotter exit non-zero, which is condensed to one line
  # rather than failing the whole move.
  jotter_sink = lambda do |old_name, new_name, cwd|
    out, status = Open3.capture2e("jotter", "mv", old_name, new_name, chdir: cwd)
    $stderr.puts "proj: jotter logs not migrated (#{out.lines.first&.strip})" unless status.success?
  rescue StandardError => e
    $stderr.puts "proj: jotter not available, logs left under '#{old_name}' (#{e.message})"
  end

  app = Proj::App.new(
    trees: Proj.load_trees,
    pwd: ENV.fetch("PWD", Dir.pwd),
    out: $stdout,
    err: $stderr,
    cd: cd_sink,
    cache: cache_sink,
    paths: paths_sink,
    types: types_sink,
    tags: tags_sink,
    worktree: worktree_sink,
    confirm: confirm,
    jotter: jotter_sink
  )

  exit app.run(ARGV)
end
