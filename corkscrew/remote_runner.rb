require 'net/ssh'

module Corkscrew
  class RemoteRunner

    def initialize(config)
      @config = config
    end

    def run_file_or_script(file_or_script)
      if file_or_script.split(' ').length == 1 && file_or_script.ends_with?('.sh')
        run_script "bash #{file_or_script}"
        return
      end

      run_script file_or_script
    end

    def run_script(script_contents)
      connection.exec!(script_contents)
    end

    def connection
      @connection ||= Net::SSH.start('host', 'user', password: "password")
    end

    def close_connection
      @connection&.close if defined? @connection
      @connection = nil
    end

  end
end
