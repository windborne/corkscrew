require 'json'
require 'thor'
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

        # flags = [
        #   '-avzhP',
        #   '--include=**.gitignore',
        #   '--exclude=/.git',
        #   '--filter=:- .gitignore',
        #   '--delete-after',
        #   '--delete'
        # ]
        #
        # ignored = CommandRunner.run_locally('git ls-files --ignored --exclude-standard -o', cwd: @config.root_dir, print_output: false).split("\n")
        #
        # # Add protect rules for each ignored file
        # ignored.each do |path|
        #   flags << "--filter=P #{path}"
        # end

        flags = [
          '-avzhP',
          '--include=**/.gitignore',
          '--exclude=/.git',
          '--delete-after',
          '--delete'
        ]

        # List ignored/untracked files
        ignored = CommandRunner.run_locally(
          "git ls-files --ignored --exclude-standard -o",
          cwd: @config.root_dir,
          print_output: false
        ).split("\n")

        # Write protect rules into a temp file
        require "tempfile"
        filter_file = Tempfile.new("rsync-filters")
        ignored.each do |path|
          filter_file.puts("- #{path}") # exclude so it isn't copied
          filter_file.puts("P #{path}") # but protect so it isn't deleted
        end
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

    end
  end
end
