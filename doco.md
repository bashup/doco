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
      - [`SERVICES` *name...*](#services-name)
      - [`VERSION` *docker-compose version*](#version-docker-compose-version)
    + [Config](#config)
      - [`export-dotenv` *filename*](#export-dotenv-filename)
    + [Automation](#automation)
      - [`compose`](#compose)
      - [`require-services` *flag command-name*](#require-services-flag-command-name)
    + [jq API](#jq-api)
      - [`jqmd_data`](#jqmd_data)
  * [Commands](#commands)
    + [Docker-Compose Subcommands](#docker-compose-subcommands)
      - [Multi-Service Subcommands](#multi-service-subcommands)
      - [Non-Service Subcommands](#non-service-subcommands)
      - [Single-Service Subcommands](#single-service-subcommands)
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

# Use README.md for default config
    $ cp $TESTDIR/README.md readme.doco.md

# Ignore/null out all configuration for testing
    $ loco_user_config() { :;}
    $ loco_site_config() { :;}
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

Project configuration is loaded into the `DOCO_CONFIG` var as JSON text.  This may be done by reading it from `docker-compose.yml` or from the data and jq code embedded in a `*.doco.md` file.  If the project file is a `.doco` file, it's sourced and any jq filters in it are applied to the `docker-compose.yml`.

```shell
loco_loadproject() {
    cd "$LOCO_ROOT"; [[ ! -f .env ]] || export-dotenv .env
    case "$(basename "$1")" in
    .doco)
        source "$1"; DOCO_CONFIG="$(yaml2json - <docker-compose.yml | RUN_JQ)" ;;
    *.doco.md)
        (("$(ls *.doco.md | wc -l)" < 2)) || loco_error "Multiple doco.md files in $LOCO_ROOT"
        set +x; run-markdown "$1";  DOCO_CONFIG="$(RUN_JQ -n)" ;;
    *.yaml|*.yml)
        DOCO_CONFIG="$(yaml2json - <"$1" | RUN_JQ)" ;;
    *)
        loco_error "Unrecognized project file type: $1" ;;
    esac
}
```

~~~shell
# There can be only one! (.doco.md file, that is)
    $ touch another.doco.md
    $ command doco
    Multiple doco.md files in /*/doco.md (glob)
    [64]
    $ rm another.doco.md

# Config is loaded from .doco and docker-compose.yml if not otherwise found
    $ mkdir t; cd t
    $ echo 'doco.dump() { RUN_JQ -c . <(echo "$DOCO_CONFIG"); }' >.doco
    $ echo 'services: {t: {image: alpine, command: "bash -c echo test"}}' >docker-compose.yml
    $ command doco dump
    {"services":{"t":{"command":"bash -c echo test","image":"alpine"}}}

# .env file is auto-loaded
    $ echo "FOO=bazbar" >.env
    $ echo 'doco.dump() { echo "$FOO"; }' >.doco
    $ command doco dump
    bazbar

# Back to the test root
    $ cd ..
~~~

## API

### Declarations

#### `SERVICES` *name...*

Define subcommands and jq functions for the given service names.  `SERVICES foo bar` will create `foo` and `bar` commands that set the current service set (`DOCO_SERVICES`)  to that service, along with jq functions `foo()` and `bar()` that can be used to alter `.services.foo` and `.services.bar`, respectively.

```shell
SERVICES() {
    for svc in "$@"; do
        DEFINE "def $svc(f): .services.$svc |= f;"
        eval "doco.$svc() { doco with '$svc' \"\$@\"; }"
    done
}
```

~~~shell
    $ SERVICES alfa foxtrot

# command alias sets the active service set
    $ doco alfa ps
    docker-compose * ps alfa (glob)

# jq function makes modifications to the service entry
    $ RUN_JQ -c -n '{} | foxtrot(.image = "test")'
    {"services":{"foxtrot":{"image":"test"}}}
~~~

#### `VERSION` *docker-compose version*

Set the version of the docker-compose configuration (by way of a jq filter):

```shell
VERSION() { FILTER ".version=\"$1\""; }
```

~~~shell
    $ VERSION 2.1
    $ echo '{}' | RUN_JQ -c
    {"version":"2.1"}
~~~

### Config

#### `export-dotenv` *filename*

`source` the specified file, exporting any variables defined by it that didn't previously exist.  Used to load the [project-level configuration](#project-level-configuration), but can also be used to load additional environment files.  (Note: the environment files are in *shell* syntax (bash syntax to be precise), *not* docker-compose syntax.  Since docker-compose gives the exported environment precedence over the contents of  `.env` files, this approach effectively allows the use of shell syntax in `.env`.

```shell
export-dotenv() {
    local before="" after=""
    before="$(compgen -v)"; source "$@"; after="$(compgen -v)"
    after="$(echo "$after" | grep -vxF -f <(echo "$before"))" || true
    [[ -z "$after" ]] || export $after
}
```

~~~shell
    $ declare -p FOO 2>/dev/null || echo undefined
    undefined
    $ echo "FOO=bar" >dummy.env
    $ export-dotenv dummy.env
    $ declare -p FOO 2>/dev/null || echo undefined
    declare -x FOO="bar"
~~~

### Automation

#### `compose`

`compose` *args* is short for `docker-compose` *args*, except that the project directory and config files are set to the ones calculated by doco.  If `DOCO_OPTIONS` is set, it's added to the start of the command line, and if `DOCO_OVERRIDES` is set, it's inserted before *args* but after the generated options:

```shell
compose() {
    docker-compose ${DOCO_OPTIONS-} --project-directory "$LOCO_ROOT" -f <(echo "$DOCO_CONFIG") ${DOCO_OVERRIDES-} "$@"
}
```

~~~shell
    $ DOCO_OPTIONS=--tls DOCO_OVERRIDES='-f foo' compose bar baz
    docker-compose --tls --project-directory /*/doco.md -f /dev/fd/63 -f foo bar baz (glob)
~~~

#### `require-services` *flag command-name*

Checks the number of currently selected services, based on *flag*.  If flag is `1`, then exactly one service must be selected; if `-`, then 0 or 1 services.  `+` means 1 or more services are required.  If the number of services selected (e.g. via the `with` subcommand), does not match the requirement, abort with a usage error using *command-name*.

```shell
require-services() {
    case "$1${#DOCO_SERVICES[@]}" in
    ?1|-0) return ;;  # 1 is always acceptable
    ?0)    loco_error "no services specified for $2" ;;
    [-1]*) loco_error "$2 cannot be used on multiple services" ;;
    esac
}
```

~~~shell
    $ doco.test-rs() { require-services "$1" test-rs; echo success; }

# 1 = exactly one service
    $ (doco -- test-rs 1)
    no services specified for test-rs
    [64]
    $ (doco with "x y" test-rs 1)
    test-rs cannot be used on multiple services
    [64]
    $ (doco with foo test-rs 1)
    success

# - = at most one service
    $ (doco -- test-rs -)
    success
    $ (doco with "x y" test-rs -)
    test-rs cannot be used on multiple services
    [64]
    $ (doco with foo test-rs -)
    success

# + = at least one service
    $ (doco -- test-rs +)
    no services specified for test-rs
    [64]
    $ (doco with "x y" test-rs +)
    success
    $ (doco with foo test-rs 1)
    success
~~~

### jq API

#### `jqmd_data`

The `jqmd_data` function is used to combine YAML or JSON blocks found in a project's configuration file.  Currently, it's defined as a recursive addition of dictionaries that also does addition of arrays.  This generally does the right thing to assemble docker-compose configuration, so long as you're consistent in using dictionaries or arrays for a given setting.

```jq api
def jqmd_data($other): . as $original |
    reduce paths(type=="array") as $path (
        (. // {}) * $other; setpath( $path; ($original | getpath($path)) + ($other | getpath($path)) )
    );
```

~~~shell
    $ RUN_JQ -n '{a: "b", c: {d: [1, 2]}} | jqmd_data( {c: {e: {f: "G"}, d: [27] }} )'
    {
      "a": "b",
      "c": {
        "d": [
          1,
          2,
          27
        ],
        "e": {
          "f": "G"
        }
      }
    }
~~~

## Commands

### Docker-Compose Subcommands

#### Multi-Service Subcommands

Unrecognized subcommands are sent to docker-compose, with the current service set appended to the command line.  (The service set is empty by default, causing docker-compose to apply commands to all services by default.)

```shell
DOCO_SERVICES=()
loco_exec() { compose "$@" ${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"}; }
```

~~~shell
    $ doco foo
    docker-compose * foo (glob)
~~~

#### Non-Service Subcommands

But docker-compose subcommands that *don't* take services as their sole positional arguments don't get services appended:

```shell
# Commands that don't accept a list of services
for cmd in bundle config down help scale version; do
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
    docker-compose * config (glob)
~~~

#### Single-Service Subcommands

Commands that take exactly *one* service (exec, run, and port) are modified to run on multiple services or no services.  When there are no services in the service set, they take an explicit service positionally, just like with docker-compose.  Otherwise, the positional service argument is assumed to be missing, and the command is run once for each service in the current set.

Inserting the service argument at the appropriate place requires parsing the command's options, specifically those that take an argument.

~~~shell
    $ doco with x port --protocol udp 53
    docker-compose * port --protocol udp x 53 (glob)

    $ doco with "x y z" run -e FOO=bar foo
    docker-compose * run -e FOO=bar x foo (glob)
    docker-compose * run -e FOO=bar y foo (glob)
    docker-compose * run -e FOO=bar z foo (glob)

    $ doco -- exec -- foo bar
    docker-compose * exec foo bar (glob)
~~~

```shell
doco.exec() { __compose_one exec -e --env -u --user --index -- "$@"; }
doco.run()  { __compose_one run  -p --publish -v --volume -w --workdir -e --env -u --user --name --entrypoint -- "$@"; }
doco.port() { __compose_one port --protocol --index -- "$@"; }

__compose_one() {
    local svc opts='' argv=("$1")

    # Build up a list of options that take an argument
    while shift && (($#)) && [[ $1 != '--' ]]; do opts+="<$1>"; done

    # Parse the command line, skipping options' argument values
    while shift && (($#)) && [[ $1 == -* ]]; do
        # Treat '--' as end of options
        if [[ $1 == -- ]]; then shift; break; fi
        argv+=("$1"); if [[ $opts = *"<$1>"* ]]; then shift; argv+=("$1"); fi
    done

    if ((${#DOCO_SERVICES[@]})); then
        for svc in "${DOCO_SERVICES[@]}"; do compose "${argv[@]}" "$svc" "$@"; done
    else
        compose "${argv[@]}" "$@"
    fi
}
```

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
    docker-compose * ps a b c (glob)
~~~

#### `--` *[subcommand args...]*

`--` is short for `with` with an empty service list; it can be used to ensure a command is invoked for all (or no) services, even if a service set was previously selected:

```shell
# Execute the rest of the command line with NO specified service(s)
doco.--()   { doco with '' "$@"; }
```

~~~shell
    $ doco with "a b c" -- ps
    docker-compose * ps (glob)
~~~

### Other

#### `jq`

`doco jq` *args...* pipes the docker-compose configuration to `jq` *args...* as JSON.  Any functions defined via jqmd's facilities  (`DEFINES`, `IMPORTS`, `jq defs` blocks, `const` blocks, etc.) will be available to the given jq expression, if any.  If no expression is given, `.` is used.

```shell
doco.jq() { echo "$DOCO_CONFIG" | RUN_JQ "$@"; }
```

~~~shell
    $ doco jq .version
    "2.1"
~~~

## Merging jqmd and loco

We embed a copy of the jqmd source (so it doesn't have to be installed separately), pass along our jq API functions to jqmd, and override the `mdsh-error` function to call `loco_error` so that all errors ultimately go through the same function.  Last, but not least, we directly concatenate the loco source so that it will act as the main program:

```shell mdsh
mdsh-embed jqmd
```
```shell
DEFINE "$mdsh_raw_jq_api"
mdsh-error() { printf -v REPLY "$1\n" "${@:2}"; loco_error "$REPLY"; }
```
```shell mdsh
sed -e '/^# LICENSE$/,/^$/d' "$(command -v loco)"
```

