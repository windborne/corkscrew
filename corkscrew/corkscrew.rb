require 'thor'
require_relative 'config'
require_relative 'command_runner'
require_relative 'syncer'
require_relative 'generator'
require_relative 'service_manager'
require_relative 'nginx_manager'
require_relative 'log_setup_manager'
require_relative 'metrics_setup_manager'
require_relative 'version'
require_relative 'helpers/query_helpers'

module Corkscrew

  class App < Thor

    include Corkscrew::Helpers::QueryHelpers

    def self.exit_on_failure?
      true
    end

    desc 'version', 'Prints the version'
    def version
      puts "Corkscrew version #{Corkscrew::VERSION}"
    end

    map "--version" => :version
    map "--help" => :help

    desc 'deploy [corkscrew.json]', 'Deploys the app'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def deploy(config_path = nil)
      with_context(config_path) do
        generate(config_path) if !@config.has_install_script? && ask_default_yes("You're missing an install script (at least on this machine). Do you want to generate one? [Yn]")
        sync config_path
        command_runner.run_command @config.build_command, cwd: @config.run_path unless @config.build_command.nil?
        service_manager.restart unless @config.restart_on_deploy == false
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

        if @config.has_nginx? && ask_default_yes("Do you want to set up nginx now? You can also run `corkscrew nginx yourself`. [Yn]")
          generator.generate_nginx if !@config.has_nginx_config? && ask_default_yes("You're missing an nginx config (at least on this machine). Do you want to generate one? [Yn]")
          nginx_manager.configure_app
        end

        if ask_default_yes("Now that files have been generated, do you want to run the install script? You can also run `corkscrew install` yourself after editing it. [Yn]")
          @config.local = ask_default_no("Are you on the same machine you deploy to? [yN]") if options[:local].nil?
          sync(config_path)
          command_runner.run_command @config.install_command, cwd: @config.run_path
        end
      end
    end

    desc 'install [corkscrew.json]', 'Runs the installation script'
    option :sync, type: :boolean, desc: 'If true, will sync code before installing', default: true
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def install(config_path = nil)
      with_context(config_path) do
        generator.generate if !@config.has_install_script? && ask_default_yes("You're missing an install script (at least on this machine). Do you want to generate one? [Yn]")
        sync if options[:sync]
        command_runner.run_command @config.install_command, cwd: @config.run_path
      end
    end

    desc 'setup_logs [corkscrew.json]', 'Sets up log forwarding to logtail for the app'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def setup_logs(config_path = nil)
      with_context(config_path) do
        log_setup_manager.configure_app
      end
    end

    desc 'nginx [corkscrew.json]', 'Sets up nginx for the app'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def nginx(config_path = nil)
      with_context(config_path) do
        generator.generate_nginx if !@config.has_nginx_config? && ask_default_yes("You're missing an nginx config (at least on this machine). Do you want to generate one? [Yn]")
        nginx_manager.configure_app
      end
    end

    desc 'nginx_generate [corkscrew.json]', 'Generates the nginx config file for the app'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def nginx_generate(config_path = nil)
      with_context(config_path) do
        generator.generate_nginx
      end
    end

    desc 'metrics_node [corkscrew.json]', 'Sets up the server as a node that can export metrics to Prometheus'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def metrics_node(config_path = nil)
      with_context(config_path) do
        metrics_setup_manager.configure_node
      end
    end

    desc 'metrics_host [corkscrew.json]', 'Sets up the server as a host with Prometheus and Grafana'
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def metrics_host(config_path = nil)
      with_context(config_path) do
        metrics_setup_manager.configure_host
      end
    end

    desc 'build [corkscrew.json]', 'Runs the build script'
    option :sync, type: :boolean, desc: 'If true, will sync code before installing', default: true
    option :local, type: :boolean, desc: 'If true, will assume the deployment path is on the current machine'
    def build(config_path = nil)
      with_context(config_path) do
        sync if options[:sync]
        command_runner.run_command @config.build_command, cwd: @config.run_path
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
        Corkscrew::Generator.new(nil).generate_config(config_path) if @config.nil? && !File.exist?(config_path || 'corkscrew.json') && ask_default_yes("No corkscrew config found. Would you like to generate one? [Yn]")
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

    def nginx_manager
      @nginx_manager ||= Corkscrew::NginxManager.new @config, command_runner, syncer
    end

    def log_setup_manager
      @log_setup_manager ||= Corkscrew::LogSetupManager.new @config, command_runner, syncer
    end

    def metrics_setup_manager
      @metrics_setup_manager ||= Corkscrew::MetricsSetupManager.new @config, command_runner, syncer, nginx_manager
    end

    def service_manager
      @service_manager ||= Corkscrew::ServiceManager.new @config, command_runner, nginx_manager
    end

  end
end
