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

  def test_description_for_reads_and_trims_the_description_line
    assert_equal "Fast, quiet file watcher", Proj.description_for("description:  Fast, quiet file watcher  \n")
  end

  def test_description_for_is_empty_without_a_description_line
    assert_empty Proj.description_for("tags: rust cli\n")
    assert_empty Proj.description_for("")
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

  def test_format_ls_row_appends_tags_after_the_reserved_description_column
    assert_equal "  cadence                                         [archived billable]",
                 Proj.format_ls_row("cadence", %w[archived billable])
  end

  def test_format_ls_row_shows_description_then_tags
    assert_equal "  otter            Fast, quiet file watcher       [rust cli]",
                 Proj.format_ls_row("otter", %w[rust cli], "Fast, quiet file watcher")
  end

  def test_format_ls_row_trims_trailing_padding_when_description_has_no_tags
    assert_equal "  otter            Fast, quiet file watcher",
                 Proj.format_ls_row("otter", [], "Fast, quiet file watcher")
  end

  def test_format_ls_row_bare_when_description_and_tags_both_empty
    assert_equal "  cadence", Proj.format_ls_row("cadence", [], "")
  end

  def test_starred_for_reads_truthy_values
    %w[true yes on 1 TRUE Yes].each do |value|
      assert Proj.starred_for("starred: #{value}\n"), "expected #{value.inspect} to star"
    end
  end

  def test_starred_for_is_false_when_absent_or_falsey
    refute Proj.starred_for("tags: rust\n")
    refute Proj.starred_for("starred: false\n")
    refute Proj.starred_for("starred: nope\n")
    refute Proj.starred_for("")
  end

  def test_colorize_starred_wraps_text_in_yellow
    assert_equal "\e[33m  cadence\e[0m", Proj.colorize_starred("  cadence")
  end

  def test_set_starred_appends_the_flag_to_content_without_one
    assert_equal "description: A tool\nstarred: true\n",
                 Proj.set_starred("description: A tool\n", true)
  end

  def test_set_starred_adds_a_separating_newline_when_content_lacks_one
    assert_equal "description: A tool\nstarred: true\n",
                 Proj.set_starred("description: A tool", true)
  end

  def test_set_starred_on_empty_content_writes_just_the_flag
    assert_equal "starred: true\n", Proj.set_starred("", true)
  end

  def test_set_starred_uncomments_the_template_line
    content = "# tags: a b\n# starred: true\n"
    assert_equal "# tags: a b\nstarred: true\n", Proj.set_starred(content, true)
  end

  def test_set_starred_normalises_an_existing_active_flag
    assert_equal "starred: true\n", Proj.set_starred("starred: yes\n", true)
  end

  def test_set_starred_false_drops_an_active_flag_leaving_the_rest
    assert_equal "tags: rust\n", Proj.set_starred("tags: rust\nstarred: true\n", false)
  end

  def test_set_starred_false_leaves_a_commented_template_untouched
    content = "# starred: true\n"
    assert_equal content, Proj.set_starred(content, false)
  end

  def test_set_starred_is_idempotent_for_the_current_state
    assert_equal "starred: true\n", Proj.set_starred("starred: true\n", true)
    assert_equal "tags: x\n", Proj.set_starred("tags: x\n", false)
  end

  def test_parse_for_each_ref_takes_branch_and_time_from_the_top_line
    assert_equal ["main", 1782571757], Proj.parse_for_each_ref("main\t1782571757\n")
  end

  def test_parse_for_each_ref_reads_only_the_first_line
    assert_equal ["feature", 1782571757],
                 Proj.parse_for_each_ref("feature\t1782571757\nmain\t1782509451\n")
  end

  def test_parse_for_each_ref_returns_nil_for_no_branches
    assert_nil Proj.parse_for_each_ref("")
    assert_nil Proj.parse_for_each_ref("\n")
  end

  def test_sort_recent_orders_newest_first_then_by_name
    entries = [
      { key: "old", branch: "main", time: 100 },
      { key: "new", branch: "main", time: 300 },
      { key: "tie-b", branch: "main", time: 200 },
      { key: "tie-a", branch: "main", time: 200 }
    ]
    assert_equal %w[new tie-a tie-b old], Proj.sort_recent(entries).map { |e| e[:key] }
  end

  def test_format_recent_row_aligns_name_branch_and_timestamp
    assert_equal "cadence                      main                     (last: 2026-06-27 16:23)",
                 Proj.format_recent_row("cadence", "main", "2026-06-27 16:23")
  end

  def test_parse_branches_reads_every_line_flagging_the_checked_out_one
    dump = "*\tmain\t1782571757\n \tfeature\t1782509451\n"
    assert_equal [
      { current: true, branch: "main", time: 1782571757 },
      { current: false, branch: "feature", time: 1782509451 }
    ], Proj.parse_branches(dump)
  end

  def test_parse_branches_skips_malformed_lines_and_empty_input
    assert_empty Proj.parse_branches("")
    assert_empty Proj.parse_branches("\n")
    assert_equal [{ current: false, branch: "main", time: 1782571757 }],
                 Proj.parse_branches("garbage-no-tabs\n \tmain\t1782571757\n")
  end

  def test_format_branch_row_marks_the_current_branch_and_pads
    assert_equal "* main                           (last: 2026-06-27 16:23)",
                 Proj.format_branch_row(true, "main", "2026-06-27 16:23")
    assert_equal "  feature                        (last: 2026-06-27 16:23)",
                 Proj.format_branch_row(false, "feature", "2026-06-27 16:23")
  end

  def test_format_time_renders_local_minute_precision
    ENV["TZ"] = "UTC"
    assert_equal "2026-06-28 04:09", Proj.format_time(1782619757)
  ensure
    ENV.delete("TZ")
  end

  def test_parse_manifest_derives_type_and_depth_from_a_bare_line
    trees = Proj.parse_manifest("personal\n", "/root")
    assert_equal [{ dir: "/root/personal", depth: 1, type: "personal", exclude: ["ARCHIVE", "session-logs"] }], trees
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

  def test_rewrite_manifest_dir_renames_the_matching_line
    content = "personal\nopensource\n"
    assert_equal "personal\nopen-source\n", Proj.rewrite_manifest_dir(content, "opensource", "open-source")
  end

  def test_rewrite_manifest_dir_preserves_the_flags_and_whitespace_verbatim
    content = "client            depth=2\n"
    assert_equal "clients            depth=2\n", Proj.rewrite_manifest_dir(content, "client", "clients")
  end

  def test_rewrite_manifest_dir_renames_a_nested_dir_leaving_others
    content = "personal\npersonal/PRIVATE  type=private\nopensource\n"
    rewritten = Proj.rewrite_manifest_dir(content, "personal/PRIVATE", "personal/SECRET")
    assert_equal "personal\npersonal/SECRET  type=private\nopensource\n", rewritten
  end

  def test_rewrite_manifest_dir_leaves_comments_and_non_matches_untouched
    content = "# opensource is public\npersonal\n"
    assert_equal content, Proj.rewrite_manifest_dir(content, "opensource", "open-source")
  end

  def test_rewrite_manifest_dir_matches_only_the_dir_token_not_a_substring
    content = "opensource-mirror\nopensource\n"
    rewritten = Proj.rewrite_manifest_dir(content, "opensource", "open-source")
    assert_equal "opensource-mirror\nopen-source\n", rewritten
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
      "personal/notes",
      "personal/session-logs",
      "personal/ARCHIVE/old",
      "personal/PRIVATE/notes",
      "personal/PRIVATE/session-logs",
      "personal/PRIVATE/secret",
      "client/acme/widget-tracker",
      "client/acme/session-logs",
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
    assert_equal File.join(@personal, "PRIVATE/notes"), map["notes"]
  end

  def test_build_map_skips_session_logs_everywhere
    keys = Proj.build_map(@trees).keys
    refute_includes keys, "session-logs"
    refute_includes keys, "acme/session-logs"
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

  def test_build_starred_reads_each_projects_proj_file
    File.write(File.join(@personal, "cadence", ".proj"), "starred: true\n")
    starred = Proj.build_starred(Proj.build_map(@trees))
    assert starred["cadence"]
    refute starred["ripgrep"]
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

  def test_help_prints_usage_without_cding
    ["help", "-h", "--help"].each do |flag|
      app, cd, out = build_app(pwd: @root)
      assert_equal 0, app.run([flag])
      assert_empty cd
      assert_includes out.string, "Usage: proj <name>"
    end
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

  def test_cd_into_a_category_root
    app, cd = build_categorised_app(pwd: @root)
    assert_equal 0, app.run(["cd", "personal"])
    assert_equal [@personal], cd
  end

  def test_cd_into_a_nested_category_by_type
    app, cd = build_categorised_app(pwd: @root)
    assert_equal 0, app.run(["cd", "private"])
    assert_equal [File.join(@personal, "PRIVATE")], cd
  end

  def test_cd_resolves_a_category_by_dir_basename
    app, cd = build_categorised_app(pwd: @root)
    assert_equal 0, app.run(["cd", "client"])
    assert_equal [File.join(@root, "client")], cd
  end

  def test_cd_unknown_category_fails
    app, cd, _out, err = build_categorised_app(pwd: @root)
    assert_equal 1, app.run(["cd", "nope"])
    assert_empty cd
    assert_includes err.string, "unknown category 'nope'"
    assert_includes err.string, "personal, private, client"
  end

  def test_cd_without_a_category_prints_usage
    app, cd, _out, err = build_categorised_app(pwd: @root)
    assert_equal 1, app.run(["cd"])
    assert_empty cd
    assert_includes err.string, "Usage: proj cd <category>"
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

  def test_run_invokes_starred_sink_with_the_starred_map
    File.write(File.join(@personal, "cadence", ".proj"), "starred: true\n")
    captured = nil
    app = Proj::App.new(
      trees: @trees, pwd: @root, out: StringIO.new, err: StringIO.new,
      cd: ->(_) {}, cache: ->(_) {}, starred: ->(map) { captured = map }
    )
    app.run(["cadence"])
    assert_equal({ "cadence" => true, "cadence-extra" => false }, captured)
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

  def test_status_lists_git_projects_newest_first_with_branch_and_time
    cadence = File.join(@personal, "cadence")
    extra = File.join(@personal, "cadence-extra")
    git = FakeGit.new(cadence => ["main\t1782509451\n", true],
                      extra => ["feature\t1782571757\n", true])
    app, _cd, out = build_app(pwd: @root, git: git)
    assert_equal 0, app.run(["status"])
    expected = [
      Proj.format_recent_row("cadence-extra", "feature", Proj.format_time(1782571757)),
      Proj.format_recent_row("cadence", "main", Proj.format_time(1782509451))
    ].join("\n") + "\n"
    assert_equal expected, out.string
  end

  def test_status_skips_non_git_and_commitless_projects
    cadence = File.join(@personal, "cadence")
    extra = File.join(@personal, "cadence-extra")
    git = FakeGit.new(cadence => ["main\t1782509451\n", true],
                      extra => ["", false])
    app, _cd, out = build_app(pwd: @root, git: git)
    assert_equal 0, app.run(["status"])
    assert_includes out.string, "cadence "
    refute_includes out.string, "cadence-extra"
  end

  def test_branches_lists_the_current_projects_branches_marking_the_checked_out_one
    cadence = File.join(@personal, "cadence")
    dump = "*\tmain\t1782571757\n \tfeature\t1782509451\n"
    git = FakeGit.new(cadence => [dump, true])
    app, _cd, out = build_app(pwd: cadence, git: git)
    assert_equal 0, app.run(["branches"])
    expected = [
      Proj.format_branch_row(true, "main", Proj.format_time(1782571757)),
      Proj.format_branch_row(false, "feature", Proj.format_time(1782509451))
    ].join("\n") + "\n"
    assert_equal expected, out.string
  end

  def test_branches_errors_outside_a_known_project_tree
    app, _cd, _out, err = build_app(pwd: @root, git: FakeGit.new({}))
    assert_equal 1, app.run(["branches"])
    assert_includes err.string, "not inside a known project tree"
  end

  def test_branches_errors_on_a_non_git_project
    cadence = File.join(@personal, "cadence")
    app, _cd, _out, err = build_app(pwd: cadence, git: FakeGit.new(cadence => ["", false]))
    assert_equal 1, app.run(["branches"])
    assert_includes err.string, "not a git repository"
  end

  def test_branches_errors_on_a_commitless_repo
    cadence = File.join(@personal, "cadence")
    app, _cd, _out, err = build_app(pwd: cadence, git: FakeGit.new(cadence => ["", true]))
    assert_equal 1, app.run(["branches"])
    assert_includes err.string, "no branches yet"
  end

  def test_ls_shows_description_inline
    cadence = File.join(@personal, "cadence")
    File.write(File.join(cadence, ".proj"), "description: Task scheduler\ntags: ruby\n")
    app, _cd, out = build_app(pwd: @root)
    assert_equal 0, app.run(["ls"])
    assert_includes out.string, Proj.format_ls_row("cadence", ["ruby"], "Task scheduler")
  end

  def test_ls_colors_starred_projects_yellow_on_a_tty
    File.write(File.join(@personal, "cadence", ".proj"), "starred: true\n")
    out = TTYStringIO.new
    app = Proj::App.new(
      trees: @trees, pwd: @root, out: out, err: StringIO.new,
      cd: ->(_) {}, cache: ->(_) {}
    )
    assert_equal 0, app.run(["ls"])
    assert_includes out.string, Proj.colorize_starred(Proj.format_ls_row("cadence", [], ""))
    assert_includes out.string, "\n  cadence-extra\n"
  end

  def test_ls_leaves_starred_rows_plain_when_not_a_tty
    File.write(File.join(@personal, "cadence", ".proj"), "starred: true\n")
    app, _cd, out = build_app(pwd: @root)
    assert_equal 0, app.run(["ls"])
    refute_includes out.string, "\e[33m"
  end

  def test_show_marks_a_starred_project
    File.write(File.join(@personal, "cadence", ".proj"), "starred: true\n")
    app, _cd, out = build_app(pwd: @root, git: FakeGit.new({}))
    assert_equal 0, app.run(["show", "cadence"])
    assert_includes out.string, "★ starred"
  end

  def test_show_omits_the_star_for_an_unstarred_project
    app, _cd, out = build_app(pwd: @root, git: FakeGit.new({}))
    assert_equal 0, app.run(["show", "cadence"])
    refute_includes out.string, "★"
  end

  def test_show_displays_metadata_and_last_commit
    cadence = File.join(@personal, "cadence")
    File.write(File.join(cadence, ".proj"), "description: Task scheduler\ntags: ruby cli\n")
    git = FakeGit.new(cadence => ["main\t1782509451\n", true])
    app, _cd, out = build_app(pwd: @root, git: git)
    assert_equal 0, app.run(["show", "cadence"])
    assert_includes out.string, "cadence  (personal)"
    assert_includes out.string, cadence
    assert_includes out.string, "Task scheduler"
    assert_includes out.string, "tags: ruby cli"
    assert_includes out.string, "last: main (#{Proj.format_time(1782509451)})"
  end

  def test_show_omits_absent_description_tags_and_commit
    app, _cd, out = build_app(pwd: @root, git: FakeGit.new({}))
    assert_equal 0, app.run(["show", "cadence"])
    assert_includes out.string, "cadence  (personal)"
    refute_includes out.string, "tags:"
    refute_includes out.string, "last:"
  end

  def test_show_requires_a_project_argument
    app, _cd, _out, err = build_app(pwd: @root, git: FakeGit.new({}))
    assert_equal 1, app.run(["show"])
    assert_includes err.string, "Usage: proj show"
  end

  def test_init_writes_a_commented_out_proj_at_the_project_root
    app, _cd, out = build_app(pwd: File.join(@personal, "cadence", "lib"))
    assert_equal 0, app.run(["init"])
    path = File.join(@personal, "cadence", ".proj")
    content = File.read(path)
    assert_includes content, "# description:"
    assert_includes content, "# tags:"
    assert_includes content, "# starred:"
    assert_empty Proj.parse_proj_file(content)
    assert_includes out.string, path
  end

  def test_init_refuses_outside_a_known_project_tree
    app, _cd, _out, err = build_app(pwd: "/elsewhere")
    assert_equal 1, app.run(["init"])
    assert_includes err.string, "not inside a known project tree"
  end

  def test_init_refuses_to_clobber_an_existing_proj
    cadence = File.join(@personal, "cadence")
    File.write(File.join(cadence, ".proj"), "tags: x\n")
    app, _cd, _out, err = build_app(pwd: cadence)
    assert_equal 1, app.run(["init"])
    assert_includes err.string, "already exists"
  end

  def test_star_creates_a_proj_for_the_current_project
    app, _cd, out = build_app(pwd: File.join(@personal, "cadence", "lib"))
    assert_equal 0, app.run(["star"])
    assert_equal "starred: true\n", File.read(File.join(@personal, "cadence", ".proj"))
    assert_includes out.string, "starred cadence"
  end

  def test_star_a_named_project_from_outside_it
    app, _cd, out = build_app(pwd: @root)
    assert_equal 0, app.run(["star", "cadence"])
    assert Proj.starred_for(File.read(File.join(@personal, "cadence", ".proj")))
    assert_includes out.string, "starred cadence"
  end

  def test_star_leaves_existing_metadata_intact
    cadence = File.join(@personal, "cadence")
    File.write(File.join(cadence, ".proj"), "description: A tool\ntags: ruby\n")
    app, = build_app(pwd: cadence)
    assert_equal 0, app.run(["star"])
    content = File.read(File.join(cadence, ".proj"))
    assert_includes content, "description: A tool"
    assert_includes content, "tags: ruby"
    assert Proj.starred_for(content)
  end

  def test_unstar_clears_the_flag_but_keeps_the_file
    cadence = File.join(@personal, "cadence")
    File.write(File.join(cadence, ".proj"), "tags: ruby\nstarred: true\n")
    app, _cd, out = build_app(pwd: cadence)
    assert_equal 0, app.run(["unstar"])
    content = File.read(File.join(cadence, ".proj"))
    refute Proj.starred_for(content)
    assert_includes content, "tags: ruby"
    assert_includes out.string, "unstarred cadence"
  end

  def test_unstar_an_unstarred_project_makes_no_proj_file
    cadence = File.join(@personal, "cadence")
    app, _cd, out = build_app(pwd: cadence)
    assert_equal 0, app.run(["unstar"])
    refute File.exist?(File.join(cadence, ".proj"))
    assert_includes out.string, "already unstarred"
  end

  def test_star_a_missing_project_fails
    app, _cd, _out, err = build_app(pwd: @root)
    assert_equal 1, app.run(["star", "zzz"])
    assert_includes err.string, "No project matching: zzz"
  end

  def test_star_outside_a_tree_without_a_name_fails
    app, _cd, _out, err = build_app(pwd: "/elsewhere")
    assert_equal 1, app.run(["star"])
    assert_includes err.string, "not inside a known project tree"
  end

  class FakeGit
    def initialize(by_dir) = @by_dir = by_dir

    def capture(*args, **) = @by_dir.fetch(args[1], ["", false])
  end

  # A StringIO that claims to be a terminal, so cmd_ls's tty-gated colouring of
  # starred rows fires under test (a plain StringIO reports tty? false).
  class TTYStringIO < StringIO
    def tty? = true
  end

  def build_app(pwd:, worktree: nil, git: nil)
    cd = []
    out = StringIO.new
    err = StringIO.new
    wt_calls = []
    resolver = worktree || ->(path, name) { wt_calls << [path, name]; 0 }
    app = Proj::App.new(
      trees: @trees, pwd: pwd, out: out, err: err,
      cd: ->(path) { cd << path }, cache: ->(_) {}, paths: ->(_) {}, worktree: resolver, git: git
    )
    [app, cd, out, err, wt_calls]
  end

  # An app over the three category shapes `proj cd` must resolve — a plain
  # depth-1 tree (personal), a nested one typed apart from its dir (private under
  # personal/PRIVATE), and a depth-2 namespaced one (client) — so a category
  # jump is exercised by type, by nesting, and by dir basename.
  def build_categorised_app(pwd:)
    cd = []
    out = StringIO.new
    err = StringIO.new
    trees = [
      { dir: @personal, depth: 1, exclude: ["ARCHIVE"], type: "personal" },
      { dir: File.join(@personal, "PRIVATE"), depth: 1, exclude: ["ARCHIVE"], type: "private" },
      { dir: File.join(@root, "client"), depth: 2, exclude: ["ARCHIVE"], type: "client" }
    ]
    app = Proj::App.new(
      trees: trees, pwd: pwd, out: out, err: err,
      cd: ->(path) { cd << path }, cache: ->(_) {}, paths: ->(_) {}
    )
    [app, cd, out, err]
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
    @client = File.join(@root, "client")
    @opensource = File.join(@root, "opensource")
    @proj = File.join(@personal, "cadence")
    @client_proj = File.join(@client, "acme", "widget")
    FileUtils.mkdir_p(@proj)
    FileUtils.mkdir_p(File.join(@personal, "cadence-extra"))
    FileUtils.mkdir_p(@client_proj)
    FileUtils.mkdir_p(@opensource)
    @trees = [
      { dir: @personal, depth: 1, exclude: [], type: "personal" },
      { dir: @client, depth: 2, exclude: [], type: "client" },
      { dir: @opensource, depth: 1, exclude: [], type: "opensource" },
    ]
    @projects = File.join(@home, ".claude", "projects")
    FileUtils.mkdir_p(@projects)
    @manifest = File.join(@root, ".projroot")
    File.write(@manifest, "personal\nclient  depth=2\nopensource\n")
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

  def app(confirm: true, git: nil, pwd: @root)
    Proj::App.new(
      trees: @trees, pwd: pwd, out: @out, err: @err,
      cd: ->(p) { @cd << p }, cache: ->(_) {}, paths: ->(_) {}, types: ->(_) {}, tags: ->(_) {},
      home: @home, confirm: ->(_) { confirm }, jotter: ->(o, n, from, p) { @jotter_calls << [o, n, from, p] },
      git: git, manifest: @manifest
    )
  end

  class RecordingGit
    attr_reader :calls

    def initialize = @calls = []
    def run(*args) = (@calls << args) && true
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

  def test_mv_repairs_worktree_registrations_for_a_git_repo
    FileUtils.mkdir_p(File.join(@proj, ".git"))
    FileUtils.mkdir_p(File.join(@proj, ".claude", "worktrees", "foo"))
    git = RecordingGit.new
    app(git: git).run(["mv", "cadence", "notes"])
    new_root = File.join(@personal, "notes")
    assert_equal [["-C", new_root, "worktree", "repair", File.join(new_root, ".claude", "worktrees", "foo")]],
                 git.calls
  end

  def test_mv_skips_repair_when_the_project_has_no_worktrees
    FileUtils.mkdir_p(File.join(@proj, ".git"))
    git = RecordingGit.new
    app(git: git).run(["mv", "cadence", "notes"])
    assert_empty git.calls
  end

  def test_mv_skips_repair_for_a_non_git_directory
    FileUtils.mkdir_p(File.join(@proj, ".claude", "worktrees", "foo"))
    git = RecordingGit.new
    app(git: git).run(["mv", "cadence", "notes"])
    assert_empty git.calls
  end

  def test_mv_delegates_to_jotter_for_a_git_repo
    FileUtils.mkdir_p(File.join(@proj, ".git"))
    app.run(["mv", "cadence", "notes"])
    assert_equal [["cadence", "notes", nil, File.join(@personal, "notes")]], @jotter_calls
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

  def test_mv_to_moves_into_another_category_keeping_the_name
    assert_equal 0, app.run(["mv", "widget", "--to", "personal"])
    assert path_exists?(File.join(@personal, "widget"))
    refute path_exists?(@client_proj)
  end

  def test_mv_to_renames_while_moving_into_another_category
    assert_equal 0, app.run(["mv", "cadence", "renamed", "--to", "opensource"])
    assert path_exists?(File.join(@opensource, "renamed"))
    refute path_exists?(@proj)
  end

  def test_mv_to_accepts_an_equals_form
    assert_equal 0, app.run(["mv", "cadence", "--to=opensource"])
    assert path_exists?(File.join(@opensource, "cadence"))
  end

  def test_mv_to_a_namespaced_tree_places_under_the_namespace
    assert_equal 0, app.run(["mv", "cadence", "--to", "client/acme"])
    assert path_exists?(File.join(@client, "acme", "cadence"))
  end

  def test_mv_to_rejects_an_unknown_category
    assert_equal 1, app.run(["mv", "cadence", "--to", "nope"])
    assert_match(/unknown destination category 'nope'/, @err.string)
    assert path_exists?(@proj)
  end

  def test_mv_to_rejects_the_wrong_namespace_depth
    assert_equal 1, app.run(["mv", "cadence", "--to", "client"])
    assert_match(/namespace segment/, @err.string)
    assert path_exists?(@proj)
  end

  def test_mv_to_rejects_an_existing_target
    FileUtils.mkdir_p(File.join(@personal, "widget"))
    assert_equal 1, app.run(["mv", "widget", "--to", "personal"])
    assert_match(/already exists/, @err.string)
  end

  def test_mv_to_migrates_claude_history_across_categories
    seed_history(@client_proj)
    app.run(["mv", "widget", "--to", "personal"])
    assert path_exists?(File.join(@projects, enc(File.join(@personal, "widget")), "s.jsonl"))
    refute path_exists?(File.join(@projects, enc(@client_proj)))
  end

  def test_mv_to_passes_the_old_parent_as_from_dir_for_a_git_repo
    FileUtils.mkdir_p(File.join(@client_proj, ".git"))
    app.run(["mv", "widget", "--to", "personal"])
    assert_equal [["widget", "widget", File.join(@client, "acme"), File.join(@personal, "widget")]], @jotter_calls
  end

  def test_mv_to_cds_into_the_moved_project_when_inside_it
    inside = app
    inside.instance_variable_set(:@pwd, File.join(@client_proj, "lib"))
    inside.run(["mv", "widget", "--to", "personal"])
    assert_equal [File.join(@personal, "widget", "/lib")], @cd
  end

  def test_archive_moves_the_project_into_the_archive_folder_keeping_its_name
    assert_equal 0, app.run(["archive", "cadence"])
    assert path_exists?(File.join(@personal, "ARCHIVE", "cadence"))
    refute path_exists?(@proj)
  end

  def test_archive_places_a_namespaced_project_under_its_own_archive_folder
    assert_equal 0, app.run(["archive", "widget"])
    assert path_exists?(File.join(@client, "acme", "ARCHIVE", "widget"))
    refute path_exists?(@client_proj)
  end

  def test_archive_migrates_the_projects_claude_history
    seed_history(@proj)
    app.run(["archive", "cadence"])
    assert path_exists?(File.join(@projects, enc(File.join(@personal, "ARCHIVE", "cadence")), "s.jsonl"))
    refute path_exists?(File.join(@projects, enc(@proj)))
  end

  def test_archive_does_not_touch_jotter_since_name_and_store_are_unchanged
    FileUtils.mkdir_p(File.join(@proj, ".git"))
    app.run(["archive", "cadence"])
    assert_empty @jotter_calls
  end

  def test_archive_declined_changes_nothing
    assert_equal 1, app(confirm: false).run(["archive", "cadence"])
    assert path_exists?(@proj)
    refute path_exists?(File.join(@personal, "ARCHIVE", "cadence"))
  end

  def test_archive_rejects_an_existing_target
    FileUtils.mkdir_p(File.join(@personal, "ARCHIVE", "cadence"))
    assert_equal 1, app.run(["archive", "cadence"])
    assert_match(/already exists/, @err.string)
  end

  def test_archive_errors_on_an_unknown_project
    assert_equal 1, app.run(["archive", "nope"])
  end

  def test_archive_requires_a_project
    assert_equal 1, app.run(["archive"])
  end

  def test_archive_cds_into_the_archived_project_when_inside_it
    inside = app
    inside.instance_variable_set(:@pwd, File.join(@proj, "lib"))
    inside.run(["archive", "cadence"])
    assert_equal [File.join(@personal, "ARCHIVE", "cadence", "/lib")], @cd
  end

  def test_mv_category_renames_the_directory
    assert_equal 0, app.run(["mv", "--category", "opensource", "open-source"])
    assert path_exists?(File.join(@root, "open-source"))
    refute path_exists?(@opensource)
  end

  def test_mv_category_resolves_by_dir_basename
    assert_equal 0, app.run(["mv", "--category", "client", "clients"])
    assert path_exists?(File.join(@root, "clients", "acme", "widget"))
    refute path_exists?(@client)
  end

  def test_mv_category_migrates_every_projects_claude_history
    seed_history(@proj)
    seed_history(File.join(@personal, "cadence-extra"))
    app.run(["mv", "--category", "personal", "mine"])
    assert path_exists?(File.join(@projects, enc(File.join(@root, "mine", "cadence")), "s.jsonl"))
    assert path_exists?(File.join(@projects, enc(File.join(@root, "mine", "cadence-extra"))))
    refute path_exists?(File.join(@projects, enc(@proj)))
  end

  def test_mv_category_migrates_namespaced_project_history
    seed_history(@client_proj)
    app.run(["mv", "--category", "client", "clients"])
    assert path_exists?(File.join(@projects, enc(File.join(@root, "clients", "acme", "widget")), "s.jsonl"))
    refute path_exists?(File.join(@projects, enc(@client_proj)))
  end

  def test_mv_category_rewrites_the_manifest_line
    app.run(["mv", "--category", "opensource", "open-source"])
    assert_equal "personal\nclient  depth=2\nopen-source\n", File.read(@manifest)
  end

  def test_mv_category_reminds_to_commit_the_manifest
    app.run(["mv", "--category", "opensource", "open-source"])
    assert_match(/updated #{Regexp.escape(@manifest)}.*commit this change/, @out.string)
  end

  def test_mv_category_leaves_jotter_untouched
    FileUtils.mkdir_p(File.join(@proj, ".git"))
    app.run(["mv", "--category", "personal", "mine"])
    assert_empty @jotter_calls
  end

  def test_mv_category_declined_changes_nothing
    assert_equal 1, app(confirm: false).run(["mv", "--category", "opensource", "open-source"])
    assert path_exists?(@opensource)
    assert_equal "personal\nclient  depth=2\nopensource\n", File.read(@manifest)
  end

  def test_mv_category_rejects_an_unknown_category
    assert_equal 1, app.run(["mv", "--category", "nope", "new"])
    assert_match(/unknown category 'nope'/, @err.string)
  end

  def test_mv_category_rejects_an_existing_target
    FileUtils.mkdir_p(File.join(@root, "open-source"))
    assert_equal 1, app.run(["mv", "--category", "opensource", "open-source"])
    assert_match(/already exists/, @err.string)
    assert path_exists?(@opensource)
  end

  def test_mv_category_rejects_a_slash_in_the_new_name
    assert_equal 1, app.run(["mv", "--category", "opensource", "a/b"])
    assert_match(/single path segment/, @err.string)
  end

  def test_mv_category_requires_both_names
    assert_equal 1, app.run(["mv", "--category", "opensource"])
    assert_match(/Usage: proj mv/, @err.string)
  end

  def test_mv_category_cds_when_standing_inside_the_renamed_tree
    app(pwd: File.join(@proj, "lib")).run(["mv", "--category", "personal", "mine"])
    assert_equal [File.join(@root, "mine", "cadence", "lib")], @cd
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
