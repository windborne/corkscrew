require 'rb_json5'

module Corkscrew
  class Config

    attr_reader :options

    class ConfigError < StandardError

    end

    def initialize(config_path = nil, options={})
      @config_path = config_path || 'corkscrew.json'
      raise ConfigError, "Config file #{@config_path} does not exist" unless File.exist? @config_path

      @options = options.map {|key, value| [key.to_sym, value]}.to_h # would love to use transform_keys, but, well traveling ruby uses ruby 2.4
      @raw = ::RbJSON5.parse(File.read(@config_path))
      @defaults = ::RbJSON5.parse(File.read(File.join(corkscrew_data_dir, 'corkscrew-defaults.json')))
    end

    def root_dir
      File.absolute_path(File.join(config_dir, root))
    end

    def run_root_dir
      return root_dir if run_root.nil? || run_root.empty?

      File.join(root_dir, run_root)
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
      "cd #{run_path} && #{convert_to_command(run)}"
    end

    def start_screen_command
      "cd #{run_path} && bash start_screen.sh"
    end

    def run_path
      return deploy_path if run_root.nil? || run_root.empty?

      File.join(deploy_path, run_root)
    end

    def run_user
      return fetch('run_user') unless fetch('run_user').nil?

      return nil if ssh.nil?

      ssh['user']
    end

    def environment_path
      return nil if environment_file.nil? || environment_file.empty?

      File.join(run_path, environment_file)
    end

    def local?
      @options[:local]
    end

    def local=(value)
      @options[:local] = value
    end

    def require_deploy_path!
      raise ConfigError, 'A deploy path is required to sync code' if deploy_path.nil? || deploy_path.empty?
    end

    def require_ssh_config!
      raise ConfigError, 'SSH config is required to run remotely' if ssh.nil? || ssh['user'].nil? || ssh['host'].nil?
    end

    def has_install_script?
      return false if install.nil?

      File.exist? File.join(run_root_dir, install)
    end

    def ssh_identity
      identity = fetch('ssh')&.dig('identity')
      return nil if identity.nil? || identity.strip == ''

      identity.gsub(/\A~/) { `echo ~`.strip }
    end

    def ssh_options
      ssh = fetch('ssh')
      {
        keys: ssh['identity'].nil? ? nil : [*ssh['identity']]
      }.compact
    end

    def fetch(name)
      name = name.to_s

      return @defaults[name] if !@raw.key?(name) && @defaults.key?(name)

      @raw[name]
    end

    def method_missing(name, *_args, &_block)
      fetch(name)
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
