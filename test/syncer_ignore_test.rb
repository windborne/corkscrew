require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../corkscrew/syncer'

class SyncerIgnoreTest
  def initialize
    @failures = []
    @test_count = 0
  end

  def run
    test_root_basename_and_directory_patterns
    test_anchored_and_slash_patterns
    test_nested_gitignore_scope
    test_negation_and_rule_order
    test_nested_rules_override_parent_rules
    test_double_star_and_character_globs
    test_comments_escapes_and_trailing_spaces
    test_hidden_nested_gitignore
    test_directory_with_only_ignored_contents_is_pruned
    test_ignored_directory_does_not_use_its_gitignore
    test_remote_ignored_paths_are_protected
    test_repository_and_global_exclude_files

    if @failures.empty?
      puts "#{@test_count} syncer ignore tests passed"
      return
    end

    warn "#{@failures.length} of #{@test_count} syncer ignore tests failed:"
    @failures.each { |failure| warn "\n#{failure}" }
    exit 1
  end

  private

  def test_root_basename_and_directory_patterns
    run_case(
      'root basename and directory patterns',
      gitignores: {
        '.gitignore' => <<~GITIGNORE
          node_modules
          cache/
          *.rdb
          .DS_Store
        GITIGNORE
      },
      source_files: %w[
        app.rb
        node_modules/package/index.js
        frontend/node_modules/package/index.js
        cache/root.txt
        frontend/cache/nested.txt
        dump.rdb
        data/dump.rdb
        .DS_Store
        assets/.DS_Store
      ],
      absent: %w[
        node_modules
        frontend/node_modules
        cache
        frontend/cache
        dump.rdb
        data/dump.rdb
        .DS_Store
        assets/.DS_Store
      ],
      present: %w[app.rb .gitignore]
    )
  end

  def test_anchored_and_slash_patterns
    run_case(
      'anchored and slash-containing patterns',
      gitignores: {
        '.gitignore' => <<~GITIGNORE
          /root-only.txt
          docs/generated/
          anywhere.txt
        GITIGNORE
      },
      source_files: %w[
        root-only.txt
        nested/root-only.txt
        docs/generated/index.html
        nested/docs/generated/index.html
        anywhere.txt
        nested/anywhere.txt
      ],
      absent: %w[
        root-only.txt
        docs/generated
        anywhere.txt
        nested/anywhere.txt
      ],
      present: %w[
        nested/root-only.txt
        nested/docs/generated/index.html
      ]
    )
  end

  def test_nested_gitignore_scope
    run_case(
      'nested gitignore scope',
      gitignores: {
        'app/.gitignore' => <<~GITIGNORE
          local.txt
          /anchored.txt
          test/.env
          build/
        GITIGNORE
      },
      source_files: %w[
        local.txt
        app/local.txt
        app/deep/local.txt
        app/anchored.txt
        app/deep/anchored.txt
        app/test/.env
        app/deep/test/.env
        app/build/output.js
        app/deep/build/output.js
      ],
      absent: %w[
        app/local.txt
        app/deep/local.txt
        app/anchored.txt
        app/test/.env
        app/build
        app/deep/build
      ],
      present: %w[
        local.txt
        app/deep/anchored.txt
        app/deep/test/.env
        app/.gitignore
      ]
    )
  end

  def test_negation_and_rule_order
    run_case(
      'negation and last matching rule wins',
      gitignores: {
        '.gitignore' => <<~GITIGNORE
          *.log
          !important.log
          !reignored.log
          reignored.log
          vendor/*
          !vendor/keep/
          !vendor/keep/**
        GITIGNORE
      },
      source_files: %w[
        debug.log
        nested/debug.log
        important.log
        nested/important.log
        reignored.log
        vendor/drop.txt
        vendor/keep/kept.txt
      ],
      absent: %w[
        debug.log
        nested/debug.log
        reignored.log
        vendor/drop.txt
      ],
      present: %w[
        important.log
        nested/important.log
        vendor/keep/kept.txt
      ]
    )
  end

  def test_nested_rules_override_parent_rules
    run_case(
      'nested rules override parent rules',
      gitignores: {
        '.gitignore' => "*.tmp\n",
        'app/.gitignore' => "!keep.tmp\n"
      },
      source_files: %w[
        root.tmp
        app/drop.tmp
        app/keep.tmp
        app/deep/keep.tmp
      ],
      absent: %w[root.tmp app/drop.tmp],
      present: %w[app/keep.tmp app/deep/keep.tmp]
    )
  end

  def test_double_star_and_character_globs
    run_case(
      'double-star and character globs',
      gitignores: {
        '.gitignore' => <<~GITIGNORE
          logs/**/debug.txt
          cache/**
          file?.txt
          data/[0-9].csv
        GITIGNORE
      },
      source_files: %w[
        logs/debug.txt
        logs/a/debug.txt
        logs/a/b/debug.txt
        logs/a/info.txt
        cache/root.txt
        cache/a/nested.txt
        file1.txt
        file12.txt
        data/1.csv
        data/a.csv
      ],
      absent: %w[
        logs/debug.txt
        logs/a/debug.txt
        logs/a/b/debug.txt
        cache/root.txt
        cache/a/nested.txt
        file1.txt
        data/1.csv
      ],
      present: %w[
        logs/a/info.txt
        file12.txt
        data/a.csv
      ]
    )
  end

  def test_comments_escapes_and_trailing_spaces
    run_case(
      'comments, escapes, and trailing spaces',
      gitignores: {
        '.gitignore' => <<~'GITIGNORE'
          # a comment
          \#literal
          \!literal
           leading-space
          trailing-space    
          escaped-space\ 
        GITIGNORE
      },
      source_files: [
        '#literal',
        '!literal',
        ' leading-space',
        'leading-space',
        'trailing-space',
        'trailing-space    ',
        'escaped-space ',
        'escaped-space'
      ],
      absent: [
        '#literal',
        '!literal',
        ' leading-space',
        'trailing-space',
        'escaped-space '
      ],
      present: [
        'leading-space',
        'trailing-space    ',
        'escaped-space'
      ]
    )
  end

  def test_hidden_nested_gitignore
    run_case(
      'gitignore inside a dot directory',
      gitignores: {
        '.config/.gitignore' => "secret.txt\n"
      },
      source_files: %w[
        .config/public.txt
        .config/secret.txt
        .config/nested/secret.txt
      ],
      absent: %w[
        .config/secret.txt
        .config/nested/secret.txt
      ],
      present: %w[
        .config/public.txt
        .config/.gitignore
      ]
    )
  end

  def test_directory_with_only_ignored_contents_is_pruned
    run_case(
      'directory with only ignored contents is pruned',
      gitignores: {
        '.ruby-lsp/.gitignore' => "*\n"
      },
      source_files: %w[
        .ruby-lsp/Gemfile
        public.txt
      ],
      absent: %w[.ruby-lsp],
      present: %w[public.txt]
    )
  end

  def test_ignored_directory_does_not_use_its_gitignore
    run_case(
      'gitignore inside an ignored directory has no effect',
      gitignores: {
        '.gitignore' => "vendor/\n",
        'vendor/.gitignore' => "!secret.txt\n"
      },
      source_files: %w[
        vendor/secret.txt
        vendor/other.txt
      ],
      absent: %w[vendor]
    )
  end

  def test_remote_ignored_paths_are_protected
    run_case(
      'ignored paths are protected from remote deletion',
      gitignores: {
        '.gitignore' => <<~GITIGNORE
          node_modules/
          runtime.log
        GITIGNORE
      },
      source_files: %w[
        app.rb
        node_modules/local-only.js
      ],
      destination_files: %w[
        node_modules/remote-only.js
        runtime.log
        stale.txt
      ],
      absent: %w[
        node_modules/local-only.js
        stale.txt
      ],
      present: %w[
        app.rb
        node_modules/remote-only.js
        runtime.log
      ]
    )
  end

  def test_repository_and_global_exclude_files
    run_case(
      'repository and configured global exclude files',
      gitignores: {
        '.gitignore' => "repo-ignored.txt\n"
      },
      source_files: %w[
        repo-ignored.txt
        info-ignored.txt
        .idea/workspace.xml
        nested/.idea/workspace.xml
        public.txt
      ],
      git_excludes: "info-ignored.txt\n",
      global_excludes: ".idea/\n",
      absent: %w[
        repo-ignored.txt
        info-ignored.txt
        .idea
        nested/.idea
      ],
      present: %w[public.txt]
    )
  end

  def run_case(name, gitignores:, source_files:, absent:, present: [],
               destination_files: [], git_excludes: nil, global_excludes: nil)
    @test_count += 1

    Dir.mktmpdir('corkscrew-syncer-test') do |tmpdir|
      source = File.join(tmpdir, 'source')
      destination = File.join(tmpdir, 'destination')
      FileUtils.mkdir_p([source, destination])

      gitignores.each { |path, contents| write_file(File.join(source, path), contents) }
      source_files.each { |path| write_file(File.join(source, path), "source: #{path}\n") }
      destination_files.each { |path| write_file(File.join(destination, path), "destination: #{path}\n") }

      configure_git_excludes(
        source,
        tmpdir,
        git_excludes: git_excludes,
        global_excludes: global_excludes
      )
      assert_expectations_match_git(source, source_files, absent, present)

      config = Struct.new(:root_dir).new(source)
      syncer = Corkscrew::Syncer.new(config, nil)
      filter_path = File.join(tmpdir, 'rsync-filter')
      File.open(filter_path, 'w') do |file|
        syncer.build_rsync_filter_file_from_gitignores(file)
      end

      run!(
        'rsync',
        '-a',
        '--prune-empty-dirs',
        '--delete',
        '--exclude=/.git',
        "--filter=. #{filter_path}",
        "#{source}/",
        "#{destination}/"
      )

      absent.each { |path| assert_path(File.join(destination, path), present: false) }
      present.each { |path| assert_path(File.join(destination, path), present: true) }
    end

    puts "PASS: #{name}"
  rescue StandardError => error
    @failures << "FAIL: #{name}\n  #{error.message.gsub("\n", "\n  ")}"
  end

  def configure_git_excludes(source, tmpdir, git_excludes:, global_excludes:)
    run!('git', 'init', '-q', source)

    unless git_excludes.nil?
      write_file(File.join(source, '.git', 'info', 'exclude'), git_excludes)
    end

    global_ignore = File.join(tmpdir, 'global-ignore')
    write_file(global_ignore, global_excludes || '')
    run!('git', 'config', 'core.excludesFile', global_ignore, cwd: source)
  end

  def assert_expectations_match_git(source, source_files, absent, present)
    source_files.each do |path|
      expected_ignored = expected_path_state(path, absent, present)
      next if expected_ignored.nil?

      _output, status = Open3.capture2e(
        'git',
        'check-ignore',
        '--quiet',
        '--no-index',
        '--',
        path,
        chdir: source
      )
      unless [0, 1].include?(status.exitstatus)
        raise "git check-ignore failed for #{path}"
      end

      actual_ignored = status.success?
      next if actual_ignored == expected_ignored

      raise "Test expectation for #{path} disagrees with git check-ignore"
    end
  end

  def expected_path_state(path, absent, present)
    return true if absent.any? { |item| path == item || path.start_with?("#{item}/") }
    return false if present.any? { |item| path == item || path.start_with?("#{item}/") }

    nil
  end

  def write_file(path, contents)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def run!(*command, cwd: nil)
    options = {}
    options[:chdir] = cwd unless cwd.nil?
    output, status = Open3.capture2e(*command, options)
    raise "#{command.join(' ')} failed:\n#{output}" unless status.success?

    output
  end

  def assert_path(path, present:)
    return if File.exist?(path) == present

    expectation = present ? 'to exist' : 'not to exist'
    raise "Expected #{path} #{expectation}"
  end
end

SyncerIgnoreTest.new.run
