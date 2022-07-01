require 'rb_json5'

module Corkscrew
  class Config

    attr_reader :options

    def initialize(config_path = nil, options={})
      @config_path = config_path || 'corkscrew.json'

      @options = options.transform_keys(&:to_sym)
      @raw = ::RbJSON5.parse(File.read(@config_path))
      @defaults = ::RbJSON5.parse(File.read(File.join(corkscrew_data_dir, 'corkscrew-defaults.json')))
    end

    def root_dir
      File.absolute_path(File.join(config_dir, root))
    end

    def config_dir
      File.dirname @config_path
    end

    def corkscrew_data_dir
      File.join(__dir__,  '..', 'data')
    end

    def install_command
      convert_to_command(install)
    end

    def run_command
      convert_to_command(run)
    end

    def build_command
      convert_to_command(build)
    end

    def run_command_absolute
      "cd #{deploy_path} && #{convert_to_command(run)}"
    end

    def start_screen_command
      "cd #{deploy_path} && bash start_screen.sh"
    end

    def local?
      @options[:local]
    end

    def method_missing(name, *_args, &_block)
      name = name.to_s

      return @defaults[name] if !@raw.key?(name) && @defaults.key?(name)

      @raw[name]
    end

    def respond_to_missing(method_name, _include_private=false)
      @raw.key(method_name.to_s) || @defaults.key?(method_name.to_s)
    end

    private

    def convert_to_command(command)
      return nil if command.nil?
      return "bash #{command}" if command.split(' ').length == 1 && command.end_with?('.sh')

      command
    end

  end
end
