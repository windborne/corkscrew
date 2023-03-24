require_relative './command_runner'

module Corkscrew
  class Syncer

    def initialize(config, command_runner)
      @config = config
      @command_runner = command_runner
    end

    def sync
      @config.require_deploy_path!

      destination = @config.deploy_path
      unless @config.local?
        @config.require_ssh_config!

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

      # Note: a known issue is that we don't use the ssh identity file, and instead rely on the user to `ssh-add` it

      puts "Syncing #{source} to #{destination}"
      # puts "rsync #{flags.join(' ')} #{source} #{destination}"

      CommandRunner.run_locally 'rsync', *flags, source, destination
    end

  end
end
