require 'net/ssh'
require 'io/console'
require 'open3'

module Corkscrew
  class CommandRunner

    def initialize(config)
      @config = config
      @sudo_password = nil
    end

    def run_command(command, sudo_escalation: true, cwd: nil, print_output: true)
      original_command = command

      if command.start_with?('sudo ') && !command.start_with?('sudo -S ')
        command = "echo -e \"#{sudo_password}\n\" | " + command.gsub(/sudo/, 'sudo -S')
      end

      # yikes
      if @config.local?
        result = self.class.run_locally command, print_output: print_output, cwd: cwd
      else
        command = "cd #{cwd} && #{command}" unless cwd.nil?

        result = ''
        connection.exec!(command) do |_channel, _stream, data|
          result += data
          print data if print_output
        end
      end

      if requires_sudo(result)
        puts 'Re-attempting with sudo' if print_output
        return run_command "sudo #{original_command}", cwd: cwd, print_output: print_output if sudo_escalation && !command.start_with?('sudo ')
      end

      result
    end

    def connection
      @connection ||= Net::SSH.start(@config.ssh['host'], @config.ssh['user'])
    end

    def close_connection
      @connection&.close if defined? @connection
      @connection = nil
    end

    private

    def requires_sudo(result)
      return true if result.strip.end_with? 'Permission denied'
      return true if result.strip.end_with? 'a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper'

      false
    end

    def sudo_password
      return @sudo_password unless @sudo_password.nil?

      if @config.local?
        prompt = "Password: "
      else
        prompt = "Password for #{@config.ssh['user']}: "
      end

      @sudo_password = IO::console.getpass(prompt)
    end

    def self.run_locally(*command, print_output: true, cwd: nil)
      result = ''
      opts = {}
      opts[:chdir] = cwd unless cwd.nil?

      Open3.popen2e(*command, opts) do |stdin, stdout_stderr, wait_thread|
        Thread.new do
          stdout_stderr.each { |l|
            puts l if print_output
            result += l
          }
        end

        stdin.close

        wait_thread.value
      end

      result
    end

  end
end
