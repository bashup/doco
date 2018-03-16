# Project Automation for docker-compose

doco is an extensible tool for project automation and literate devops using docker-compose.  All docker-compose subcommands are subcommands of `doco`, along with any custom subcommands you define in your project, user, or global configuration files.

In addition to letting you create custom commands and apply them to a configuration, you can also define your docker-compose configuration *and* custom commands as YAML, [jq](http://stedolan.github.io/jq/) code, and shell functions embeded in a markdown file.  In this way, you can document your project's configuration and custom commands directly alongside the code that implements them.

## Basic Use

doco is a mashup of [loco](https://github.com/bashup/loco) (for project configuration and subcommands) and [jqmd](https://github.com/bashup/jqmd) (for literate programming and jq support).  You can install it with [basher](https://github.com/basherpm/basher) (i.e. via `basher install bashup/doco`), or just copy the [binary](bin/doco) to a directory on your `PATH`.  You will need [jq](http://stedolan.github.io/jq/) and docker-compose on your `PATH` as well, along with either a yaml2json command (such as [this one](https://github.com/bronze1man/yaml2json)), PyYAML, or the YAML extension for PHP.

In its simplest use, doco can be used to add custom commands to an existing docker-compose project: just create a `.doco` file alongside your `docker-compose.yml`, and define bash functions in it using the [doco API](doco.md#api) and [CLI](doco.md#command-line-interface).  A function named `doco.X` will define a doco subcommand `X`.

## Literate DevOps

While doco's basic project automation facilities are nice, doco's "killer app" is doing **literate devops**: combining infrastructure code, container configuration, documentation and possibly even *tests* in a single, well organized document.  For example, this very README.md is a cram test as well as an example doco project file.

To create a new project, just make a file whose name ends in `.doco.md`, e.g.:

~~~shell
    $ cp $TESTDIR/README.md readme-example.doco.md
~~~

In that file, you can intermix docker-compose YAML blocks, `jq` code, and shell script to define your configuration and custom commands, like so:

```yaml
# A `yaml` block defining some configuration
version: "2.1"
services:
  example1:
    image: bash
```

```jq
# A `jq` block defining some filter code that alters the supplied YAML
.services.example1.command = "bash -c 'echo hello world; echo'"
```

```shell
# A `shell` block defining a new doco subcommand
doco.example() { echo "this is an example command"; }
```

Your commands and containers can then be used on the command line:

~~~shell
    $ doco example
    this is an example command

    $ doco run --rm example1
    hello world
~~~

Your project document can include as many `shell`, `yaml`, and `jq` blocks as you like.  `yaml` and `jq` blocks are processed in order, with the `yaml` being treated as if it were a jq filter assigning the contents of the block. The project document is processed using [jqmd](https://github.com/bashup/jqmd), so all of the languages and metaprogramming tricks of both jqmd and [mdsh](https://github.com/bashup/mdsh) are supported.  (You can define jq functions in `jq defs` blocks, for example, or generate code using `mdsh` blocks.)

Of course, you won't want to put sensitive data directly in your project document.  So, just like with docker-compose, you can use an `.env` file.

You're also not limited to just the contents of your main project document to do configuration.  The shell code embedded in your project document can use [export-env](doco.md#export-env-filename) to process additional docker-compose format `.env` files, or [include](include-markdownfile-cachefile) to source other markdown documents with the same syntax.  This can be useful for projects that want to be extensible, where a user can define local extension documents alongside a main project document that's kept in revision control.

### Caching

`doco` uses various caches to speed up its operation, and must therefore have write access to your project's root directory.  Currently, the cache files used are `.doco-cache.json` (which contains your project's generated configuration in JSON format) and `.doco-cache.sh` (which contains the compiled version of your `*.doco.md` file, if applicable).  If you `include` any markdown files, their compiled versions are cached in `.doco-cache/includes/`, unless you explicitly declare a cache path for each file.

All of these files are only used by `doco` while it's running, so if it's not running, you can safely remove them.  (But the next run of `doco` may be slower, since it will need to regenerate them.)

