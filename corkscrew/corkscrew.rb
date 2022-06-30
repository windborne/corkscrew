require 'thor'
require_relative 'config'
require_relative 'remote_runner'
require_relative 'syncer'

module Corkscrew

  class App < Thor

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

    private

    def with_context(config_path = nil)
      begin
        @config ||= Corkscrew::Config.new config_path, options
        yield
      ensure
        @remote_runner&.close_connection
      end
    end

    def remote_runner
      @remote_runner ||= Corkscrew::RemoteRunner.new @config
    end

    def syncer
      @syncer ||= Corkscrew::Syncer.new @config, remote_runner
    end

  end
end
