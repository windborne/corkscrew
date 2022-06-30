require 'rb_json5'

module Corkscrew
  class Config

    def initialize(config_path = nil, options={})
      config_path = 'corkscrew.json' if config_path.nil?

      @options = options.transform_keys(&:to_sym)
      @raw = ::RbJSON5.parse(File.read(config_path))
      @defaults = ::RbJSON5.parse(File.read(File.join(__dir__,  '..', 'data', 'corkscrew-defaults.json')))
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

  end
end
