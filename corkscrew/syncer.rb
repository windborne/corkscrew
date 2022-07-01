require_relative './command_runner'

module Corkscrew
  class Syncer

    class SyncError < StandardError

    end

    def initialize(config, command_runner)
      @config = config
      @command_runner = command_runner
    end

    def sync
      raise SyncError, 'A deploy path is required to sync code' if @config.deploy_path.nil?

      destination = @config.deploy_path
      unless @config.local?
        raise SyncError, 'SSH config is required to sync code remotely' if @config.ssh.nil?

        @command_runner.run_command "mkdir -p #{destination}", print_output: false
        @command_runner.run_command "chown -R #{@config.ssh['user']} #{destination}", print_output: false

        destination = "#{@config.ssh['user']}@#{@config.ssh['host']}:#{destination}"
      end

      source = @config.root_dir
      source += '/' unless source.end_with?('.') || source.end_with?('/')

      flags = [
        '-avzhP',
        '--include=**.gitignore',
        '--exclude=/.git',
        '--filter=:- .gitignore',
        '--delete-after',
        '--delete'
      ]

      puts "Syncing #{source} to #{destination}"

      CommandRunner.run_locally 'rsync', *flags, source, destination
    end

  end
end
