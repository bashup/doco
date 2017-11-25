# Project Automation for docker-compose

doco is an extensible tool for project automation and literate devops using docker-compose.  All docker-compose subcommands are subcommands of `doco`, along with any custom subcommands you define in your project, user, or global configuration files.

In addition to letting you create custom commands and apply them to a configuration, you can also define your docker-compose configuration *and* custom commands as YAML, [jq](http://stedolan.github.io/jq/) code, and shell functions embeded in a markdown file.  In this way, you can document your project's configuration and custom commands directly alongside the code that implements them.

## Basic Use

doco is a mashup of [loco](https://github.com/bashup/loco) (for project configuration and subcommands) and [jqmd](https://github.com/bashup/jqmd) (for literate programming and jq support).  You can install it with [basher](https://github.com/basherpm/basher) (i.e. via `basher install bashup/doco`), or just copy the [binary](bin/doco) to a directory on your `PATH`.  You will need [jq](http://stedolan.github.io/jq/) and docker-compose on your `PATH` as well, along with either PyYAML or a yaml2json command (such as [this one](https://github.com/bronze1man/yaml2json)).

In its simplest use, doco can be used to add custom commands to an existing docker-compose project: just create a `.doco` file alongside your `docker-compose.yml`, and define bash functions in it using the [doco API](doco.md#api) and [predefined commands](doco.md#commands).  A function named `doco.X` will define a doco subcommand `X`.

## Literate DevOps

While doco's basic project automation facilities are nice, doco's "killer app" is doing **literate devops**: combining infrastructure code, container configuration, documentation and possibly even *tests* in a single, well organized document.  For example, this very README.md is a cram test as well as an example doco project file.

To create a new project, just make a file whose name ends in `.doco.md`, e.g.:

~~~shell
    $ cp $TESTDIR/README.md readme-example.doco.md
~~~

In that file, you can intermix docker-compose YAML blocks, `jq` code, and shell script to define your configuration and custom commands, like so:

```yaml !true
services:
  example1:
    image: alpine
```

```jq
# jq filter that alters the supplied YAML
.services.example1.command = "true"
```

```shell
doco.example() { echo "this is an example command"; }
```

Your commands and containers can then be used on the command line:

~~~shell
    $ doco example
    this is an example command
~~~

