require_relative './command_runner'

module Corkscrew
  class ServiceManager

    def initialize(config, command_runner, nginx_manager)
      @config = config
      @command_runner = command_runner
      @nginx_manager = nginx_manager
    end

    def restart
      if @config.service_manager == 'systemd'
        if @config.zero_downtime_deployments?
          # figure out which service is currently running
          # start the other one
          # wait for it to accept connections
          # stop the old one

          green_up = green_up?
          blue_up = blue_up?

          if green_up && blue_up
            puts "Both green & blue services are up. Stopping green, then transitioning to it."

            # make sure it's actually running on the blue port
            nginx_success = @nginx_manager.replace_port(@config.green_port, @config.blue_port)
            unless nginx_success
              puts "WARNING: Nginx config is probably in a spooky state now"
              puts "You should fix this asap"
              return
            end

            @command_runner.run_command("sudo systemctl stop #{service_name}")

            # business as usual
            execute_zero_downtime_deployment('green')
          elsif !green_up && !blue_up
            puts "Neither green nor blue service is up. Starting green."
            start
          else
            execute_zero_downtime_deployment(green_up ? 'blue' : 'green')
          end
        else
          @command_runner.run_command("sudo systemctl restart #{service_name}")
        end
      elsif @config.service_manager == 'screen'
        stop
        start
      else
        raise 'Invalid service manager'
      end
    end

    def start
      if @config.service_manager == 'systemd'
        @command_runner.run_command("sudo systemctl start #{service_name}") unless @config.zero_downtime_deployments? && blue_up?
      elsif @config.service_manager == 'screen'
        @command_runner.run_command("bash start_screen.sh", cwd: @config.run_path)
      else
        raise 'Invalid service manager'
      end
    end

    def stop
      if @config.service_manager == 'systemd'
        @command_runner.run_command("sudo systemctl stop #{service_name}")
        @command_runner.run_command("sudo systemctl stop #{blue_service_name}") if @config.zero_downtime_deployments?
      elsif @config.service_manager == 'screen'
        @command_runner.run_command("touch /tmp/#{@config.name}-screen-killed; screen -S #{@config.name} -p 0 -X stuff $'\\cc'; screen -S #{@config.name} -p 0 -X stuff 'exit\n'")
      else
        raise 'Invalid service manager'
      end
    end

    def execute_zero_downtime_deployment(to_start)
      to_stop = to_start == 'green' ? 'blue' : 'green'

      puts "#{to_stop.capitalize} service is up. Starting #{to_start} service."
      @command_runner.run_command("sudo systemctl start #{to_start == 'green' ? service_name : blue_service_name}")
      60.times do |i|
        break if check_port_up(to_start == 'green' ? @config.green_port : @config.blue_port)

        puts "Service is still not up; waiting..." if i % 10 == 0 && i > 0
        sleep 1
      end

      unless check_port_up(to_start == 'green' ? @config.green_port : @config.blue_port)
        puts "Service did not come up in time. Aborting."
        puts "Run `corkscrew stop && corkscrew start` to ignore zero-downtime checks"
        return
      end

      puts "#{to_start.capitalize} service is now up; switching nginx to it."

      nginx_success = @nginx_manager.replace_port(to_stop == 'green' ? @config.green_port : @config.blue_port, to_start == 'green' ? @config.green_port : @config.blue_port)
      unless nginx_success
        puts "WARNING: Nginx config is probably in a spooky state now"
        puts "You should fix this asap"
        return
      end

      # Give nginx a little bit of time to reload
      sleep 1

      puts "Stopping #{to_stop} service."
      @command_runner.run_command("sudo systemctl stop #{to_stop == 'green' ? service_name : blue_service_name}")
    end

    def service_name
      @config.service_name || @config.name
    end

    def blue_service_name
      @config.blue_service_name || "#{service_name}_blue"
    end

    def green_up?
      check_port_up(@config.green_port)
    end

    def blue_up?
      check_port_up(@config.blue_port)
    end

    def check_port_up(port)
      @command_runner.run_command("curl -s -o /dev/null -w \"%{http_code}\" --head --connect-timeout 5 http://localhost:#{port}", print_output: false)&.start_with?('2')
    end

  end
end
