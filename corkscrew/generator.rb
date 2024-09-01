require 'json'
require 'thor'
require_relative 'helpers/query_helpers'

module Corkscrew
  class Generator < Thor
    include Thor::Actions
    include Corkscrew::Helpers::QueryHelpers

    def initialize(config)
      @config = config
    end

    no_commands do

      def generate
        Corkscrew::Generator.source_root(@config.corkscrew_data_dir)
        self.destination_root = @config.run_root_dir

        if @config.service_manager == 'systemd'
          @is_blue = false
          template(
            'systemd_template.service.erb',
            "#{@config.name}.service"
          )

          if @config.zero_downtime_deployments?
            @is_blue = true
            template(
              'systemd_template.service.erb',
              "#{@config.name}_blue.service"
            )
          end

          template(
            'install_service_template.sh.erb',
            @config.install
          )
        elsif @config.service_manager == 'screen'
          template(
            'screen_template.sh.erb',
            "start_screen.sh"
          )

          template(
            'install_screen_template.sh.erb',
            @config.install
          )
        else
          raise 'Invalid service manager'
        end

        generate_nginx unless @config.no_nginx?
      end

      def generate_nginx
        @config.require_nginx!

        Corkscrew::Generator.source_root(@config.corkscrew_data_dir)
        self.destination_root = @config.run_root_dir

        template(
          'nginx.conf.erb',
          @config.nginx['config']
        )
      end

      def generate_config(config_path=nil)
        config_path ||= 'corkscrew.json'

        name = ask_nonempty("Name of service (snake_case strongly recommended):")
        run = ask_nonempty("Start command (eg `python3 main.py`):")
        service_manager = ask("Service manager:", limited_to: %w[systemd screen], default: 'systemd')
        has_ssh = ask_default_yes("Has a remote host [Yn]:")
        ssh_user = has_ssh ? ask_nonempty("SSH user:") : nil
        ssh_host = has_ssh ? ask_nonempty("SSH host:") : nil
        ssh_no_password = has_ssh ? ask_default_no("SSH user is passwordless (often true on ec2) [yN]:") : nil
        deploy_path = ask_nonempty("Deploy path:")
        root = ask("Source root (relative to #{File.join(File.dirname(config_path))}):", default: '.')
        install = ask("Install script:", default: 'install.sh')
        build = ask("Build script:", default: '')
        has_nginx = ask_default_yes("Will be served with nginx [Yn]:")
        port = has_nginx ? ask_nonempty("Port service runs on:") : nil
        host = has_nginx ? ask_nonempty("Hostname (eg #{name}.windbornesystems.com) to link to service:") : nil
        has_cors = has_nginx ? ask_default_yes("Enable CORS [Yn]:") : nil
        zdd_possible = service_manager == 'systemd' && has_nginx

        say("Skipping zero-downtime deployment questions; not supported without nginx and systemd") unless zdd_possible
        zero_downtime_deployments = zdd_possible ? ask_default_yes("Enable zero-downtime deployments [Yn]:") : false
        blue_port = zero_downtime_deployments ? ask_nonempty("Secondary port for parallel deployment:") : nil
        regularly_restart = (service_manager == 'systemd' && !zero_downtime_deployments) ? ask_default_yes("Regularly restart service [Yn]:") : false

        say("Writing to #{config_path}")

        contents = {
          name: name,
          run: run,
          service_manager: service_manager,
          root: root,
          ssh: has_ssh ? {
            user: ssh_user,
            host: ssh_host,
            no_pwd: ssh_no_password ? true : nil
          }.compact : nil,
          deploy_path: deploy_path,
          install: install,
          build: build.empty? ? nil : build,
          regularly_restart: regularly_restart,
          nginx: has_nginx ? {
            port: port,
            host: host,
            cors: has_cors,
            zero_downtime_deployments: zero_downtime_deployments,
            blue_port: blue_port
          }.compact : nil
        }.compact

        say(JSON.pretty_generate(contents), "\e[2m")

        self.destination_root = '.'
        create_file config_path, JSON.pretty_generate(contents)
      end

      def options
        @config&.options || {}
      end

    end

  end
end
