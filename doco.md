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
      - [`ALIAS` *name(s) targets...*](#alias-names-targets)
      - [`SERVICES` *name...*](#services-name)
      - [`VERSION` *docker-compose version*](#version-docker-compose-version)
    + [Config](#config)
      - [`export-env` *filename*](#export-env-filename)
      - [`export-source` *filename*](#export-source-filename)
    + [Automation](#automation)
      - [`alias-exists` *name*](#alias-exists-name)
      - [`compose`](#compose)
      - [`find-services` *[jq-filter]*](#find-services-jq-filter)
      - [`foreach-service` *cmd args...*](#foreach-service-cmd-args)
      - [`get-alias` *alias*](#get-alias-alias)
      - [`have-services` *[compexpr]*](#have-services-compexpr)
      - [`include` *markdownfile [cachefile]*](#include-markdownfile-cachefile)
      - [`project-name` *[service index]*](#project-name-service-index)
      - [`require-services` *flag command-name*](#require-services-flag-command-name)
      - [`set-alias` *alias services...*](#set-alias-alias-services)
      - [`with-alias` *alias command...*](#with-alias-alias-command)
      - [`with-service` *service(s) command...*](#with-service-services-command)
    + [jq API](#jq-api)
      - [`services`](#services)
      - [`services_matching(filter)`](#services_matchingfilter)
  * [Docker-Compose Integration](#docker-compose-integration)
    + [Docker-Compose Subcommands](#docker-compose-subcommands)
      - [Multi-Service Subcommands](#multi-service-subcommands)
      - [Non-Service Subcommands](#non-service-subcommands)
      - [Single-Service Subcommands](#single-service-subcommands)
    + [Docker-Compose Options](#docker-compose-options)
      - [Generic Options](#generic-options)
      - [Aborting Options (--help, --version, etc.)](#aborting-options---help---version-etc)
      - [Project-level Options](#project-level-options)
  * [Command-line Interface](#command-line-interface)
    + [doco options](#doco-options)
      - [`--` *[subcommand args...]*](#---subcommand-args)
      - [`--all` *subcommand args...*](#--all-subcommand-args)
      - [`--where` *jq-filter [subcommand args...]*](#--where-jq-filter-subcommand-args)
      - [`--with` *service [subcommand args...]*](#--with-service-subcommand-args)
      - [`--with-default` *alias [subcommand args...]*](#--with-default-alias-subcommand-args)
      - [`--require-services` *flag [subcommand args...]*](#--require-services-flag-subcommand-args)
    + [doco subcommands](#doco-subcommands)
      - [`cmd` *flag subcommand...*](#cmd-flag-subcommand)
      - [`cp` *[opts] src dest*](#cp-opts-src-dest)
      - [`foreach` *subcmd arg...*](#foreach-subcmd-arg)
      - [`jq`](#jq)
      - [`sh`](#sh)
  * [Merging jqmd and loco](#merging-jqmd-and-loco)

<!-- tocstop -->

# doco - Project Automation and Literate Devops for docker-compose

doco is a project automation tool for doing literate devops with docker-compose.  It's an extension of both loco and jqmd, written as a literate program using mdsh.  Within this source file, `shell` code blocks are the main program, while `shell mdsh` blocks are metaprogramming, and `~~~shell` blocks are examples tested with cram.

The main program begins with a `#!` line and edit warning, followed by its license text and embedded copies of jqmd and loco:

```shell mdsh
@module doco.md
@main loco_main

@require pjeby/license @comment LICENSE
@require bashup/jqmd   mdsh-source "$BASHER_PACKAGES_PATH/bashup/jqmd/jqmd.md"
@require bashup/loco   mdsh-source "$BASHER_PACKAGES_PATH/bashup/loco/loco.md"
@require doco/api      mdsh-source "$DEVKIT_ROOT/API.md"
@require doco/cli      mdsh-source "$DEVKIT_ROOT/CLI.md"
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

# stub docker and docker-compose to output arguments
    $ docker() { printf -v REPLY ' %q' "docker" "$@"; echo "${REPLY# }"; } >&2;
    $ docker-compose() { printf -v REPLY ' %q' "docker-compose" "$@"; echo "${REPLY# }"; } >&2;
~~~

## Configuration

### File and Function Names

Configuration is loaded using loco.  Specifically, by searching for `*.doco.md`, `.doco`, or `docker-compose.yml` above the current directory.  The loco script name is hardcoded to `doco`, so even if it's run via a symlink the function names for custom subcommands will still be `doco.subcommand-name`.  User and site-level configs are also defined.

```shell
loco_preconfig() {
    export COMPOSE_PROJECT_NAME=
    LOCO_FILE=("?*[-.]doco.md" ".doco" "docker-compose.yml")
    LOCO_NAME=doco
    LOCO_USER_CONFIG=$HOME/.config/doco
    LOCO_SITE_CONFIG=/etc/doco/config
    DOCO_PROFILE=
}
```

~~~shell
    $ declare -p LOCO_FILE LOCO_NAME LOCO_USER_CONFIG LOCO_SITE_CONFIG DOCO_PROFILE | sed "s/'//g"
    declare -a LOCO_FILE=([0]="?*[-.]doco.md" [1]=".doco" [2]="docker-compose.yml")
    declare -- LOCO_NAME="doco"
    declare -- LOCO_USER_CONFIG="/*/.config/doco" (glob)
    declare -- LOCO_SITE_CONFIG="/etc/doco/config"
    declare -- DOCO_PROFILE=""
~~~

### Project-Level Configuration

Project configuration is loaded into `$LOCO_ROOT/.doco-cache.json` as JSON text, and `COMPOSE_FILE` is set to point to that file, for use by docker-compose.  (`COMPOSE_FILE` also gets the name of the `docker-compose.override` file, if any, with  `COMPOSE_PATH_SEPARATOR` set to a newline.)

If the configuration is a `*doco.md` file, it's entirely responsible for generating the configuration, and any standard `docker-compose{.override,}.y{a,}ml` file(s) are ignored.  Otherwise, the main YAML config is read before sourcing `.doco`, and the standard files are used to source the configuration.  (Note: the `.override` file, if any, is passed to docker-compose, but is *not* included in any jq filters or queries done by doco.)

Either way, service aliases are created for any services that don't already have them.  (Minus any services that are only defined in an `.override`.)

```shell
loco_loadproject() {
    cd "$LOCO_ROOT"; [[ ! -f .env ]] || export-env .env
    export COMPOSE_FILE=$LOCO_ROOT/.doco-cache.json COMPOSE_PATH_SEPARATOR=$'\n'
    local json=$COMPOSE_FILE; DOCO_CONFIG=

    realpath.basename "$1"; case "$REPLY" in
    ?*[-.]doco.md)
        check_multi doco.md '?*[-.]doco.md'
        include "$1" "$LOCO_ROOT/.doco-cache.sh"
        ;;
    *)
        compose-variants "" load_yaml; compose-variants ".override" add_override
        [[ ! -f .doco ]] || source .doco
        ;;
    esac

    eval "$DOCO_PROFILE"  # allow overriding the final configuration
    RUN_JQ -c -n >"$json"; DOCO_CONFIG=$json; find-services
    ${REPLY[@]+SERVICES "${REPLY[@]}"}   # ensure SERVICES exist for all services
}

# Run a command with variants accepted by docker-compose, first checking that
# no more than one such variant exists
compose-variants() {
    check_multi "docker-compose$1" "docker-compose$1.yml" "docker-compose$1.yaml"
    "${@:2}" "$LOCO_ROOT/docker-compose$1.yml" "$LOCO_ROOT/docker-compose$1.yaml"
}

# Load listed YAML files as JSON, if they exist
load_yaml() { while (($#)); do [[ ! -f "$1" ]] || JSON "$(yaml2json /dev/stdin <"$1")"; shift; done; }

# Add a file to the COMPOSE_FILE list
add_override() { while (($#)); do [[ ! -f "$1" ]] || COMPOSE_FILE+=$'\n'"$1"; shift; done; }

# Abort if more than one given filename exists
check_multi() {
   # shellcheck disable=SC2012,SC2068  # we're using wc and glob expansion is intentional
   (("$(ls ${@:2} 2>/dev/null | wc -l)" < 2)) || loco_error "Multiple $1 files in $LOCO_ROOT"
}
```

~~~shell
# COMPOSE_FILE is exported, pointing to the cache; DOCO_CONFIG is the same,
# and COMPOSE_PATH_SEPARATOR is a line break
    $ declare -p COMPOSE_FILE DOCO_CONFIG COMPOSE_PATH_SEPARATOR
    declare -x COMPOSE_FILE="/*/doco.md/.doco-cache.json" (glob)
    declare -- DOCO_CONFIG="/*/doco.md/.doco-cache.json" (glob)
    declare -x COMPOSE_PATH_SEPARATOR="
    "

# .cache has same timestamp as what it's built from; and is rebuilt if it changes
    $ [[ readme.doco.md -ot .doco-cache.sh || readme.doco.md -nt .doco-cache.sh ]] || echo equal
    equal
    $ touch -r readme.doco.md savetime; touch readme.doco.md
    $ command doco --all
    example1
    $ [[ "$(stat -c %y readme.doco.md)" != "$(stat -c %y savetime)" ]] && echo changed
    changed
    $ [[ readme.doco.md -ot .doco-cache.sh || readme.doco.md -nt .doco-cache.sh ]] || echo equal
    equal

# There can be only one! ([.-]doco.md file, that is)
    $ touch another-doco.md
    $ command doco
    Multiple doco.md files in /*/doco.md (glob)
    [64]
    $ rm another-doco.md

# Config is loaded from .doco and docker-compose.yml if not otherwise found;
# COMPOSE_PROJECT_NAME is reset to empty before config runs:
    $ mkdir t; cd t
    $ echo 'FILTER .
    > doco.dump() {
    >     HAVE_FILTERS || echo "cleared!"
    >     RUN_JQ -c . <"$DOCO_CONFIG";
    >     declare -p COMPOSE_PROJECT_NAME
    > }
    > ' >.doco
    $ echo 'services: {t: {image: alpine, command: "bash -c echo test"}}' >docker-compose.yml
    $ COMPOSE_PROJECT_NAME=foo command doco dump
    cleared!
    {"services":{"t":{"command":"bash -c echo test","image":"alpine"}}}
    declare -x COMPOSE_PROJECT_NAME=""

# Must be only one docker-compose.y{a,}ml
    $ touch docker-compose.yaml
    $ command doco dump
    Multiple docker-compose files in /*/doco.md/t (glob)
    [64]
    $ rm docker-compose.yaml

# docker-compose.override.yml and docker-compose.override.yaml are included in COMPOSE_FILE
    $ echo 'doco.dump() { declare -p COMPOSE_FILE; }' >.doco
    $ command doco dump
    declare -x COMPOSE_FILE="/*/doco.md/t/.doco-cache.json" (glob)
    $ touch docker-compose.override.yml; command doco dump
    declare -x COMPOSE_FILE="/*/doco.md/t/.doco-cache.json (glob)
    /*/doco.md/t/docker-compose.override.yml" (glob)
    $ touch docker-compose.override.yaml; command doco dump
    Multiple docker-compose.override files in /*/doco.md/t (glob)
    [64]
    $ rm docker-compose.override.yml; command doco dump
    declare -x COMPOSE_FILE="/*/doco.md/t/.doco-cache.json (glob)
    /*/doco.md/t/docker-compose.override.yaml" (glob)

# .env file is auto-loaded, using docker-compose .env syntax, running DOCO_PROFILE
    $ { echo "FOO=baz'bar"; echo "DOCO_PROFILE=echo hi!"; } >.env
    $ echo 'doco.dump() { echo "${DOCO_SERVICES[@]}"; echo "$FOO"; }' >.doco
    $ command doco t dump
    hi!
    t
    baz'bar

# Back to the test root
    $ cd ..
~~~

## Docker-Compose Integration

### Docker-Compose Subcommands

#### Multi-Service Subcommands

Unrecognized subcommands are first checked to see if they're an alias.  If not, they're sent to docker-compose, with the current service set appended to the command line.  (The service set is empty by default, causing docker-compose to apply commands to all services by default.)

```shell
DOCO_SERVICES=()
loco_exec() {
    if alias-exists "$1"; then
        with-alias "$1" ${2+doco "${@:2}"};
    else
        compose "$@" ${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"};
    fi
}
```

~~~shell
    $ doco foo
    docker-compose foo
    $ (ALIAS foo bar; doco foo ps)
    docker-compose ps bar
    $ (ALIAS foo bar; doco foo bar)
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
    docker-compose config
~~~

#### Single-Service Subcommands

Commands that take exactly *one* service (exec, run, and port) are modified to run on multiple services or no services.  When there are no services in the service set, they take an explicit service positionally, just like with docker-compose.  Otherwise, the positional service argument is assumed to be missing, and the command is run once for each service in the current set.

Inserting the service argument at the appropriate place requires parsing the command's options, specifically those that take an argument.

~~~shell
    $ doco --with x port --protocol udp 53
    docker-compose port --protocol udp x 53

    $ doco --with "x y z" run -e FOO=bar foo
    docker-compose run -e FOO=bar x foo
    docker-compose run -e FOO=bar y foo
    docker-compose run -e FOO=bar z foo

    $ doco -- exec -- foo bar
    docker-compose exec foo bar
~~~

```shell
doco.exec() { __compose_one exec -e --env -u --user --index -- "$@"; }
doco.run()  { __compose_one run  -p --publish -v --volume -w --workdir -e --env -u --user --name --entrypoint -- "$@"; }
doco.port() { __compose_one port --protocol --index -- "$@"; }

__compose_one() {
    local svc options='' argv=("$1")

    # Build up a list of options that take an argument
    while shift && (($#)) && [[ $1 != '--' ]]; do options+="<$1>"; done

    # Parse the command line, skipping options' argument values
    while shift && (($#)) && [[ $1 == -* ]]; do
        # Treat '--' as end of options
        if [[ $1 == -- ]]; then shift; break; fi
        argv+=("$1"); if [[ $options = *"<$1>"* ]]; then shift; argv+=("$1"); fi
    done

    if ((${#DOCO_SERVICES[@]})); then
        for svc in "${DOCO_SERVICES[@]}"; do compose "${argv[@]}" "$svc" "$@"; done
    else
        compose "${argv[@]}" "$@"
    fi
}
```

### Docker-Compose Options

  A few (like `--version` and `--help`) need to exit immediately, and a few others need special handling:

#### Generic Options

Most docker-compose global options are added to the `DOCO_OPTS` array, where they will pass through to any subcommand.

```shell
docker-compose-options() {
    while (($#)); do
        # shellcheck disable=SC2089  # shellcheck hates metaprogramming
        printf -v REPLY 'doco.%s() { doco-opt %s doco "$@"; }' "$1" "$1"; eval "$REPLY"; shift
    done
}

docker-compose-optargs() {
    while (($#)); do
        eval "doco.$1() { doco-opt $1 doco-opt \"\$1\" doco \"\${@:2}\"; }"; shift
    done
}
doco-opt() { local DOCO_OPTS=(${DOCO_OPTS[@]+"${DOCO_OPTS[@]}"} "$1"); "${@:2}"; }
docker-compose-options --verbose --no-ansi --tls --tlsverify --skip-hostname-check
docker-compose-optargs -H --host --tlscacert --tlscert --tlskey
```

~~~shell
    $ doco --verbose --tlskey blah foo
    docker-compose --verbose --tlskey blah foo
~~~

#### Aborting Options (--help, --version, etc.)

Some options pass directly the rest of the command line directly to docker-compose, ignoring any preceding options or prefix options:

```shell
docker-compose-immediate() {
    while (($#)); do eval "doco.$1() { docker-compose $1 \"\$@\"; }"; shift; done
}
docker-compose-immediate -h --help -v --version
```
~~~shell
    $ doco --help --verbose something blah
    docker-compose --help --verbose something blah
~~~

#### Project-level Options

Project level options are fixed and can't be changed via the command line.

```shell
doco.-p() { loco_error "You must use COMPOSE_PROJECT_NAME to set the project name."; }
doco.-f() { loco_error "doco does not support -f and --file."; }
doco.--file() { doco -f "$@"; }
doco.--project-name() { doco -p "$@"; }
doco.--project-directory() { loco_error "doco: --project-directory cannot be overridden"; }
```

~~~shell
    $ (doco --file x)
    doco does not support -f and --file.
    [64]

    $ (doco --verbose -p blah foo)
    You must use COMPOSE_PROJECT_NAME to set the project name.
    [64]

    $ (doco --project-directory x blah)
    doco: --project-directory cannot be overridden
    [64]
~~~



## Merging jqmd and loco

We pass along our jq API functions to jqmd, and override the `mdsh-error` function to call `loco_error` so that all errors ultimately go through the same function.

```shell
DEFINE "${mdsh_raw_jq_api[*]}"
# shellcheck disable=SC2059  # argument is a printf format string
mdsh-error() { printf -v REPLY "$1"'\n' "${@:2}"; loco_error "$REPLY"; }
```