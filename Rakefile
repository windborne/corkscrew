# For Bundler.with_clean_env
require 'bundler/setup'

PACKAGE_NAME = "corkscrew"
VERSION = "0.9.9"
TRAVELING_RUBY_VERSION = "20230803-3.0.6"

# right now you can only package on the same architecture you'll deploy to
desc "Package your app"
task :package => ['package:linux:x86_64', 'package:osx']

namespace :package do
  namespace :linux do
    desc "Package your app for Linux x86_64"
    task :x86_64 => [:bundle_install] do
      create_package("linux-x86_64")
    end
  end

  desc "Package your app for OS X"
  task :osx => [:bundle_install] do
    create_package("osx-x86_64")
  end

  desc "Install gems to local directory"
  task :bundle_install do
    if RUBY_VERSION !~ /^3\.0\./
      abort "You can only 'bundle install' using Ruby 3.0, because that's what Traveling Ruby uses."
    end
    sh "rm -rf packaging/tmp"
    sh "mkdir packaging/tmp"
    sh "cp Gemfile Gemfile.lock packaging/tmp/"
    Bundler.with_clean_env do
      sh "cd packaging/tmp && env BUNDLE_IGNORE_CONFIG=1 bundle install --path ../vendor --without development"
    end
    sh "rm -rf packaging/tmp"
    sh "rm -f packaging/vendor/*/*/cache/*"
    sh "rm -rf packaging/vendor/ruby/*/extensions"
    sh "find packaging/vendor/ruby/*/gems -name '*.so' | xargs rm -f"
    sh "find packaging/vendor/ruby/*/gems -name '*.bundle' | xargs rm -f"
    sh "find packaging/vendor/ruby/*/gems -name '*.o' | xargs rm -f"
  end
end

def create_package(target)
  package_dir = "packaging/#{PACKAGE_NAME}"

  sh "rm -rf #{package_dir}"
  sh "mkdir #{package_dir}"
  sh "mkdir -p #{package_dir}/lib/app"
  sh "cp corkscrew.rb #{package_dir}/lib/app/"
  sh "cp -r corkscrew #{package_dir}/lib/app/"
  sh "cp -r data #{package_dir}/lib/app/"
  sh "mkdir #{package_dir}/lib/ruby"
  sh "tar -xzf traveling-ruby/#{target.split('-').first}/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz -C #{package_dir}/lib/ruby"
  sh "cp packaging/wrapper.sh #{package_dir}/#{PACKAGE_NAME}"
  sh "cp -pR packaging/vendor #{package_dir}/lib/"
  sh "cp Gemfile Gemfile.lock #{package_dir}/lib/vendor/"
  sh "mkdir #{package_dir}/lib/vendor/.bundle"
  sh "cp packaging/bundler-config #{package_dir}/lib/vendor/.bundle/config"
  %w[bcrypt_pbkdf-1.1.0 ed25519-1.3.0].each do |gem|
    sh "tar -xzf traveling-ruby/#{target.split('-').first}/traveling-ruby-gems-#{TRAVELING_RUBY_VERSION}-#{target}/#{gem}.tar.gz " +
         "-C #{package_dir}/lib/vendor/ruby"
  end

  unless ENV['DIR_ONLY']
    sh "tar -czf packaging/#{PACKAGE_NAME}-#{VERSION}-#{target}.tar.gz -C packaging #{PACKAGE_NAME}"
    sh "rm -rf #{package_dir}"
    sh "cp packaging/#{PACKAGE_NAME}-#{VERSION}-#{target}.tar.gz packaging/#{PACKAGE_NAME}-LATEST-#{target}.tar.gz"
  end
end
