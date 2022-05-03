module Corkscrew
  class Deployer

    def initialize
      @config = Corkscrew::Config.new
      @remote_runner = Corkscrew::RemoteRunner.new @config
      @syncer = Corkscrew::Syncer.new @config
      @remote_builder = Corkscrew::RemoteBuilder.new @config, @remote_runner
    end

    def deploy
      begin
        @syncer.sync
        @remote_builder.build
      ensure
        @remote_runner.close_connection
      end
    end

  end
end
