require 'json'
require 'thor'
require 'pathname'
require 'find'
require_relative './command_runner'
require_relative 'helpers/query_helpers'

module Corkscrew
  class Syncer < Thor
    include Thor::Actions
    include Corkscrew::Helpers::QueryHelpers

    def initialize(config, command_runner)
      @config = config
      @command_runner = command_runner
    end

    no_commands do

      def sync
        @config.require_deploy_path!

        confirmed = true
        unless @config.skip_confirmation?
          if @config.confirm_sync == 'always'
            confirmed = ask_default_yes("Are you sure you want to sync? [Yn]")
          elsif @config.confirm_sync == 'dirty' && git_info[:dirty]
            confirmed = ask_default_no("You have uncommitted changes. Are you sure you want to sync? [yN]")
          end
        end

        unless confirmed
          say 'Sync aborted'
          exit 0
        end

        destination = @config.deploy_path
        destinations = []
        unless @config.local?
          @config.require_ssh_config!

          @command_runner.run_command "mkdir -p #{destination}", print_output: false
          @command_runner.run_command "chown -R #{@config.ssh['user']} #{destination}", print_output: false

          destinations = @config.ssh_hosts.map { |host|
            "#{@config.ssh['user']}@#{host}:#{destination}"
          }
        end

        source = @config.root_dir
        source += '/' unless source.end_with?('.') || source.end_with?('/')

        flags = [
          '-avzhP',
          '--exclude=/.git',
          '--prune-empty-dirs',
          '--delete-after',
          '--delete'
        ]

        # Build an rsync filter file derived from all .gitignore files
        require "tempfile"
        filter_file = Tempfile.new("rsync-filters")
        build_rsync_filter_file_from_gitignores(filter_file)
        filter_file.flush

        # Add the filter file to rsync flags
        flags << "--filter=. #{filter_file.path}"

        unless @config.ssh['identity'].nil? || @config.ssh['identity'].empty?
          flags += [
            '-e',
            "ssh -i #{@config.ssh['identity']}"
          ]
        end

        # Note: a known issue is that we don't use the ssh identity file, and instead rely on the user to `ssh-add` it
        # puts "rsync #{flags.join(' ')} #{source} #{destination}"

        git_info_path = nil
        if @config.add_git_info?
          git_info_name = '.git_status.json'
          git_info_name = @config.git_info if @config.git_info.is_a? String

          git_info_path = File.join(@config.root_dir, git_info_name)

          File.write(git_info_path, JSON.pretty_generate(git_info))
          puts "Syncing git info to #{git_info_path}"
        end

        destinations.each do |destination|
          puts "Syncing #{source} to #{destination}"
          CommandRunner.run_locally 'rsync', *flags, source, destination
        end

        begin
          File.delete(git_info_path) unless git_info_path.nil?
        rescue Errno::ENOENT
          puts "Git info file #{git_info_path} already deleted; skipping"
        end
      end

      def copy_file(source, destination)
        unless @config.local?
          @config.require_ssh_config!

          @command_runner.run_command "touch #{destination}", print_output: false
          @command_runner.run_command "sudo chown #{@config.ssh['user']} #{destination}", print_output: false
          destination = "#{@config.ssh['user']}@#{@config.ssh['host']}:#{destination}"
        end

        CommandRunner.run_locally 'scp', source, destination
      end

      def git_info
        return @git_info unless @git_info.nil?

        modified_files = CommandRunner.run_locally('git status --porcelain', cwd: @config.root_dir, print_output: false).split("\n").map { |line| line.split(' ')[1] }

        branch = CommandRunner.run_locally('git rev-parse --abbrev-ref HEAD', cwd: @config.root_dir, print_output: false).strip
        modified_files = [] if branch == 'fatal: not a git repository (or any of the parent directories): .git'

        @git_info = {
          remote: CommandRunner.run_locally('git config --get remote.origin.url', cwd: @config.root_dir, print_output: false).strip,
          sha: CommandRunner.run_locally('git rev-parse HEAD', cwd: @config.root_dir, print_output: false).strip,
          branch: branch,
          dirty: modified_files.any?,
          modified_files: modified_files,
          synced_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S%z")
        }
      end

      # Translate Git ignore rules to rsync filters without enumerating ignored
      # files. Git uses the last matching rule, while rsync uses the first, so
      # rules are emitted in reverse precedence order.
      def build_rsync_filter_file_from_gitignores(io)
        project_root = File.expand_path(@config.root_dir)
        rules = []

        gitignore_sources(project_root).each do |source|
          File.foreach(source[:path], chomp: true) do |line|
            parsed = parse_gitignore_line(line)
            next if parsed.nil?

            rules << {
              negated: parsed[:negated],
              patterns: rsync_patterns_for_gitignore(
                parsed[:pattern],
                source[:base_rel],
                parsed[:directory_only],
                parsed[:anchored]
              )
            }
          end
        end

        rules.reverse_each do |rule|
          rule[:patterns].each do |pattern|
            if rule[:negated]
              io.puts("+ #{pattern}")
            else
              # P applies on the receiver, preserving ignored runtime files
              # when --delete is enabled. The exclude applies on the sender.
              io.puts("P #{pattern}")
              io.puts("- #{pattern}")
            end
          end
        end
      end

      def gitignore_sources(project_root)
        sources = git_exclude_sources(project_root)
        gitignore_paths = []

        Find.find(project_root) do |path|
          if File.directory?(path) && File.basename(path) == '.git'
            Find.prune
          elsif File.file?(path) && File.basename(path) == '.gitignore'
            gitignore_paths << path
          end
        end

        gitignore_paths.sort_by do |path|
          relative = Pathname(path).relative_path_from(Pathname(project_root)).to_s
          [relative.count(File::SEPARATOR), relative]
        end.each do |path|
          base_rel = Pathname(File.dirname(path))
            .relative_path_from(Pathname(project_root))
            .to_s
          base_rel = '' if base_rel == '.'
          sources << { path: path, base_rel: base_rel }
        end

        sources
      end

      # Git's repository and configured global exclude files have lower
      # precedence than every per-directory .gitignore file.
      def git_exclude_sources(project_root)
        git_dir = CommandRunner.run_locally(
          'git',
          'rev-parse',
          '--git-dir',
          cwd: project_root,
          print_output: false
        ).strip
        return [] if git_dir.empty? || git_dir.start_with?('fatal:')

        sources = []
        global_excludes = CommandRunner.run_locally(
          'git',
          'config',
          '--path',
          '--get',
          'core.excludesFile',
          cwd: project_root,
          print_output: false
        ).strip
        if !global_excludes.empty? && File.file?(global_excludes)
          sources << { path: global_excludes, base_rel: '' }
        end

        git_dir = File.expand_path(git_dir, project_root)
        repository_excludes = File.join(git_dir, 'info', 'exclude')
        if File.file?(repository_excludes)
          sources << { path: repository_excludes, base_rel: '' }
        end

        sources
      end

      def parse_gitignore_line(line)
        line = remove_unescaped_trailing_spaces(line)
        return nil if line.empty? || line.start_with?('#')

        negated = line.start_with?('!')
        line = line[1..-1] if negated
        return nil if line.nil? || line.empty?

        directory_only = line.end_with?('/')
        line = line[0...-1] if directory_only
        anchored = line.start_with?('/')
        line = line[1..-1] if anchored
        return nil if line.nil? || line.empty?

        {
          negated: negated,
          pattern: translate_gitignore_escapes(line),
          directory_only: directory_only,
          anchored: anchored
        }
      end

      def remove_unescaped_trailing_spaces(line)
        while line.end_with?(' ')
          backslash_count = 0
          index = line.length - 2
          while index >= 0 && line[index] == '\\'
            backslash_count += 1
            index -= 1
          end

          break if backslash_count.odd?
          line = line[0...-1]
        end
        line
      end

      def translate_gitignore_escapes(pattern)
        translated = ''
        index = 0

        while index < pattern.length
          if pattern[index] == '\\' && index + 1 < pattern.length
            escaped = pattern[index + 1]
            if ['*', '?', '[', '\\'].include?(escaped)
              translated << '\\' << escaped
            else
              translated << escaped
            end
            index += 2
          else
            translated << pattern[index]
            index += 1
          end
        end

        translated
      end

      def rsync_patterns_for_gitignore(pattern, base_rel, directory_only, anchored)
        contains_slash = pattern.include?('/')
        patterns = if !anchored && !contains_slash && base_rel.empty?
                     [pattern]
                   elsif !anchored && !contains_slash
                     [
                       "/#{base_rel}/#{pattern}",
                       "/#{base_rel}/**/#{pattern}"
                     ]
                   else
                     relative = [base_rel, pattern].reject(&:empty?).join('/')
                     ["/#{relative}"]
                   end

        patterns = patterns.flat_map { |item| expand_zero_depth_double_stars(item) }
        patterns.map! { |item| directory_only ? "#{item}/" : item }
        patterns.uniq
      end

      # rsync 2.6.9 does not let a leading **/ match at the transfer root.
      # Git's **/ can match zero directories, so emit that form explicitly.
      def expand_zero_depth_double_stars(pattern)
        patterns = [pattern]
        index = 0

        while index < patterns.length
          expanded = patterns[index].sub('/**/', '/')
          patterns << expanded unless expanded == patterns[index] || patterns.include?(expanded)
          index += 1
        end

        patterns
      end

    end
  end
end
