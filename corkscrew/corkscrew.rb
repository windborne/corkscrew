require 'thor'
require_relative 'config'
require_relative 'command_runner'
require_relative 'syncer'
require_relative 'generator'
require_relative 'service_manager'
require_relative 'helpers/query_helpers'

module Corkscrew

  class App < Thor

    include Corkscrew::Helpers::QueryHelpers

    def self.exit_on_failure?
      true
    end

    desc 'deploy [corkscrew.json]', 'Deploys the app'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def deploy(config_path = nil)
      with_context(config_path) do
        generate(config_path) if !@config.has_install_script? && ask_default_yes("You're missing an install script (at least on this machine). Do you want to generate one? [Yn]")
        sync config_path
        command_runner.run_command @config.build_command, cwd: @config.deploy_path unless @config.build_command.nil?
        service_manager.restart
      end
    end

    desc 'sync [corkscrew.json]', 'Syncs the app'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def sync(config_path = nil)
      with_context(config_path) do
        syncer.sync
      end
    end

    desc 'generate [corkscrew.json]', 'Generates installation files'
    def generate(config_path = nil)
      with_context(config_path) do
        generator.generate

        if ask_default_yes("Now that files have been generated, do you want to run them? You can also run `corkscrew install` yourself. [Yn]")
          @config.local = ask_default_no("Are you on the same machine you deploy to? [yN]") if options[:local].nil?
          sync(config_path)
          command_runner.run_command @config.install_command, cwd: @config.deploy_path
        end
      end
    end

    desc 'install [corkscrew.json]', 'Runs installation script'
    option :sync, type: :boolean, desc: 'If true, will sync code before installing', default: true
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def install(config_path = nil)
      with_context(config_path) do
        generator.generate if !@config.has_install_script? && ask_default_yes("You're missing an install script (at least on this machine). Do you want to generate one? [Yn]")
        sync if options[:sync]
        command_runner.run_command @config.install_command, cwd: @config.deploy_path
      end
    end

    desc 'restart [corkscrew.json]', 'Restarts the app'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def restart(config_path = nil)
      with_context(config_path) do
        service_manager.restart
      end
    end

    desc 'start [corkscrew.json]', 'Starts the app'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def start(config_path = nil)
      with_context(config_path) do
        service_manager.start
      end
    end

    desc 'stop [corkscrew.json]', 'Stops the app'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def stop(config_path = nil)
      with_context(config_path) do
        service_manager.stop
      end
    end

    private

    def with_context(config_path = nil)
      @context_depth ||= 0
      config_depth_was_zero = @context_depth == 0

      begin
        @context_depth += 1
        Corkscrew::Generator.new(nil).generate_config(config_path) if !File.exist?(config_path || 'corkscrew.json') && ask_default_yes("No corkscrew config found. Would you like to generate one? [Yn]")
        @config ||= Corkscrew::Config.new config_path, options
        yield
        @context_depth -= 1
      ensure
        @command_runner&.close_connection if config_depth_was_zero
      end
    end

    def generator
      @generator ||= Corkscrew::Generator.new @config
    end

    def command_runner
      @command_runner ||= Corkscrew::CommandRunner.new @config
    end

    def syncer
      @syncer ||= Corkscrew::Syncer.new @config, command_runner
    end

    def service_manager
      @service_manager ||= Corkscrew::ServiceManager.new @config, command_runner
    end

  end
end
