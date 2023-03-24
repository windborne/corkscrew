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
      test = @command_runner.run_command "sudo nginx -t"
      unless test.strip.end_with? 'is successful'
        puts 'Invalid nginx config; aborting'
        return
      end

      @command_runner.run_command "sudo systemctl restart nginx"
      puts 'Config updated and nginx restarted!'
    end

    def install_nginx
      @command_runner.run_command 'sudo apt install nginx'
      @command_runner.run_command "sudo ufw allow 'Nginx Full'"
    end

  end
end
