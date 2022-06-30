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

## Configuration
Configuration lives in `corkscrew.json`.

```json5
{
  "name": "your_service", // REQUIRED. Should be snake case
  "run": "start_server.sh", // the run script. May be a file or a bash command. REQUIRED
  "service_manager": "systemd", // may be systemd or screen. Optional, defaults to systemd
  "root": ".", // the root of the code you want to deploy. Optional, defaults to current repo
  "sync": "rsync", // how to sync code. May be rsync or git. Optional, defaults to rsync. You can also always edit code locally
  "ssh": { // the ssh parameters. Optional, but if not provided you will only be able to deploy locally
    "host": "a.windbornesystems.com",
    "user": "windborne"
  },
  "deploy_path": "/srv/", // where to sync the code to on the remote host. If not provided, you won't be able to deploy
  "install": "install.sh", // the install script. May be a file or a bash command. Optional
  "build": "build.sh", // the build script. May be a file or a bash command. Optional
}
```
