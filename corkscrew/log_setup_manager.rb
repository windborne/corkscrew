require 'yaml'
require_relative './command_runner'

module Corkscrew
  class LogSetupManager < Thor
    include Corkscrew::Helpers::QueryHelpers

    def initialize(config, command_runner, syncer)
      @config = config
      @command_runner = command_runner
      @syncer = syncer
    end

    no_commands do
      def configure_app
        install_vector

        raw_vector_conf = get_existing_config
        if raw_vector_conf.include?('No such file or directory')
          vector_conf = {}
        else
          vector_conf = YAML.safe_load(raw_vector_conf)
        end

        vector_conf['sources'] ||= {}
        vector_conf['sinks'] ||= {}

        sink_name = 'corkscrew_better_stack_http_sink'
        vector_conf['sinks'][sink_name] = logtail_sink if vector_conf['sinks'][sink_name].nil?

        if @config.service_manager == 'systemd'
          source_name = 'systemd_source'
          vector_conf['sources'][source_name] = journald_source if vector_conf['sources'][source_name].nil?

          service_name = @config.service_name || @config.name
          puts "Forwarding logs from #{service_name} to better stack"

          vector_conf['sources'][source_name]['include_units'] << service_name unless vector_conf['sources'][source_name]['include_units'].include?(service_name)
        else
          source_name = 'screenlogs_source'
          vector_conf['sources'][source_name] = logfile_source if vector_conf['sources'][source_name].nil?

          logfile = @config.logfile
          logfile = "/home/#{@config.ssh['user']}/screenlogs/#{@config.name}" if logfile.nil?
          puts "Forwarding logs from #{logfile} to better stack"

          vector_conf['sources'][source_name]['include'] << logfile unless vector_conf['sources'][source_name]['include'].include?(logfile)
        end

        vector_conf['sinks'][sink_name]['inputs'] << source_name unless vector_conf['sinks'][sink_name]['inputs'].include?(source_name)

        write_config(vector_conf)

        enable_vector
        restart_vector
      end

      def logfile_source
        {
          'type' => 'file',
          'read_from' => 'beginning',
          'ignore_older_secs' => 600,
          'include' => []
        }
      end

      def journald_source
        {
          'type' => 'journald',
          'include_units' => []
        }
      end

      def logtail_sink
        token = ask_nonempty('Logtail token:')
        {
          'type' => 'http',
          'method' => 'post',
          'proxy' => {
            'enabled' => false
          },
          'uri' => 'https://in.logs.betterstack.com/',
          'encoding' => {
            'codec' => 'json'
          },
          'auth' => {
            'strategy' => 'bearer',
            'token' => token
          },
          'inputs' => []
        }
      end

      def get_existing_config
        @command_runner.run_command 'cat /etc/vector/vector.yaml', print_output: false
      end

      def write_config(vector_conf)
        tmp_file = "/tmp/vector_#{(rand*1e10).to_i.to_s(36)}.yaml"
        @command_runner.run_command "echo '#{YAML.dump(vector_conf)}' > #{tmp_file}"
        @command_runner.run_command "sudo mv #{tmp_file} /etc/vector/vector.yaml"
      end

      def install_vector
        has_vector = @command_runner.run_command 'which vector'
        return if has_vector.include?('vector')

        @command_runner.run_command 'bash -c "$(curl -L https://setup.vector.dev)"'
        @command_runner.run_command 'sudo apt-get install vector'

        # delete default config so it doesn't cause weirdness
        @command_runner.run_command "sudo rm /etc/vector/vector.yaml"
      end

      def enable_vector
        @command_runner.run_command 'sudo systemctl enable vector'
      end

      def restart_vector
        @command_runner.run_command 'sudo systemctl restart vector'
      end
    end

  end
end
