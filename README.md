# Project Automation for docker-compose

doco is an extensible tool for project automation and literate devops using docker-compose.  All docker-compose subcommands are subcommands of `doco`, along with any custom subcommands you define in your project, user, or global configuration files, and a few extra commands such as:

* `doco where` *[jq-filter [cmd..]].* -- invoke `doco cmd ...` on the services whose configuration matches *jq-filter*, or list the matching service names if no command is given.
* `doco jq` *expr* -- run a [jq](http://stedolan.github.io/jq/) query on the docker-compose configuration

In addition to letting you create custom commands and apply them to a configuration, you can also define your docker-compose configuration *and* custom commands as YAML, jq code, and shell functions embeded in a markdown file.  In this way, you can document your project's configuration and custom commands directly alongside the code that implements them.

doco is a mashup of [loco](https://github.com/bashup/loco) (for project configuration and subcommands) and [jqmd](https://github.com/bashup/jqmd) (for literate programming and jq support).  You can install it with [basher](https://github.com/basherpm/basher) (i.e. via `basher install bashup/doco`), or just copy the [binary](bin/doco) to a directory on your `PATH`.  You will need [jq](http://stedolan.github.io/jq/) and docker-compose on your `PATH` as well, along with either PyYAML or a yaml2json command (such as [this one](https://github.com/bronze1man/yaml2json)).