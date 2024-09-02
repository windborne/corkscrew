# Corkscrew

You have code (maybe a webserver?) that you want to run on another machine. Corkscrew is a tool to sync code and then run it.

Basic usage is designed to be simple, but it has lots of other features like zero-downtime deployments, cloud logging, and git status tracking to make it easy to run your code in production.

## Quickstart
After [installing](#installation), at the beginning of the project:
```shell
corkscrew generate
```

Then to deploy:
```shell
corkscrew deploy
```

## Installation
1. Download the file from the [releases page](https://github.com/windborne/corkscrew/releases) or (on a remote machine) `wget https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/corkscrew-LATEST-linux-x86_64.tar.gz`
2. Untar it
3. Add it to your path or link it to somewhere in your path already

For example:
```shell
tar -xzf corkscrew-LATEST-osx-x86_64.tar.gz -C /usr/local/lib/
ln -s /usr/local/lib/corkscrew/corkscrew /usr/local/bin/corkscrew
```

## Basic usage

A common path is to run `corkscrew generate` once at the beginning of the project, then `corkscrew deploy` after that.
The commands you will use the most often are:
- `generate` creates (or regenerates) an installation script
- `install` runs the installation script. Accepts a `--local` flag
- `sync` syncs code to the other machine. Accepts a `--local` flag
- `deploy` syncs code, calls the build script (if there is one), and restarts the server. Accepts a `--local` flag

All commands have a help option, eg ```corkscrew help generate``` or ```corkscrew help``` for general help.

Configuration lives in `corkscrew.json` by default.
You can generate this file interactively by calling `corkscrew generate [name, defaults to corkscrew.json]`

You can also pass in a path to a corkscrew config file to support deploying to multiple machines with different configs, eg `corkscrew deploy /path/to/config.json`.

## Why corkscrew
Corkscrew was created because I was in pain every time I had to get my services running on a remote machine. Either I was running dozens of different commands manually or I was spending ages tweaking verbose ansible configs. Ultimately, corkcrew's value isn't that it can do something new, but that it makes things easier. It should be fast not just to deploy code, but also to set up a new deployment in the first place.

While tools like dokku do something similar, they containerize the service; corkscrew is designed for running directly on the machine. Unlike eg ansible, corkscrew is built to minimize the configuration necessary -- and walk you through the config generation process.

At its core, corkscrew to the user can be broken into five parts:
1. Installation.
2. Code syncing. The goal of this part is to get the code you want to the place you want on the remote (or local) machine
3. Building. The goal of this part is to get your code ready to go live -- think webpack compilation.
4. Running. The goal of this part is to make your code run while handling details like logging and restarting on crash for you. In practice, this is a think layer around either screen or systemd.
5. Extra layers. Think nginx setup and logging.

At all points in the process, corkscrew tries to make the process as simple as possible so that you can create a new service with a simple `corkscrew generate` and then deploy it to a new machine with `corkscrew deploy`.

## Advanced features
Full list of commands:
- `help` prints available commands
- `version` prints the version of corkscrew
- `restart` restarts the server
- `start` starts the server
- `stop` stops the server
- `sync` syncs the code, but does nothing else
- `build` runs the build script, syncing before by default
- `nginx` sets up nginx for the app, generating the config before if needed
- `nginx_generate` generates an nginx configuration
- `setup_logs` sets up log forwarding to betterstack
- `metrics_node` sets up server to export metrics to prometheus
- `metrics_host` sets up server to have metrics in a grafana dashboard

### Service managers: systemd vs screen
Tl;dr: use systemd if at all possible.
It's designed to be reliable, and has lots of nice features -- not to mention that it's the default way linux systems manage services.

However, corkscrew does also support running services in a screen for the rarer use-cases where you can't use systemd.
This fires off a bash script that runs the server in a screen session in a loop such that it can restart; it also logs to `~/screenlogs/[name]`. As a rule, advanced features like zero-downtime deployments are not supported in screen mode, though it does set it up to start on system boot.

### Nginx configuration
Corkscrew can generate a nginx configuration and make sure nginx is installed.
```shell
corkscrew nginx
```

This is ultimately based on the `nginx` field in the corkscrew config file. You can also run `corkscrew nginx_generate` to generate the nginx configuration to see how it looks, and only then run `corkscrew nginx` to install it.
```json5
{
   "nginx": {
      "port": 0000, // port the server runs on
      "blue_port": 0000, // port the blue server runs on for zero-downtime deployments
      "host": "", // the hostname it should respond to requests from
      "cors": true // if true, will generate setup to allow CORS requests. Optional, defaults to false
   }
}
```

Note that this does not (yet) support SSL.
To add a certificate using certbot, you can run the following:
```shell
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot --nginx
```  

### Zero-downtime deployments
To use zero-downtime deployments, make sure your server uses the PORT environment variable and can safely have two copies running at once.
Corkscrew uses blue-green deployments to ensure zero-downtime deployments, with the zero downtime being enabled if the `blue_port` field is set in the nginx configuration (and the service manager is systemd).
Blue-green deployments work by starting a new server on the blue port, then switching the nginx configuration to point to the new server, then stopping the old server.

### Cloud logging
Logs can be forwarded to logtail/betterstack for easy viewing and search.
You will need a logtail token; you can get one by creating a new source at https://logs.betterstack.com/ and selecting vector as the type.
To set this up, run:

```shell
corkscrew setup_logs
```

### Git status tracking
On deploy, corkscrew stores the current git status in a file.
This stores the current git sha, the current branch, if it's dirty, and what time it was synced in `.git_status.json`.
This might look something like:
```json5
{
   "remote": "https://github.com/windborne/some_repo.git",
   "sha": "f9ca9401595c154eac4c126342d3e3cbeb4c0052",
   "branch": "main",
   "dirty": false,
   "modified_files": [

   ],
   "synced_at": "2024-09-01T18:12:05+0000"
}
```

Git also integrates with confirmation. 
If in your config `confirm_sync` is set to `dirty` or it is unset (as this behavior is the default), corkscrew will ask for confirmation before syncing if the repo is dirty.

### Metrics dashboards
Corkscrew can also set up a metrics dashboard using grafana and prometheus.
There are two pieces to this: the metrics node and the metrics host, which may or may not be the same machine.

Let's start with the metrics node.
This uses the [prometheus node exporter](https://github.com/prometheus/node_exporter) to make metrics available on port 9100.
To set this up, run:
```shell
corkscrew metrics_node
```

Next, the metrics host.
This uses [prometheus](https://prometheus.io/) to scrape metrics from the node exporter and then [grafana](https://grafana.com/) to display them.
To set this up, run:
```shell
corkscrew metrics_host
```

This installs prometheus and grafana, and sets up a dashboard for the node exporter.

### Full configuration options
By default, you'll probably just want to use the things generated by `corkscrew generate`.
However, we include a full list of options here for reference.

```json5
{
   "name": "your_service", // REQUIRED. Should be snake case
   "run": "start_server.sh", // the run script. May be a file or a bash command. REQUIRED
   "service_manager": "systemd", // may be systemd or screen. Optional, defaults to systemd
   "restart_on_deploy": true, // defaults to true; if false, won't restart the server after deploying
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
      "blue_port": 0000, // port the blue server runs on for zero-downtime deployments
      "host": "", // the hostname it should respond to requests from
      "cors": true // if true, will generate setup to allow CORS requests. Optional, defaults to false
   },
   "logfile": "/path/to/logfile", // For log forwarding to cloud: where logs are stored. With a normal config, this is set automatically
   "service_name": "your_service", // The name of the service if it's been renamed from the default
   "git_info": ".git_status.json", // where to store git info. Optional, defaults to .git_status.json. If false, won't store git info
   "confirm_sync": "dirty", // when to ask for confirmation on syncing. May be never, always, or dirty (ie, only if the repo is dirty). Optional, defaults to dirty
}
```

## Recommendations
Make your install script idempotent so that you can update it then run `corkscrew install` again safely.

We also recommend having as little in your build script as possible, since it gets run every deploy; consider moving some of its contents to the install script if needed.

## Troubleshooting

### rsync: connection unexpectedly closed
Tl;dr: don't worry about it; it doesn't actually affect the deployment.

The root cause of this is likely that rsync isn't installed on the target system.
This is common on google cloud.
See [this stackoverflow answer](https://unix.stackexchange.com/questions/309176/connection-unexpectedly-closed-while-using-rsync-with-various-command-line-arg) for more details.

To fix, install `rsync` on the target machine (eg ```sudo apt-get install rsync```).

### I changed NAME.service, but it didn't seem to have any effect?
You need to:
1. Make sure `/etc/systemd/system/[name].service` has the right contents (and also `/etc/systemd/system/[name]_blue.service` if you have zero downtime deployments).

   When you ran `corskcrew install` the first time, it would have copied the service file to `/etc/systemd/system/[name].service`. But if you've made changes to the service file and haven't run `corkscrew install` since, it will be out of date. You can thus either run `corkscrew install` again, or copy the service file manually to skip the rest of the install process.

2. Run `sudo systemctl daemon-reload` to reload the systemd daemon. This will make sure that systemd knows about the changes you've made to the service file.

### I changed the nginx config, but it didn't seem to have any effect?
You need to copy the config to `/etc/nginx/sites-available/[name]`.
Like with editing a service file, this was done for you on initial generation, but needs to be done manually after changes.
We do NOT recommend re-running `corkscrew nginx` as it will overwrite your changes.

Run `sudo nginx -t` to test the nginx configuration, then run `sudo nginx -s` to reload the nginx configuration.

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