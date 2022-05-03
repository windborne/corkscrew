module Corkscrew
  class Config

    def initialize(config_path = 'corkscrew.json')
      @raw = RbJSON5.parse(File.read(config_path))
      @defaults = RbJSON5.parse(File.read('data/corkscrew-defaults.json'))
    end

    def method_missing(name, *_args, &_block)
      return @defaults[name] if !@raw.key?(name) && @defaults.key?(name)

      @raw[name]
    end

  end
end
