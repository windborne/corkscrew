require_relative '../corkscrew/corkscrew'

def deploy_from(config_path)
  Corkscrew::Deployer.new(config_path, { local: config_path.include?('local') }).deploy
end

deploy_from ARGV[0]
