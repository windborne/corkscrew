require_relative './command_runner'

module Corkscrew
  class ServiceManager

    def initialize(config, command_runner)
      @config = config
      @command_runner = command_runner
    end

    def restart
      if @config.service_manager == 'systemd'
        @command_runner.run_command("sudo systemctl restart #{@config.service_name || @config.name}")
      elsif @config.service_manager == 'screen'
        stop
        start
      else
        raise 'Invalid service manager'
      end
    end

    def start
      if @config.service_manager == 'systemd'
        @command_runner.run_command("sudo systemctl start #{@config.service_name || @config.name}")
      elsif @config.service_manager == 'screen'
        @command_runner.run_command("bash start_screen.sh", cwd: @config.run_path)
      else
        raise 'Invalid service manager'
      end
    end

    def stop
      if @config.service_manager == 'systemd'
        @command_runner.run_command("sudo systemctl stop #{@config.service_name || @config.name}")
      elsif @config.service_manager == 'screen'
        @command_runner.run_command("touch /tmp/#{@config.name}-screen-killed; screen -S #{@config.name} -p 0 -X stuff $'\\cc'; screen -S #{@config.name} -p 0 -X stuff 'exit\n'")
      else
        raise 'Invalid service manager'
      end
    end

  end
end
