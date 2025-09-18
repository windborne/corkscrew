require 'json'
require 'thor'
require 'pathname'
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

      # Build rsync filter rules from all .gitignore files in the project.
      # - Skips commented and blank lines
      # - Handles negations starting with '!'
      # - For ignored entries: exclude and protect (so --delete doesn't remove them remotely)
      # - For negated entries: include the path so they are transferred
      def build_rsync_filter_file_from_gitignores(io)
        project_root = File.expand_path(@config.root_dir)

        gitignore_paths = Dir.glob(File.join(project_root, '**', '.gitignore'))
        root_gitignore = File.join(project_root, '.gitignore')
        gitignore_paths << root_gitignore if File.exist?(root_gitignore) && !gitignore_paths.include?(root_gitignore)
        gitignore_paths.reject! { |p| p.include?(File.join(project_root, '.git', '')) }

        include_rules = []
        exclude_rules = []

        gitignore_paths.sort.each do |gitignore_path|
          base_dir = File.dirname(gitignore_path)
          base_rel = Pathname(base_dir).relative_path_from(Pathname(project_root)).to_s
          base_rel = '' if base_rel == '.'

          File.foreach(gitignore_path, chomp: true) do |line|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?('#')

            negated = stripped.start_with?('!')
            pattern = negated ? stripped[1..-1] : stripped

            is_dir = pattern.end_with?('/')
            pattern = pattern.chomp('/') if is_dir

            # Build patterns relative to project root respecting .gitignore semantics:
            # - leading '/' anchors to the directory containing the .gitignore
            # - otherwise it can match in subdirectories, so prefix '**/' under the base
            rel_patterns = []
            if pattern.start_with?('/')
              anchored = pattern.sub(%r{^/+}, '')
              rel_patterns << File.join(base_rel, anchored)
            else
              if base_rel.empty?
                rel_patterns << File.join('**', pattern)
              else
                rel_patterns << File.join(base_rel, pattern)
                rel_patterns << File.join(base_rel, '**', pattern)
              end
            end

            rel_patterns.each do |rel|
              # Normalize multiple slashes
              rel = rel.gsub(%r{/+}, '/').sub(%r{^\./}, '')

              if negated
                if is_dir
                  include_rules << "+ #{rel}/"
                else
                  include_rules << "+ #{rel}"
                end
              else
                # Exclude and protect ignored paths so remote artifacts are not deleted
                if is_dir
                  exclude_rules << "P #{rel}/"
                  exclude_rules << "P #{rel}/***"
                  exclude_rules << "- #{rel}/"
                  exclude_rules << "- #{rel}/***"
                else
                  exclude_rules << "P #{rel}"
                  exclude_rules << "- #{rel}"
                end
              end
            end
          end
        end

        # Write includes first so they can override excludes when needed
        include_rules.uniq.each { |r| io.puts(r) }
        exclude_rules.uniq.each { |r| io.puts(r) }
      end

    end
  end
end
