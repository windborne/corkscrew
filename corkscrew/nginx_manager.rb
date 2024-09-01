require_relative './command_runner'

module Corkscrew
  class NginxManager

    def initialize(config, command_runner, syncer)
      @config = config
      @command_runner = command_runner
      @syncer = syncer
    end

    def configure_app
      @config.require_nginx!

      install_nginx
      update_server_block

      puts
      puts "Note: you'll need to set up SSL certificates yourself, eg by running sudo certbot --nginx"
    end

    def update_server_block
      @syncer.copy_file @config.nginx_config_path, "/etc/nginx/sites-available/#{@config.name}"
      @command_runner.run_command "sudo chown root /etc/nginx/sites-available/#{@config.name}"
      @command_runner.run_command "sudo ln -s /etc/nginx/sites-available/#{@config.name} /etc/nginx/sites-enabled/"
      reload_config
    end

    def reload_config
      test = @command_runner.run_command "sudo nginx -t"
      unless test.strip.end_with? 'is successful'
        puts 'Invalid nginx config; aborting'
        return false
      end

      @command_runner.run_command "sudo nginx -s reload"
      puts 'Config updated and nginx restarted!'
      true
    end

    def replace_port(old_port, new_port)
      remote_nginx_path = "/etc/nginx/sites-available/#{@config.name}"
      find = "proxy_pass http://localhost:#{old_port};"
      replace = "proxy_pass http://localhost:#{new_port};"
      sed_command = "sudo sed -i 's|#{find}|#{replace}|g' #{remote_nginx_path}"
      sed_output = @command_runner.run_command(sed_command, print_output: false)
      unless sed_output.empty?
        puts "Error replacing port"
        puts sed_output
        return false
      end

      reload_config
    end

    def install_nginx
      @command_runner.run_command 'sudo apt install nginx'
      @command_runner.run_command "sudo ufw allow 'Nginx Full'"
    end

  end
end
