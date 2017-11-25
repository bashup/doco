#!/usr/bin/env bash
: '
<!-- ex: set syntax=markdown : '; eval "$(mdsh -E "$BASH_SOURCE")"; # -->

### Contents

<!-- toc -->

- [doco - Project Automation and Literate Devops for docker-compose](#doco---project-automation-and-literate-devops-for-docker-compose)
  * [Configuration](#configuration)
    + [File and Function Names](#file-and-function-names)
    + [Project-Level Configuration](#project-level-configuration)
  * [API](#api)
    + [Declarations](#declarations)
      - [`SERVICES`](#services)
      - [`VERSION`](#version)
    + [Config](#config)
      - [`export-dotenv`](#export-dotenv)
    + [Automation](#automation)
      - [`compose`](#compose)
  * [Commands](#commands)
    + [Docker-Compose Subcommands](#docker-compose-subcommands)
    + [Service Selection](#service-selection)
      - [`with` *service subcommand args...*](#with-service-subcommand-args)
      - [`--` *[subcommand args...]*](#---subcommand-args)
    + [Other](#other)
      - [`jq`](#jq)
  * [Merging jqmd and loco](#merging-jqmd-and-loco)

<!-- tocstop -->

# doco - Project Automation and Literate Devops for docker-compose

doco is a project automation tool for doing literate devops with docker-compose.  It's an extension of both loco and jqmd, written as a literate program using mdsh.  Within this source file, `shell` code blocks are the main program, while `shell mdsh` blocks are metaprogramming, and `~~~shell` blocks are examples tested with cram.

The main program begins with a `#!` line and edit warning:

```shell
#!/usr/bin/env bash
# ---
# This file was automatically generated from doco.md - DO NOT EDIT!
# ---
```

Followed by its license text:

```shell mdsh
# incorporate the LICENSE file as bash comments
source realpaths; realpath.location "$MDSH_SOURCE"
echo; sed -e '1,2d; s/^\(.\)/# \1/; s/^$/#/;' "$REPLY/LICENSE"; echo
```

And for our tests, we source this file and set up some testing tools:

~~~shell
# Load functions and turn off error exit
    $ source doco; set +e
    $ doco.no-op() { :;}

# Ignore/null out all configuration for testing
    $ loco_user_config() { :;}
    $ loco_site_config() { :;}
    $ loco_findproject() { LOCO_PROJECT=/dev/null; DOCO_CONFIG=docker-compose.yml; }
    $ loco_main no-op

# stub docker-compose to output arguments
    $ docker-compose() {
    >     { printf -v REPLY ' %q' "docker-compose" "$@"; echo "${REPLY# }"; } >&2;
    > }
~~~

## Configuration

### File and Function Names

Configuration is loaded using loco.  Specifically, by searching for `*.doco.md`, `.doco`, or `docker-compose.yml` above the current directory.  The loco script name is hardcoded to `doco`, so even if it's run via a symlink the function names for custom subcommands will still be `doco.subcommand-name`.  User and site-level configs are also defined.

```shell
loco_preconfig() {
    LOCO_FILE=("*[-.]doco.md" ".doco" "docker-compose.yml")
    LOCO_NAME=doco
    LOCO_USER_CONFIG=$HOME/.config/doco
    LOCO_SITE_CONFIG=/etc/doco/config
}
```

~~~shell
    $ declare -p LOCO_FILE LOCO_NAME LOCO_USER_CONFIG LOCO_SITE_CONFIG
    declare -a LOCO_FILE='([0]="*[-.]doco.md" [1]=".doco" [2]="docker-compose.yml")'
    declare -- LOCO_NAME="doco"
    declare -- LOCO_USER_CONFIG="/*/.config/doco" (glob)
    declare -- LOCO_SITE_CONFIG="/etc/doco/config"
~~~

### Project-Level Configuration

## API

### Declarations

#### `SERVICES`

#### `VERSION`

### Config

#### `export-dotenv`

### Automation

#### `compose`

`compose` *args* is short for `docker-compose` *args*, except that the project directory and config files are set to the ones calculated by doco.  If `DOCO_OPTIONS` is set, it's added to the start of the command line, and if `DOCO_OVERRIDES` is set, it's inserted before *args* but after the generated options:

```shell
compose() {
    docker-compose ${DOCO_OPTIONS-} --project-directory "$LOCO_ROOT" -f "$DOCO_CONFIG" ${DOCO_OVERRIDES-} "$@"
}
```

~~~shell
    $ DOCO_OPTIONS=--tls DOCO_OVERRIDES='-f foo' DOCO_CONFIG=config.yml compose bar baz
    docker-compose --tls --project-directory /dev -f config.yml -f foo bar baz
~~~

## Commands

### Docker-Compose Subcommands

Unrecognized subcommands are sent to docker-compose, with the current service set appended to the command line.  (The service set is empty by default, causing docker-compose to apply commands to all services by default.)

```shell
DOCO_SERVICES=()
loco_exec() { compose "$@" ${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"}; }
```

~~~shell
    $ doco foo
    docker-compose --project-directory /dev -f docker-compose.yml foo
~~~

But docker-compose subcommands that *don't* take services as their sole positional arguments don't get services appended:

```shell
# Commands that don't accept a list of services
for cmd in bundle config down exec help port run scale version; do
    eval "doco.$cmd() { compose $cmd \"\$@\"; }"
done
```

~~~shell
    $ declare -f doco.config | sed 's/ $//'
    doco.config ()
    {
        compose config "$@"
    }
    $ doco config
    docker-compose --project-directory /dev -f docker-compose.yml config
~~~

### Service Selection

#### `with` *service subcommand args...*

The `with`  subcommand sets one or more services in `DOCO_SERVICES` and invokes the given `doco` subcommand with the given arguments.  The *service* argument is either a single service name or a string containing a space-separated list of service names.

```shell
# Execute the rest of the command line with specified service(s)
doco.with() { local DOCO_SERVICES=($1); doco "${@:2}"; }
```

At first glance, this command might appear redundant to simply adding the service names to the end of a regular command.  But since you can write custom subcommands that execute multiple docker commands, or that loop over `DOCO_SERVICES` to perform other operations (not to mention subcommands that invoke `with` with a preset list of services), it can come quite in handy.

~~~shell
    $ doco with "a b c" ps
    docker-compose --project-directory /dev -f docker-compose.yml ps a b c
~~~

#### `--` *[subcommand args...]*

`--` is short for `with` with an empty service list; it can be used to ensure a command is invoked for all (or no) services, even if a service set was previously selected:

```shell
# Execute the rest of the command line with NO specified service(s)
doco.--()   { doco with '' "$@"; }
```

~~~shell
    $ doco with "a b c" -- ps
    docker-compose --project-directory /dev -f docker-compose.yml ps
~~~

### Other

#### `jq`

## Merging jqmd and loco

We embed a copy of the jqmd source (so it doesn't have to be installed separately), and override the `mdsh-error` function to call `loco_error` so that all errors ultimately go through the same function.  Last, but not least, we directly concatenate the loco source so that it will act as the main program.

```shell mdsh
mdsh-embed jqmd
```
```shell
mdsh-error() { printf -v REPLY "$1\n" "${@:2}"; loco_error "$REPLY"; }
```
```shell mdsh
sed -e '/^# LICENSE$/,/^$/d' "$(command -v loco)"
```

