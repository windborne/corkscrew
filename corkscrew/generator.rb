require 'thor'

module Corkscrew
  class Generator < Thor
    include Thor::Actions
    def initialize(config)
      @config = config
    end

    no_commands do

      def generate
        Corkscrew::Generator.source_root(@config.corkscrew_data_dir)
        self.destination_root = @config.root_dir

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

      def options
        @config.options
      end

    end

  end
end
