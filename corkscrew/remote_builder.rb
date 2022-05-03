module Corkscrew
  class RemoteBuilder

    def initialize(config, remote_runner)
      @config = config
      @remote_runner = remote_runner
    end

    def install
      return unless @config.install

      @remote_runner.run_file_or_script @config.install
    end

    def build
      install

      @remote_runner.run_file_or_script @config.install

      set_up_runner
    end

    def set_up_runner
      return set_up_systemd if @config.service_manager == 'systemd'
      return set_up_screen if @config.service_manager == 'screen'

      raise 'Unsupported service manager'
    end

    def set_up_systemd
      #
    end

    def set_up_screen

    end

  end
end
