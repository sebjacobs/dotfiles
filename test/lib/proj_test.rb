#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "open3"
ScriptTest.load_script("../lib/proj.rb")

class ProjPureTest < Minitest::Test
  def test_fuzzy_match_prefers_prefix_over_substring
    assert_equal %w[foobar foo-baz], Proj.fuzzy_match(%w[foobar foo-baz my-foo other], "foo")
  end

  def test_fuzzy_match_falls_back_to_substring
    assert_equal %w[my-foo-wt], Proj.fuzzy_match(%w[my-foo-wt other], "foo")
  end

  def test_fuzzy_match_returns_empty_when_nothing_matches
    assert_empty Proj.fuzzy_match(%w[alpha beta], "zzz")
  end

  def test_fuzzy_match_namespaced_matches_each_segment_by_prefix
    keys = ["acme/widget-tracker", "acme/other", "globex/dashboard"]
    assert_equal ["acme/widget-tracker"], Proj.fuzzy_match(keys, "acm/wid")
  end

  def test_fuzzy_match_namespaced_falls_back_to_substring_segments
    keys = ["acme/widget-tracker", "globex/dashboard"]
    assert_equal ["acme/widget-tracker"], Proj.fuzzy_match(keys, "cme/track")
  end

  def test_fuzzy_match_namespaced_ignores_flat_keys
    keys = ["widget-tool", "acme/widget"]
    assert_equal ["acme/widget"], Proj.fuzzy_match(keys, "a/widget")
  end

  def test_descend_returns_remainder_for_strict_descendant
    assert_equal "cadence/sub", Proj.descend("/root/personal/cadence/sub", "/root/personal")
  end

  def test_descend_returns_nil_for_equal_path
    assert_nil Proj.descend("/root/personal", "/root/personal")
  end

  def test_descend_returns_nil_for_prefix_sibling
    assert_nil Proj.descend("/root/personal-archive/x", "/root/personal")
  end

  def test_key_for_uses_basename_at_depth_one
    assert_equal "cadence", Proj.key_for("/root/personal/cadence", 1)
  end

  def test_key_for_namespaces_at_depth_two
    assert_equal "acme/widget", Proj.key_for("/root/client/acme/widget", 2)
  end

  def test_group_by_type_orders_personal_then_client_then_opensource
    keys = %w[ripgrep cadence acme/widget dotfiles]
    types = { "ripgrep" => "opensource", "cadence" => "personal",
              "acme/widget" => "client", "dotfiles" => "personal" }
    assert_equal(
      [["personal", %w[cadence dotfiles]], ["client", ["acme/widget"]], ["opensource", ["ripgrep"]]],
      Proj.group_by_type(keys, types, %w[personal client opensource])
    )
  end

  def test_group_by_type_drops_absent_groups
    assert_equal [["personal", ["cadence"]]],
                 Proj.group_by_type(%w[cadence], { "cadence" => "personal" }, %w[personal client])
  end

  def test_group_by_type_appends_unknown_types_sorted_last
    keys = %w[a b c]
    types = { "a" => "personal", "b" => "zeta", "c" => "alpha" }
    assert_equal [["personal", ["a"]], ["alpha", ["c"]], ["zeta", ["b"]]],
                 Proj.group_by_type(keys, types, %w[personal])
  end

  def test_parse_proj_file_reads_key_values_skipping_comments_and_blanks
    content = "# a comment\n\ntags: archived, billable\ndescription: a tool\n"
    assert_equal({ "tags" => "archived, billable", "description" => "a tool" },
                 Proj.parse_proj_file(content))
  end

  def test_parse_proj_file_ignores_lines_without_a_colon
    assert_equal({}, Proj.parse_proj_file("not a config line\n"))
  end

  def test_tags_for_splits_on_commas_and_whitespace
    assert_equal %w[archived billable wip], Proj.tags_for("tags: archived, billable wip\n")
  end

  def test_tags_for_is_empty_without_a_tags_line
    assert_empty Proj.tags_for("description: x\n")
    assert_empty Proj.tags_for("")
  end

  def test_parse_ls_args_takes_lone_positional_as_type
    assert_equal({ type: "personal", tags: [] }, Proj.parse_ls_args(["personal"]))
  end

  def test_parse_ls_args_collects_repeated_tag_flags
    assert_equal({ type: nil, tags: %w[archived billable] },
                 Proj.parse_ls_args(["--tag", "archived", "--tag", "billable"]))
  end

  def test_parse_ls_args_accepts_equals_and_comma_joined_tags
    assert_equal({ type: nil, tags: %w[a b c] }, Proj.parse_ls_args(["--tag=a,b", "--tag", "c"]))
  end

  def test_parse_ls_args_combines_type_and_tags
    assert_equal({ type: "client", tags: %w[archived] },
                 Proj.parse_ls_args(["client", "--tag", "archived"]))
  end

  def test_format_ls_row_bare_when_untagged
    assert_equal "  cadence", Proj.format_ls_row("cadence", [])
    assert_equal "  cadence", Proj.format_ls_row("cadence", nil)
  end

  def test_format_ls_row_appends_tags_when_present
    assert_equal "  cadence                      [archived billable]",
                 Proj.format_ls_row("cadence", %w[archived billable])
  end

  def test_parse_manifest_derives_type_and_depth_from_a_bare_line
    trees = Proj.parse_manifest("personal\n", "/root")
    assert_equal [{ dir: "/root/personal", depth: 1, type: "personal", exclude: ["ARCHIVE"] }], trees
  end

  def test_parse_manifest_honors_depth_and_type_overrides
    trees = Proj.parse_manifest("client depth=2\nfoo type=bar\n", "/root")
    assert_equal "/root/client", trees[0][:dir]
    assert_equal 2, trees[0][:depth]
    assert_equal "client", trees[0][:type]
    assert_equal "bar", trees[1][:type]
  end

  def test_parse_manifest_types_a_nested_dir_by_its_last_segment
    trees = Proj.parse_manifest("personal/PRIVATE\n", "/root")
    assert_equal "/root/personal/PRIVATE", trees[0][:dir]
    assert_equal "PRIVATE", trees[0][:type]
  end

  def test_parse_manifest_skips_comments_and_blank_lines
    trees = Proj.parse_manifest("# a comment\n\npersonal\n", "/root")
    assert_equal 1, trees.length
    assert_equal "personal", trees[0][:type]
  end

  def test_parse_manifest_preserves_line_order
    trees = Proj.parse_manifest("personal\nclient\nopensource\n", "/root")
    assert_equal %w[personal client opensource], trees.map { |t| t[:type] }
  end

  def test_parse_manifest_excludes_a_nested_category_from_its_parent
    trees = Proj.parse_manifest("personal\npersonal/PRIVATE type=private\n", "/root")
    personal = trees.find { |t| t[:type] == "personal" }
    assert_includes personal[:exclude], "PRIVATE"
    refute_includes trees.find { |t| t[:type] == "private" }[:exclude], "PRIVATE"
  end
end

class ProjLoadTreesTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@root, "personal"))
    FileUtils.mkdir_p(File.join(@root, "client"))
    FileUtils.mkdir_p(File.join(@root, "temp-backups"))
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_load_trees_reads_the_manifest_when_present
    File.write(File.join(@root, ".projroot"), "personal\nclient depth=2\n")
    trees = Proj.load_trees(@root)
    assert_equal %w[personal client], trees.map { |t| t[:type] }
    assert_equal 2, trees.find { |t| t[:type] == "client" }[:depth]
  end

  def test_load_trees_ignores_undeclared_dirs_under_an_allowlist_manifest
    File.write(File.join(@root, ".projroot"), "personal\n")
    trees = Proj.load_trees(@root)
    refute_includes trees.map { |t| t[:type] }, "temp-backups"
  end

  def test_load_trees_falls_back_to_scanning_top_level_dirs_without_a_manifest
    trees = Proj.load_trees(@root)
    assert_equal %w[client personal temp-backups], trees.map { |t| t[:type] }.sort
    assert(trees.all? { |t| t[:depth] == 1 })
  end
end

class ProjTreeTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @personal = File.join(@root, "personal")
    @client = File.join(@root, "client")
    @opensource = File.join(@root, "opensource")

    mkdirs(
      "personal/cadence",
      "personal/session-logs",
      "personal/ARCHIVE/old",
      "personal/PRIVATE/session-logs",
      "personal/PRIVATE/secret",
      "client/acme/widget-tracker",
      "client/ARCHIVE/x",
      "client/acme/ARCHIVE",
      "opensource/ripgrep"
    )

    @trees = Proj.parse_manifest(<<~MANIFEST, @root)
      personal
      personal/PRIVATE type=private
      client depth=2
      opensource
    MANIFEST
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_build_map_keys_each_tree
    map = Proj.build_map(@trees)

    assert_equal File.join(@personal, "cadence"), map["cadence"]
    assert_equal File.join(@client, "acme/widget-tracker"), map["acme/widget-tracker"]
    assert_equal File.join(@opensource, "ripgrep"), map["ripgrep"]
  end

  def test_build_map_private_wins_collision_over_personal
    map = Proj.build_map(@trees)
    assert_equal File.join(@personal, "PRIVATE/session-logs"), map["session-logs"]
  end

  def test_build_types_labels_each_tree
    types = Proj.build_types(@trees)

    assert_equal "personal", types["cadence"]
    assert_equal "private", types["secret"]
    assert_equal "client", types["acme/widget-tracker"]
    assert_equal "opensource", types["ripgrep"]
  end

  def test_build_map_exposes_private_only_projects
    map = Proj.build_map(@trees)
    assert_equal File.join(@personal, "PRIVATE/secret"), map["secret"]
  end

  def test_build_tags_reads_each_projects_proj_file
    File.write(File.join(@personal, "cadence", ".proj"), "tags: archived, billable\n")
    tags = Proj.build_tags(Proj.build_map(@trees))
    assert_equal %w[archived billable], tags["cadence"]
    assert_empty tags["ripgrep"]
  end

  def test_build_map_skips_archive_everywhere
    keys = Proj.build_map(@trees).keys
    refute_includes keys, "ARCHIVE"
    refute_includes keys, "acme/ARCHIVE"
  end

  def test_root_from_pwd_personal
    pwd = File.join(@personal, "cadence/lib")
    assert_equal File.join(@personal, "cadence"), Proj.root_from_pwd(pwd, @trees)
  end

  def test_root_from_pwd_private
    pwd = File.join(@personal, "PRIVATE/secret/notes")
    assert_equal File.join(@personal, "PRIVATE/secret"), Proj.root_from_pwd(pwd, @trees)
  end

  def test_root_from_pwd_client
    pwd = File.join(@client, "acme/widget-tracker/app")
    assert_equal File.join(@client, "acme/widget-tracker"), Proj.root_from_pwd(pwd, @trees)
  end

  def test_root_from_pwd_returns_nil_outside_trees
    assert_nil Proj.root_from_pwd("/somewhere/else", @trees)
  end

  def test_root_from_pwd_returns_nil_in_archive
    pwd = File.join(@personal, "ARCHIVE/old")
    assert_nil Proj.root_from_pwd(pwd, @trees)
  end

  private

  def mkdirs(*rels)
    rels.each { |rel| FileUtils.mkdir_p(File.join(@root, rel)) }
  end
end

class ProjAppTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @personal = File.join(@root, "personal")
    FileUtils.mkdir_p(File.join(@personal, "cadence"))
    FileUtils.mkdir_p(File.join(@personal, "cadence-extra"))
    @trees = [{ dir: @personal, depth: 1, exclude: ["ARCHIVE"], type: "personal" }]
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_exact_match_cds
    app, cd, _out, _err = build_app(pwd: @root)
    assert_equal 0, app.run(["cadence"])
    assert_equal [File.join(@personal, "cadence")], cd
  end

  def test_unique_fuzzy_match_cds
    FileUtils.rm_rf(File.join(@personal, "cadence-extra"))
    app, cd, = build_app(pwd: @root)
    assert_equal 0, app.run(["cad"])
    assert_equal [File.join(@personal, "cadence")], cd
  end

  def test_ambiguous_match_lists_and_fails
    app, cd, _out, err = build_app(pwd: @root)
    assert_equal 1, app.run(["cad"])
    assert_empty cd
    assert_includes err.string, "Multiple projects match 'cad'"
  end

  def test_no_match_fails
    app, cd, _out, err = build_app(pwd: @root)
    assert_equal 1, app.run(["zzz"])
    assert_empty cd
    assert_includes err.string, "No project matching: zzz"
  end

  def test_dot_cds_to_current_root
    app, cd, = build_app(pwd: File.join(@personal, "cadence", "lib"))
    assert_equal 0, app.run(["."])
    assert_equal [File.join(@personal, "cadence")], cd
  end

  def test_dot_outside_tree_fails
    app, cd, _out, err = build_app(pwd: "/elsewhere")
    assert_equal 1, app.run(["."])
    assert_empty cd
    assert_includes err.string, "not inside a known project tree"
  end

  def test_bare_inside_project_prints_root
    app, _cd, out = build_app(pwd: File.join(@personal, "cadence", "lib"))
    assert_equal 0, app.run([])
    assert_equal "#{File.join(@personal, 'cadence')}\n", out.string
  end

  def test_bare_outside_project_lists_grouped
    app, _cd, out = build_app(pwd: @root)
    assert_equal 0, app.run([])
    assert_equal "personal\n  cadence\n  cadence-extra\n", out.string
  end

  def test_ls_lists_projects_grouped_by_type
    app, _cd, out = build_app(pwd: @root)
    assert_equal 0, app.run(["ls"])
    assert_equal "personal\n  cadence\n  cadence-extra\n", out.string
  end

  def test_ls_filters_to_a_single_type
    app, _cd, out = build_app(pwd: @root)
    assert_equal 0, app.run(["ls", "personal"])
    assert_equal "personal\n  cadence\n  cadence-extra\n", out.string
  end

  def test_ls_rejects_an_unknown_type
    app, _cd, _out, err = build_app(pwd: @root)
    assert_equal 1, app.run(["ls", "client"])
    assert_includes err.string, "no such type 'client'"
    assert_includes err.string, "known: personal"
  end

  def test_ls_groups_multiple_types_in_order
    with_typed_app do |app, out|
      assert_equal 0, app.run(["ls"])
      assert_equal "personal\n  cadence\n\nclient\n  acme/widget\n\nopensource\n  ripgrep\n", out.string
    end
  end

  def test_ls_filter_narrows_to_one_group
    with_typed_app do |app, out|
      assert_equal 0, app.run(["ls", "client"])
      assert_equal "client\n  acme/widget\n", out.string
    end
  end

  def test_ls_shows_tags_inline
    with_tagged_app do |app, out|
      assert_equal 0, app.run(["ls"])
      assert_includes out.string, Proj.format_ls_row("old-thing", ["archived"])
      assert_includes out.string, Proj.format_ls_row("acme/widget", %w[archived billable])
      assert_includes out.string, "  cadence\n"
    end
  end

  def test_ls_filters_by_tag_across_types
    with_tagged_app do |app, out|
      assert_equal 0, app.run(["ls", "--tag", "archived"])
      assert_includes out.string, "old-thing"
      assert_includes out.string, "acme/widget"
      refute_includes out.string, "cadence"
      refute_includes out.string, "ripgrep"
    end
  end

  def test_ls_multiple_tags_require_all
    with_tagged_app do |app, out|
      assert_equal 0, app.run(["ls", "--tag", "archived", "--tag", "billable"])
      assert_includes out.string, "acme/widget"
      refute_includes out.string, "old-thing"
    end
  end

  def test_ls_combines_type_positional_with_tag_flag
    with_tagged_app do |app, out|
      assert_equal 0, app.run(["ls", "personal", "--tag", "archived"])
      assert_includes out.string, "old-thing"
      refute_includes out.string, "acme/widget"
      refute_includes out.string, "cadence"
    end
  end

  def test_run_invokes_tags_sink_with_the_tag_map
    captured = nil
    app = Proj::App.new(
      trees: @trees, pwd: @root, out: StringIO.new, err: StringIO.new,
      cd: ->(_) {}, cache: ->(_) {}, tags: ->(map) { captured = map }
    )
    app.run(["cadence"])
    assert_equal({ "cadence" => [], "cadence-extra" => [] }, captured)
  end

  def test_run_refreshes_cache
    cached = nil
    app = Proj::App.new(
      trees: @trees, pwd: @root, out: StringIO.new, err: StringIO.new,
      cd: ->(_) {}, cache: ->(keys) { cached = keys }
    )
    app.run(["cadence"])
    assert_equal %w[cadence cadence-extra], cached
  end

  def test_list_only_refreshes_cache_without_cd
    app, cd, out = build_app(pwd: @root)
    assert_equal 0, app.run(["--list"])
    assert_empty cd
    assert_empty out.string
  end

  def test_second_arg_cds_to_project_then_delegates_to_worktree
    app, cd, _out, _err, wt = build_app(pwd: @root)
    assert_equal 0, app.run(["cadence", "feat"])
    assert_equal [File.join(@personal, "cadence")], cd
    assert_equal [[File.join(@personal, "cadence"), "feat"]], wt
  end

  def test_second_arg_returns_worktree_exit_code
    failing = ->(_path, _name) { 1 }
    app, cd, = build_app(pwd: @root, worktree: failing)
    assert_equal 1, app.run(["cadence", "feat"])
    assert_equal [File.join(@personal, "cadence")], cd
  end

  def test_second_arg_resolves_fuzzy_project_before_delegating
    FileUtils.rm_rf(File.join(@personal, "cadence-extra"))
    app, _cd, _out, _err, wt = build_app(pwd: @root)
    assert_equal 0, app.run(["cad", "feat"])
    assert_equal [[File.join(@personal, "cadence"), "feat"]], wt
  end

  def test_second_arg_skips_delegation_on_ambiguous_project
    app, cd, _out, err, wt = build_app(pwd: @root)
    assert_equal 1, app.run(["cad", "feat"])
    assert_empty cd
    assert_empty wt
    assert_includes err.string, "Multiple projects match 'cad'"
  end

  def test_second_arg_skips_delegation_on_unknown_project
    app, _cd, _out, err, wt = build_app(pwd: @root)
    assert_equal 1, app.run(["zzz", "feat"])
    assert_empty wt
    assert_includes err.string, "No project matching: zzz"
  end

  def test_run_writes_name_to_path_mapping
    captured = nil
    app = Proj::App.new(
      trees: @trees, pwd: @root, out: StringIO.new, err: StringIO.new,
      cd: ->(_) {}, cache: ->(_) {}, paths: ->(map) { captured = map }
    )
    app.run(["cadence"])
    assert_equal File.join(@personal, "cadence"), captured["cadence"]
  end

  def test_run_writes_name_to_type_mapping
    captured = nil
    app = Proj::App.new(
      trees: @trees, pwd: @root, out: StringIO.new, err: StringIO.new,
      cd: ->(_) {}, cache: ->(_) {}, types: ->(map) { captured = map }
    )
    app.run(["cadence"])
    assert_equal "personal", captured["cadence"]
  end

  private

  def build_app(pwd:, worktree: nil)
    cd = []
    out = StringIO.new
    err = StringIO.new
    wt_calls = []
    resolver = worktree || ->(path, name) { wt_calls << [path, name]; 0 }
    app = Proj::App.new(
      trees: @trees, pwd: pwd, out: out, err: err,
      cd: ->(path) { cd << path }, cache: ->(_) {}, paths: ->(_) {}, worktree: resolver
    )
    [app, cd, out, err, wt_calls]
  end

  # An app over one project of each type, so `ls` grouping and filtering can be
  # exercised across all three. The tree lives in a tmpdir cleaned up after.
  def with_typed_app
    root = Dir.mktmpdir
    %w[personal/cadence client/acme/widget opensource/ripgrep].each do |rel|
      FileUtils.mkdir_p(File.join(root, rel))
    end
    trees = [
      { dir: File.join(root, "personal"), depth: 1, exclude: [], type: "personal" },
      { dir: File.join(root, "client"), depth: 2, exclude: [], type: "client" },
      { dir: File.join(root, "opensource"), depth: 1, exclude: [], type: "opensource" }
    ]
    out = StringIO.new
    app = Proj::App.new(
      trees: trees, pwd: root, out: out, err: StringIO.new,
      cd: ->(_) {}, cache: ->(_) {}, paths: ->(_) {}, types: ->(_) {}
    )
    yield app, out
  ensure
    FileUtils.remove_entry(root)
  end

  # Like with_typed_app, plus .proj tag files: old-thing is [archived], the
  # client project is [archived billable], cadence/ripgrep are untagged.
  def with_tagged_app
    root = Dir.mktmpdir
    %w[personal/cadence personal/old-thing client/acme/widget opensource/ripgrep].each do |rel|
      FileUtils.mkdir_p(File.join(root, rel))
    end
    File.write(File.join(root, "personal/old-thing/.proj"), "tags: archived\n")
    File.write(File.join(root, "client/acme/widget/.proj"), "tags: archived, billable\n")
    trees = [
      { dir: File.join(root, "personal"), depth: 1, exclude: [], type: "personal" },
      { dir: File.join(root, "client"), depth: 2, exclude: [], type: "client" },
      { dir: File.join(root, "opensource"), depth: 1, exclude: [], type: "opensource" }
    ]
    out = StringIO.new
    app = Proj::App.new(
      trees: trees, pwd: root, out: out, err: StringIO.new,
      cd: ->(_) {}, cache: ->(_) {}, paths: ->(_) {}, types: ->(_) {}, tags: ->(_) {}
    )
    yield app, out
  ensure
    FileUtils.remove_entry(root)
  end
end

class ProjMvTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @home = Dir.mktmpdir
    @personal = File.join(@root, "personal")
    @proj = File.join(@personal, "cadence")
    FileUtils.mkdir_p(@proj)
    FileUtils.mkdir_p(File.join(@personal, "cadence-extra"))
    @trees = [{ dir: @personal, depth: 1, exclude: [], type: "personal" }]
    @projects = File.join(@home, ".claude", "projects")
    FileUtils.mkdir_p(@projects)
    @jotter_calls = []
    @cd = []
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root)
    FileUtils.remove_entry(@home)
  end

  def enc(path) = path.gsub(%r{[/.]}, "-")

  def seed_history(path, file = "s.jsonl")
    dir = File.join(@projects, enc(path))
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, file), "entry")
    dir
  end

  def app(confirm: true)
    Proj::App.new(
      trees: @trees, pwd: @root, out: @out, err: @err,
      cd: ->(p) { @cd << p }, cache: ->(_) {}, paths: ->(_) {}, types: ->(_) {}, tags: ->(_) {},
      home: @home, confirm: ->(_) { confirm }, jotter: ->(o, n, p) { @jotter_calls << [o, n, p] }
    )
  end

  def test_mv_renames_the_directory
    assert_equal 0, app.run(["mv", "cadence", "notes"])
    assert path_exists?(File.join(@personal, "notes"))
    refute path_exists?(@proj)
  end

  def test_mv_migrates_the_projects_claude_history
    seed_history(@proj)
    app.run(["mv", "cadence", "notes"])
    assert path_exists?(File.join(@projects, enc(File.join(@personal, "notes")), "s.jsonl"))
    refute path_exists?(File.join(@projects, enc(@proj)))
  end

  def test_mv_leaves_a_sibling_projects_history_untouched
    seed_history(@proj)
    sibling = seed_history(File.join(@personal, "cadence-extra"))
    app.run(["mv", "cadence", "notes"])
    assert path_exists?(sibling), "sibling cadence-extra history must not be swept along"
  end

  def test_mv_migrates_worktree_history_under_the_project
    wt = File.join(@proj, ".claude", "worktrees", "foo")
    FileUtils.mkdir_p(wt)
    seed_history(wt)
    app.run(["mv", "cadence", "notes"])
    moved = File.join(@projects, enc(File.join(@personal, "notes", ".claude", "worktrees", "foo")))
    assert path_exists?(moved)
  end

  def test_mv_delegates_to_jotter_for_a_git_repo
    FileUtils.mkdir_p(File.join(@proj, ".git"))
    app.run(["mv", "cadence", "notes"])
    assert_equal [["cadence", "notes", File.join(@personal, "notes")]], @jotter_calls
  end

  def test_mv_skips_jotter_for_a_non_git_directory
    app.run(["mv", "cadence", "notes"])
    assert_empty @jotter_calls
  end

  def test_mv_declined_changes_nothing
    seed_history(@proj)
    assert_equal 1, app(confirm: false).run(["mv", "cadence", "notes"])
    assert path_exists?(@proj)
    refute path_exists?(File.join(@personal, "notes"))
    assert_empty @jotter_calls
  end

  def test_mv_cds_into_the_renamed_project_when_inside_it
    inside = app
    inside.instance_variable_set(:@pwd, File.join(@proj, "lib"))
    inside.run(["mv", "cadence", "notes"])
    assert_equal [File.join(@personal, "notes", "/lib")], @cd
  end

  def test_mv_rejects_a_slash_in_the_new_name
    assert_equal 1, app.run(["mv", "cadence", "a/b"])
    assert_match(/single path segment/, @err.string)
    assert path_exists?(@proj)
  end

  def test_mv_rejects_an_existing_target
    FileUtils.mkdir_p(File.join(@personal, "notes"))
    assert_equal 1, app.run(["mv", "cadence", "notes"])
    assert_match(/already exists/, @err.string)
  end

  def test_mv_errors_on_an_unknown_project
    assert_equal 1, app.run(["mv", "nope", "notes"])
    assert_match(/No project matching: nope/, @err.string)
  end

  def test_mv_requires_two_arguments
    assert_equal 1, app.run(["mv", "cadence"])
    assert_match(/Usage: proj mv/, @err.string)
  end

  private

  def path_exists?(path) = File.exist?(path)
end

class ProjDelegationLoadTest < Minitest::Test
  HELPER = File.expand_path("../../lib/proj.rb", __dir__)

  def test_cli_loads_sibling_gwt_helper_without_a_load_error
    Dir.mktmpdir do |empty|
      env = { "PROJ_ROOT" => empty,
              "PROJ_CD_FILE" => "", "PROJ_CACHE_FILE" => "", "PROJ_PATHS_FILE" => "" }
      _out, err, _status = Open3.capture3(env, RbConfig.ruby, HELPER, "no-such-project")
      refute_match(/cannot load such file/, err)
      refute_match(/LoadError/, err)
    end
  end
end
