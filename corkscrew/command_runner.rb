require 'net/ssh'
require 'io/console'
require 'open3'

module Corkscrew
  class CommandRunner

    def initialize(config)
      @config = config
      @sudo_password = nil
    end

    def run_command(command, sudo_escalation: true, cwd: nil, print_output: true, print_sudo_escalation: true, as_shell: false, screen_name: nil, in_series: false)
      if @config.local?
        run_command_internal(command, connection: nil, sudo_escalation: sudo_escalation, cwd: cwd, print_output: print_output, print_sudo_escalation: print_sudo_escalation, as_shell: as_shell, screen_name: screen_name)
      elsif connections.length <= 1
        run_command_internal(command, connection: connections.first, sudo_escalation: sudo_escalation, cwd: cwd, print_output: print_output, print_sudo_escalation: print_sudo_escalation, as_shell: as_shell, screen_name: screen_name)
      elsif screen_name || in_series
        # run command in series
        puts "Running #{command} on #{connections.length} hosts in series"
        connections.each_with_index do |connection, worker_index|
          run_command_internal(command, connection: connection, sudo_escalation: sudo_escalation, cwd: cwd, print_output: print_output, print_sudo_escalation: print_sudo_escalation, as_shell: as_shell, screen_name: screen_name, worker_index: worker_index)
        end
      else
        puts "Running #{command} on #{connections.length} hosts in parallel"
        threads = connections.each_with_index.map do |connection, worker_index|
          Thread.new do
            run_command_internal(command, connection: connection, sudo_escalation: sudo_escalation, cwd: cwd, print_output: print_output, print_sudo_escalation: print_sudo_escalation, as_shell: as_shell, worker_index: worker_index)
          end
        end

        threads.map(&:value).join
      end
    end

    def run_command_internal(command, connection:, sudo_escalation: true, cwd: nil, print_output: true, print_sudo_escalation: true, as_shell: false, screen_name: nil, worker_index: nil)
      original_command = command

      # command = "WORKER_COUNT=#{connections.length} WORKER_INDEX=#{worker_index} #{command}" unless worker_index.nil? || connections.length <= 1
      # puts "Running command: #{command}"

      if command.start_with?('sudo ') && !command.start_with?('sudo -S ')
        command = "echo -e \"#{sudo_password}\n\" | " + command.gsub(/sudo/, 'sudo -S')
      end

      # yikes
      if @config.local?
        result = self.class.run_locally command, print_output: print_output, cwd: cwd
      else
        command = "cd #{cwd} && #{command}" unless cwd.nil?
        command = "export WORKER_COUNT=#{connections.length} && export WORKER_INDEX=#{worker_index} && #{command}" unless worker_index.nil? || connections.length <= 1
        result = ''

        channel = connection.open_channel do |channel|
          channel.request_pty do |_ch, success|
            raise "Could not initialize PTY" unless success
          end

          if as_shell || screen_name
            channel.send_channel_request "shell" do |shell_channel, success|
              raise "Could not initialize shell" unless success

              run_id = nil
              if screen_name
                run_id = "#{screen_name}_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
                # write command to run_id.sh
                shell_channel.send_data("mkdir -p ~/screenlogs\n")
                shell_channel.send_data("mkdir -p ~/corkscrew_cmds\n")
                escaped_command = command.gsub("'", "'\\'")
                shell_channel.send_data("echo '#{escaped_command}' > ~/corkscrew_cmds/#{run_id}.sh\n")
                shell_channel.send_data("screen -S #{screen_name} -X \"^C\"\n") # send interrupt to screen
                shell_channel.send_data("screen -ls #{screen_name} | grep -oE '[0-9]+\.' | cut -d. -f1 | xargs -r -I {} sh -c 'kill -INT {} && sleep 2 && kill -TERM {}'\n") # kill screen
                shell_channel.send_data("screen -dm -S #{screen_name} -L -Logfile ~/screenlogs/#{run_id}.log bash ~/corkscrew_cmds/#{run_id}.sh\n")
                shell_channel.send_data("echo -n \"Screen #{screen_name} started with PID: \"\n")
                shell_channel.send_data("screen -ls | grep #{screen_name} || echo \"FAILED_TO_START_SCREEN\"\n")
              else
                shell_channel.send_data(command + "\n")
              end
              
              shell_channel.send_data("exit\n")

              print_all = false
              command_started = false

              shell_channel.on_data do |_ch2, data|
                @sudo_password = nil if data.include?('Sorry, try again.')
                shell_channel.send_data("#{sudo_password}\n") if password_requested(data)

                if data.strip.include?("FAILED_TO_START_SCREEN") && !data.include?("echo \"FAILED_TO_START_SCREEN\"")
                  puts "Failed to start screen #{screen_name}"
                end

                if data.strip.include?("\n#{command}") || data.strip.start_with?("#{command}")
                  command_started = true
                  data = data.split("#{command}").last.strip unless print_all
                end

                data = '' unless command_started || print_all

                if data.strip.include?("exit\r\n") || data.strip.include?("exit\n") || data.strip.end_with?("exit")
                  command_started = false
                  data = data.strip.split("exit").first&.strip || '' unless print_all
                end

                result += data.gsub(@sudo_password.to_s, '')
                print data.gsub(@sudo_password.to_s, '') if print_output
              end

              if run_id
                if worker_index.nil?
                  puts "Screen #{screen_name} started; run_id: #{run_id}"
                else
                  puts "Screen #{screen_name} started on host #{connection.host} (worker #{worker_index}); run_id: #{run_id}"
                end
              end

              shell_channel.wait
            end
          else
            channel.exec(command) do |_ch, success|
              raise "Could not execute command: #{command.inspect}" unless success

              channel.on_data do |_ch2, data|
                @sudo_password = nil if data.include?('Sorry, try again.')
                channel.send_data("#{sudo_password}\n") if password_requested(data)
                result += data.gsub(@sudo_password.to_s, '')
                print data.gsub(@sudo_password.to_s, '') if print_output
              end

              channel.on_extended_data do |_ch2, _type, data|
                $stderr.print(data)
              end
            end
          end
        end

        channel.wait
      end

      if requires_sudo(result)
        puts result if print_sudo_escalation && !print_output
        puts 'Re-attempting with sudo' if print_output || print_sudo_escalation
        return run_command "sudo #{original_command}", cwd: cwd, print_output: print_output if sudo_escalation && !command.start_with?('sudo ')
      end

      result
    end

    def connections
      @config.require_ssh_config!
      @connections ||= @config.ssh_hosts.map { |host|
        Net::SSH.start(host, @config.ssh['user'], @config.ssh_options)
      }
    end

    def close_connections
      @connections&.each { |connection| connection.close } if defined? @connections
      @connections = nil
    end

    private

    def password_requested(data)
      # return true if data =~ /^|\nPassword:\s*\z/

      data.include? '[sudo] password for'
    end

    def requires_sudo(result)
      return true if result.strip.end_with? 'Permission denied'
      return true if result.strip.end_with? 'Operation not permitted'
      return true if result.strip.end_with? 'a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper'

      false
    end

    def sudo_password
      return '' if @config.ssh['no_pwd']

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
