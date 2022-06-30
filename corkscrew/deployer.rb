require_relative 'config'
require_relative 'remote_runner'
require_relative 'syncer'

module Corkscrew
  class Deployer

    def initialize(config_path=nil, options={})
      @config = Corkscrew::Config.new config_path, options
      @remote_runner = Corkscrew::RemoteRunner.new @config
      @syncer = Corkscrew::Syncer.new @config, @remote_runner
    end

    def deploy
      begin
        @syncer.sync

        # TODO: run install
        # @remote_runner.run_script ""

        # TODO: run build
        # @remote_runner.run_script ""

        # TODO: (re)start it
      ensure
        @remote_runner.close_connection
      end
    end

  end
end
