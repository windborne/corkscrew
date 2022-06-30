require 'open3'

module Corkscrew
  class Syncer

    class SyncError < StandardError

    end

    def initialize(config, remote_runner)
      @config = config
      @remote_runner = remote_runner
    end

    def sync
      raise SyncError, 'A deploy path is required to sync code' if @config.deploy_path.nil?

      destination = @config.deploy_path
      unless @config.local?
        raise SyncError, 'SSH config is required to sync code remotely' if @config.ssh.nil?

        @remote_runner.run_command "sudo mkdir -p #{destination}"
        @remote_runner.run_command "sudo chown -R #{@config.ssh['user']} #{destination}"

        destination = "#{@config.ssh['user']}@#{@config.ssh['host']}:#{destination}"
      end

      source = File.absolute_path(@config.root)
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

      Open3.popen2e('rsync', *flags, source, destination) do |stdin, stdout_stderr, wait_thread|
        Thread.new do
          stdout_stderr.each {|l| puts l }
        end

        stdin.puts 'ls'
        stdin.close

        wait_thread.value
      end
    end

  end
end
