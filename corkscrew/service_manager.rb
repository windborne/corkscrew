require_relative './command_runner'

module Corkscrew
  class ServiceManager

    def initialize(config, command_runner)
      @config = config
      @command_runner = command_runner
    end

    def restart
      if @config.service_manager == 'systemd'
        @command_runner.run_command("sudo systemctl restart #{@config.name}")
      elsif @config.service_manager == 'screen'
        stop
        start
      else
        raise 'Invalid service manager'
      end
    end

    def start
      if @config.service_manager == 'systemd'
        @command_runner.run_command("sudo systemctl start #{@config.name}")
      elsif @config.service_manager == 'screen'
        @command_runner.run_command("bash start_screen.sh", cwd: @config.deploy_path)
      else
        raise 'Invalid service manager'
      end
    end

    def stop
      if @config.service_manager == 'systemd'
        @command_runner.run_command("sudo systemctl stop #{@config.name}")
      elsif @config.service_manager == 'screen'
        @command_runner.run_command("screen -S #{@config.name} -p 0 -X stuff $'\\cc'")
      else
        raise 'Invalid service manager'
      end
    end

  end
end
