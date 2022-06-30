require 'net/ssh'
require 'io/console'

module Corkscrew
  class RemoteRunner

    def initialize(config)
      @config = config
      @sudo_password = nil
    end

    def run_file_or_script(file_or_script)
      if file_or_script.split(' ').length == 1 && file_or_script.ends_with?('.sh')
        run_command "bash #{file_or_script}"
        return
      end

      run_command file_or_script
    end

    def run_command(script_contents, sudo_escalation: true)
      if script_contents.start_with?('sudo ') && !script_contents.start_with?('sudo -S ')
        script_contents = "echo -e \"#{sudo_password}\n\" | " + script_contents.gsub(/sudo/, 'sudo -S')
      end

      result = connection.exec!(script_contents)

      if result.end_with? 'Permission denied'
        return run_command "sudo #{script_contents}" if sudo_escalation && !script_contents.start_with?('sudo ')
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

    def sudo_password
      return @sudo_password unless @sudo_password.nil?

      @sudo_password = IO::console.getpass("Password for #{@config.ssh['user']}: ")
    end

  end
end
