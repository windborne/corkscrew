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
          template(
            'systemd_template.service.erb',
            "#{@config.name}.service"
          )

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
      end

      def generate_config(config_path=nil)
        config_path ||= 'corkscrew.json'

        name = ask_nonempty("Name of service (snake_case strongly recommended):")
        run = ask_nonempty("Start command (eg `python3 main.py`):")
        service_manager = ask("Service manager:", limited_to: %w[systemd screen], default: 'systemd')
        has_ssh = ask_default_yes("Has a remote host [Yn]:")
        ssh_user = has_ssh ? ask_nonempty("SSH user:") : nil
        ssh_host = has_ssh ? ask_nonempty("SSH host:") : nil
        deploy_path = ask_nonempty("Deploy path:")
        root = ask("Source root (relative to #{File.join(File.dirname(config_path))}):", default: '.')
        install = ask("Install script:", default: 'install.sh')
        build = ask("Build script:", default: '')

        say("Writing to #{config_path}")

        contents = {
          name: name,
          run: run,
          service_manager: service_manager,
          root: root,
          ssh: has_ssh ? {
            user: ssh_user,
            host: ssh_host
          } : nil,
          deploy_path: deploy_path,
          install: install,
          build: build.empty? ? nil : build
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
