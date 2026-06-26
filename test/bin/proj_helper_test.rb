#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
ScriptTest.load_script("../bin/proj-helper")

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
    keys = ["nesta/asf_visit_a_heat_pump", "nesta/other", "acme/heat"]
    assert_equal ["nesta/asf_visit_a_heat_pump"], Proj.fuzzy_match(keys, "nest/asf")
  end

  def test_fuzzy_match_namespaced_falls_back_to_substring_segments
    keys = ["nesta/asf_visit_a_heat_pump", "acme/cooling"]
    assert_equal ["nesta/asf_visit_a_heat_pump"], Proj.fuzzy_match(keys, "est/heat")
  end

  def test_fuzzy_match_namespaced_ignores_flat_keys
    keys = ["heat-tool", "nesta/heat"]
    assert_equal ["nesta/heat"], Proj.fuzzy_match(keys, "n/heat")
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
    assert_equal "nesta/heat", Proj.key_for("/root/client/nesta/heat", 2)
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
      "client/nesta/asf_visit_a_heat_pump",
      "client/ARCHIVE/x",
      "client/acme/ARCHIVE",
      "opensource/ripgrep"
    )

    @trees = [
      { dir: File.join(@personal, "PRIVATE"), depth: 1, exclude: ["ARCHIVE"] },
      { dir: @personal, depth: 1, exclude: ["ARCHIVE", "PRIVATE"] },
      { dir: @client, depth: 2, exclude: ["ARCHIVE"] },
      { dir: @opensource, depth: 1, exclude: ["ARCHIVE"] }
    ]
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_build_map_keys_each_tree
    map = Proj.build_map(@trees)

    assert_equal File.join(@personal, "cadence"), map["cadence"]
    assert_equal File.join(@client, "nesta/asf_visit_a_heat_pump"), map["nesta/asf_visit_a_heat_pump"]
    assert_equal File.join(@opensource, "ripgrep"), map["ripgrep"]
  end

  def test_build_map_personal_wins_collision_over_private
    map = Proj.build_map(@trees)
    assert_equal File.join(@personal, "session-logs"), map["session-logs"]
  end

  def test_build_map_exposes_private_only_projects
    map = Proj.build_map(@trees)
    assert_equal File.join(@personal, "PRIVATE/secret"), map["secret"]
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
    pwd = File.join(@client, "nesta/asf_visit_a_heat_pump/app")
    assert_equal File.join(@client, "nesta/asf_visit_a_heat_pump"), Proj.root_from_pwd(pwd, @trees)
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
    @trees = [{ dir: @personal, depth: 1, exclude: ["ARCHIVE"] }]
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

  def test_bare_outside_project_lists_keys
    app, _cd, out = build_app(pwd: @root)
    assert_equal 1, app.run([])
    assert_includes out.string, "cadence"
    assert_includes out.string, "cadence-extra"
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

  private

  def build_app(pwd:)
    cd = []
    out = StringIO.new
    err = StringIO.new
    app = Proj::App.new(
      trees: @trees, pwd: pwd, out: out, err: err,
      cd: ->(path) { cd << path }, cache: ->(_) {}
    )
    [app, cd, out, err]
  end
end
