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

module Proj
  module_function

  PROJ_DIR = ENV.fetch("PROJ_DIR", File.join(Dir.home, "Tech/Projects/personal"))
  CLIENT_DIR = ENV.fetch("CLIENT_DIR", File.join(Dir.home, "Tech/Projects/client"))
  OPENSOURCE_DIR = ENV.fetch("OPENSOURCE_DIR", File.join(Dir.home, "Tech/Projects/opensource"))

  # Each tree is one searchable root. `depth` is how many path segments below
  # `dir` form a project: 1 keys projects by basename (`cadence`), 2 keys them
  # namespaced (`nesta/asf_visit_a_heat_pump`). `exclude` drops any project
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
  # against namespaced keys, so `nest/heat` resolves
  # `nesta/asf_visit_a_heat_pump`. Returns an array (0, 1, or many). Exact
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
    def initialize(trees:, pwd:, out:, err:, cd:, cache:, paths: ->(_) {}, types: ->(_) {}, worktree: nil)
      @trees = trees
      @pwd = pwd
      @out = out
      @err = err
      @cd = cd
      @cache = cache
      @paths = paths
      @types = types
      @worktree = worktree
    end

    def run(argv)
      name = argv[0]
      worktree = argv[1]
      root = Proj.root_from_pwd(@pwd, @trees)

      return goto_current_root(root) if name == "."

      map = Proj.build_map(@trees)
      @cache.call(map.keys.sort)
      @paths.call(map)
      @types.call(Proj.build_types(@trees))

      return 0 if name == "--list"
      return print_current_or_list(root, map) if name.nil? || name.empty?

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

    def print_current_or_list(root, map)
      if root
        @out.puts root
        return 0
      end

      @out.puts "Usage: proj <name>"
      @out.puts ""
      map.keys.sort.each { |k| @out.puts k }
      1
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

  app = Proj::App.new(
    trees: Proj::TREES,
    pwd: ENV.fetch("PWD", Dir.pwd),
    out: $stdout,
    err: $stderr,
    cd: cd_sink,
    cache: cache_sink,
    paths: paths_sink,
    types: types_sink,
    worktree: worktree_sink
  )

  exit app.run(ARGV)
end
