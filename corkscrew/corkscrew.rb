require 'thor'
require_relative 'config'
require_relative 'command_runner'
require_relative 'syncer'
require_relative 'generator'

module Corkscrew

  class App < Thor

    def self.exit_on_failure?
      true
    end

    desc 'deploy [corkscrew.json]', 'Deploys the app'
    option :local, type: :boolean, desc: 'If provided, will assume the deployment path is on the current machine'
    def deploy(config_path = nil)
      with_context(config_path) do
        invoke :sync, config_path
      end
    end

    desc 'sync [corkscrew.json]', 'Syncs the app'
    option :local, type: :boolean, desc: 'If provided, will assume the deployment path is on the current machine'
    def sync(config_path = nil)
      with_context(config_path) do
        syncer.sync
      end
    end

    desc 'generate [corkscrew.json]', 'Generates installation files'
    def generate(config_path = nil)
      with_context(config_path) do
        generator.generate
      end
    end

    desc 'install [corkscrew.json]', 'Runs installation script'
    option :sync, type: :boolean, desc: 'If true, will sync the installation script first'
    option :local, type: :boolean, desc: 'If provided, will assume the deployment path is on the current machine'
    def install(config_path = nil)
      with_context(config_path) do
        sync if options[:sync]
        command_runner.run_command @config.install_command, cwd: @config.deploy_path
      end
    end

    private

    def with_context(config_path = nil)
      @context_depth ||= 0

      begin
        @context_depth += 1
        @config ||= Corkscrew::Config.new config_path, options
        yield
        @context_depth -= 1
      ensure
        @command_runner&.close_connection if @context_depth <= 0
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

  end
end
