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
# Project trees are declared as data in TREES — adding a new kind of project
# (a new root dir) is a one-line entry, picked up by both the name->path map
# and the current-root resolver with no other edits.
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

  PROJ_DIR = ENV.fetch("PROJ_DIR", File.join(Dir.home, "Tech/Projects/personal"))
  CLIENT_DIR = ENV.fetch("CLIENT_DIR", File.join(Dir.home, "Tech/Projects/client"))
  OPENSOURCE_DIR = ENV.fetch("OPENSOURCE_DIR", File.join(Dir.home, "Tech/Projects/opensource"))

  # Each tree is one searchable root. `depth` is how many path segments below
  # `dir` form a project: 1 keys projects by basename (`cadence`), 2 keys them
  # namespaced (`acme/widget-tracker`). `exclude` drops any project
  # whose segments hit those names. `type` is the completion grouping label —
  # PRIVATE shares `personal` since it lives under the personal root. Order is
  # precedence — later trees overwrite earlier ones on a key collision, so
  # PRIVATE is listed before personal/* and personal wins `session-logs`. Add a
  # kind of project by adding a line here.
  TREES = [
    { dir: File.join(PROJ_DIR, "PRIVATE"), depth: 1, exclude: ["ARCHIVE"], type: "personal" },
    { dir: PROJ_DIR, depth: 1, exclude: ["ARCHIVE", "PRIVATE"], type: "personal" },
    { dir: CLIENT_DIR, depth: 2, exclude: ["ARCHIVE"], type: "client" },
    { dir: OPENSOURCE_DIR, depth: 1, exclude: ["ARCHIVE"], type: "opensource" }
  ].freeze

  # Build the display-name -> path map by walking every tree in precedence order.
  def build_map(trees = TREES)
    trees.each_with_object({}) do |tree, map|
      project_dirs(tree).each { |dir| map[key_for(dir, tree[:depth])] = dir }
    end
  end

  # Build the display-name -> type map, walking trees in the same precedence
  # order as build_map so a collision's type matches its winning path.
  def build_types(trees = TREES)
    trees.each_with_object({}) do |tree, types|
      project_dirs(tree).each { |dir| types[key_for(dir, tree[:depth])] = tree[:type] }
    end
  end

  # The order `ls` and tab-completion present project groups in; mirrors the
  # group-order zstyle in zsh/projects.zsh so the two stay consistent.
  TYPE_ORDER = %w[personal client opensource].freeze

  # Group project keys by type for `ls`: TYPE_ORDER first, any unrecognised type
  # after (sorted), keys sorted within each group. Returns [[type, [keys]], ...]
  # with empty groups dropped, so the caller just prints what it is handed.
  def group_by_type(keys, types, order = TYPE_ORDER)
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
  def root_from_pwd(pwd, trees = TREES)
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
                   sys: nil, home: Dir.home, confirm: ->(_) { false }, jotter: ->(*) {})
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
    def cmd_ls(map, types, tags, args)
      filter = Proj.parse_ls_args(args)
      keys = map.keys

      if (type = filter[:type])
        known = (Proj::TYPE_ORDER & types.values) | types.values.uniq.sort
        return error("proj ls: no such type '#{type}' (known: #{known.join(', ')})") unless known.include?(type)

        keys = keys.select { |key| types[key] == type }
      end

      unless filter[:tags].empty?
        keys = keys.select { |key| (filter[:tags] - (tags[key] || [])).empty? }
      end

      Proj.group_by_type(keys, types).each_with_index do |(type, group_keys), i|
        @out.puts "" unless i.zero?
        @out.puts type
        group_keys.each { |key| @out.puts Proj.format_ls_row(key, tags[key]) }
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
      migrate_jotter_logs(old_name, new, new_path)
      change_dir(new_path + @pwd[old_path.length..]) if @pwd == old_path || @pwd.start_with?("#{old_path}/")
      0
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
    trees: Proj::TREES,
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
