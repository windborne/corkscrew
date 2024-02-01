# Corkscrew

Corkscrew is designed to support building, running, and managing services. 
While tools like dokku do something similar, they containerize the service; corkscrew is designed for running directly on the machine.
Unlike eg ansible, corkscrew is built to minimize the configuration necessary.

At its core, corkscrew to the user can be broken into four parts:
1. Installation. 
2. Code syncing. The goal of this part is to get the code you want to the place you want on the remote (or local) machine
3. Building. The goal of this part is to get your code ready to go live -- think webpack compilation. 
4. Running. The goal of this part is to make your code run while handling details like logging and restarting on crash for you. In practice, this is a think layer around either screen or systemd.

At all points in the process, corkscrew tries to make the process as simple as possible so that you can create a new service with a simple `corkscrew generate` and then deploy it to a new machine with `corkscrew deploy`.

## Basic usage
At the beginning of the project:
```shell
corkscrew generate
```

Then to deploy:
```shell
corkscrew deploy
```

## Installation
1. Download the file from the [releases page](https://github.com/windborne/corkscrew/releases)
2. Untar it
3. Add it to your path or link it to somewhere in your path already 

For example:
```shell
tar -xzf corkscrew-0.9.8-osx-x86_64.tar.gz -C /usr/local/lib/
ln -s /usr/local/lib/corkscrew/corkscrew /usr/local/bin/corkscrew
```

## Configuration
Configuration lives in `corkscrew.json` by default.
You can generate this file interactively by calling `corkscrew generate [name, defaults to corkscrew.json]`

## Commands
All commands have a help option, eg ```corkscrew help generate```.
You can also pass in a path to a corkscrew config file if there is not a 

### Core
These are the commands you will use most commonly.
A common path is to run `corkscrew generate` once at the beginning of the project, then `corkscrew deploy` after that.

- `generate` creates (or regenerates) an installation script
- `install` runs the installation script. Accepts a `--local` flag
- `deploy` syncs code, calls the build script (if there is one), and restarts the server. Accepts a `--local` flag

### Utility
- `help` prints available commands
- `restart` restarts the server
- `start` starts the server
- `stop` stops the server
- `sync` syncs the code, but does nothing else
- `build` runs the build script, syncing before by default
- `nginx` sets up nginx for the app, generating the config before if needed
- `nginx_generate` generates an nginx configuration
- `setup_logs` sets up log forwarding to betterstack

## Recommendations
Make your install script idempotent so that you can update it then run `corkscrew install` again safely.

We also recommend having as little in your build script as possible, since it gets run every deploy; consider moving some of its contents to the install script if needed.

## Full configuration options
By default, you'll probably just want to use the things generated by `corkscrew generate`.
However, we include a full list of options here for reference.

```json5
{
  "name": "your_service", // REQUIRED. Should be snake case
  "run": "start_server.sh", // the run script. May be a file or a bash command. REQUIRED
  "service_manager": "systemd", // may be systemd or screen. Optional, defaults to systemd
  "root": ".", // the root of the code you want to deploy. Optional, defaults to current repo
  "run_root": "", // the place where you want to run your code from, relative to root. Optional (since usually you run from root)
  "sync": "rsync", // how to sync code. May be rsync or git. Optional, defaults to rsync. You can also always edit code locally
  "ssh": { // the ssh parameters. Optional, but if not provided you will only be able to deploy locally
    "host": "a.windbornesystems.com",
    "user": "windborne",
    "identity": "/path/to/identity/file", // an SSH identity file for connecting 
    "no_pwd": false // if true, will provide an empty string when asked for the password. Useful for some cloud environments.
  },
  "deploy_path": "/srv/", // where to sync the code to on the remote host. If not provided, you won't be able to deploy
  "install": "install.sh", // the install script. May be a file or a bash command. Optional
  "build": "build.sh", // the build script. May be a file or a bash command. Optional
  "environment_file": ".env", // An environment file for systemd. Optional
  "nginx": { // optional config to set up nginx
    "port": 0000, // port the server runs on
    "host": "", // the hostname it should respond to requests from
    "cors": true // if true, will generate setup to allow CORS requests. Optional, defaults to false
  },
  "logfile": "/path/to/logfile", // For log forwarding to cloud: where logs are stored. With a normal config, this is set automatically
  "service_name": "your_service", // The name of the service if it's been renamed from the default
}
```

## Development
### Philosophies
1. Minimum effort. Things should just work without you having to worry about how; there should be sane defaults for everything we can manage
2. Delegation to existing tools. We don't need to re-invent systemd; instead, we should delegate as much work as possible to core unix utilities.  
3. Compatibility with existing tools. You should be able to deploy completely manually and not have it break things, and also be able to go outside the system whenever you want

### Packaging a new version
Corkscrew is packaged into an executable with [Traveling Ruby](https://github.com/phusion/traveling-ruby).
This enables us to distribute an executable without any dependencies: users don't need to worry about installing ruby or anything else.
Unfortunately, because we use gems with native extensions, we cannot use the pre-compiled traveling ruby binaries, and instead need to compile it ourselves.
To this end, traveling-ruby is cloned within this repository and the Gemfile (within [traveling-ruby/shared/gemfiles/20230803](traveling-ruby/shared/gemfiles/20210107)) modified.

To build, run either `rake package:osx` or `rake package:linux:x86_64`, or both with `rake package`.
This requires that you have the traveling rubies built: you can read the [osx](traveling-ruby/osx/README.md) and [linux](traveling-ruby/linux/README.md) readmes for instructions on how.
OSX can only be built on OSX; linux (as it's dockerized) can be run on either.

Once built, add it to github and to s3 (https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-LATEST-linux-x86_64.tar.gz)