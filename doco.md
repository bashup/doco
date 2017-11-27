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
      - [`ALIAS` *name(s) services...*](#alias-names-services)
      - [`SERVICES` *name...*](#services-name)
      - [`VERSION` *docker-compose version*](#version-docker-compose-version)
    + [Config](#config)
      - [`export-dotenv` *filename*](#export-dotenv-filename)
    + [Automation](#automation)
      - [`compose`](#compose)
      - [`get-alias` *alias*](#get-alias-alias)
      - [`project-name` *[service index]*](#project-name-service-index)
      - [`require-services` *flag command-name*](#require-services-flag-command-name)
    + [jq API](#jq-api)
      - [`jqmd_data`](#jqmd_data)
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
      - [`--with` *service [subcommand args...]*](#--with-service-subcommand-args)
      - [`--` *[subcommand args...]*](#---subcommand-args)
      - [`--with-default` *alias [subcommand args...]*](#--with-default-alias-subcommand-args)
      - [`--require-services` *flag [subcommand args...]*](#--require-services-flag-subcommand-args)
    + [doco subcommands](#doco-subcommands)
      - [`cp` *[opts] src dest*](#cp-opts-src-dest)
      - [`jq`](#jq)
      - [`sh`](#sh)
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

# stub docker and docker-compose to output arguments
    $ docker() { printf -v REPLY ' %q' "docker" "$@"; echo "${REPLY# }"; } >&2;
    $ docker-compose() { printf -v REPLY ' %q' "docker-compose" "$@"; echo "${REPLY# }"; } >&2;
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
    CLEAR_FILTERS  # doing RUN_JQ in a subshell doesn't reset the current shell's state
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
    $ echo 'FILTER .
    > doco.dump() {
    >     HAVE_FILTERS || echo "cleared!"
    >     RUN_JQ -c . <(echo "$DOCO_CONFIG");
    > }
    > ' >.doco
    $ echo 'services: {t: {image: alpine, command: "bash -c echo test"}}' >docker-compose.yml
    $ command doco dump
    cleared!
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

#### `ALIAS` *name(s) services...*

Add *services* to the named alias(es), defining or redefining subcommands and jq functions to map those aliases to their defined services.   Multiple aliases can be updated at once by passing them as a space-separated string in the first argument, e.g. `ALIAS "foo bar" baz spam` adds `baz` and `spam` to both the `foo` and `bar` aliases.

```shell
ALIAS() {
    local alias svc tmp
    (($#>1)) || loco_error "ALIAS requires at least two arguments"
    for alias in $1; do
        get-alias "$alias"
        for svc in "${@:2}"; do
            [[ " ${REPLY[*]-} " == *" $svc "* ]] || REPLY+=("$svc")
        done
        printf -v tmp ' %q' "${REPLY[@]}"
        printf -v tmp 'doco-alias-%s() { REPLY=(%s); }' "$alias" "$tmp"; eval "$tmp";
        printf -v tmp 'doco.%s() { get-alias %q; doco --with "${REPLY[*]-}" "$@"; }' "$alias" "$alias"; eval "$tmp"
        printf -v tmp '| (.services.%s |= f ) ' "${REPLY[@]}"
        DEFINE "def $alias(f): . $tmp;"
    done
}
```

~~~shell
# Arguments required

    $ (ALIAS)
    ALIAS requires at least two arguments
    [64]

# Alias one, non-existing name

    $ ALIAS delta echo gamma
    $ doco delta ps
    docker-compose * ps echo gamma (glob)
    $ RUN_JQ -c -n '{} | delta(.image = "test")'
    {"services":{"echo":{"image":"test"},"gamma":{"image":"test"}}}

# Add to multiple aliases, adding but not duplicating

    $ ALIAS "tango delta" niner gamma
    $ doco delta ps
    docker-compose * ps echo gamma niner (glob)
    $ RUN_JQ -c -n '{} | delta(.image = "test")'
    {"services":{"echo":{"image":"test"},"gamma":{"image":"test"},"niner":{"image":"test"}}}

    $ doco tango ps
    docker-compose * ps niner gamma (glob)
    $ RUN_JQ -c -n '{} | tango(.image = "test")'
    {"services":{"niner":{"image":"test"},"gamma":{"image":"test"}}}
~~~

#### `SERVICES` *name...*

Define subcommands and jq functions for the given service names.  `SERVICES foo bar` will create `foo` and `bar` commands that set the current service set (`DOCO_SERVICES`)  to that service, along with jq functions `foo()` and `bar()` that can be used to alter `.services.foo` and `.services.bar`, respectively.

Note: this command is a shortcut for aliasing a service name to itself; if you alias o

```shell
SERVICES() { for svc in "$@"; do ALIAS "$svc" "$svc"; done; }
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

`compose` *args* is short for `docker-compose` *args*, except that the project directory and config files are set to the ones calculated by doco.  If `DOCO_PREFIX_OPTS` is set, it's added to the start of the command line, and if `DOCO_OPTS` is set, it's inserted before *args* but after the generated options:

```shell
DOCO_PREFIX_OPTS=
DOCO_OPTS=

compose() {
    docker-compose ${DOCO_PREFIX_OPTS-} --project-directory "$LOCO_ROOT" -f <(echo "$DOCO_CONFIG") ${DOCO_OPTS-} "$@"
}
```

~~~shell
    $ DOCO_PREFIX_OPTS=--tls DOCO_OPTS='-f foo' compose bar baz
    docker-compose --tls --project-directory /*/doco.md -f /dev/fd/63 -f foo bar baz (glob)
~~~

#### `get-alias` *alias*

Return the current value of alias *alias* as an array in `REPLY`.  Returns an empty array if the alias doesn't exist.

```shell
get-alias() { if fn-exists "doco-alias-$1"; then "doco-alias-$1"; else REPLY=(); fi; }
```

~~~shell
    $ get-alias tango; printf '%q\n' ${REPLY[@]}
    niner
    gamma
    $ get-alias nonesuch; echo ${#REPLY[@]}
    0
~~~

#### `project-name` *[service index]*

Returns the project name or container name of the specified service in `REPLY`.  The project name is derived from  `$COMPOSE_PROJECT_NAME` (or the project directory name if not set).  If no *index* is given, it defaults to `1`.  (e.g. `project_service_1`).

(Note: custom container names are **not** supported.)

```shell
project-name() {
    REPLY=${COMPOSE_PROJECT_NAME-}
    [[ $REPLY ]] || realpath.basename "$LOCO_ROOT"   # default to directory name
    REPLY=${REPLY//[^[:alnum:]]/}; REPLY=${REPLY,,}  # lowercase and remove non-alphanumerics
    ! (($#)) || REPLY+="_${1}_${2-1}"                # container name
}
```

~~~shell
    $ project-name; echo $REPLY
    docomd
    $ COMPOSE_PROJECT_NAME=foo project-name bar 3; echo $REPLY
    foo_bar_3
~~~

#### `require-services` *flag command-name*

Checks the number of currently selected services, based on *flag*.  If flag is `1`, then exactly one service must be selected; if `-`, then 0 or 1 services.  `+` means 1 or more services are required.  If the number of services selected (e.g. via the `--with` subcommand), does not match the requirement, abort with a usage error using *command-name*.

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
    $ (doco --with "x y" test-rs 1)
    test-rs cannot be used on multiple services
    [64]
    $ (doco --with foo test-rs 1)
    success

# - = at most one service
    $ (doco -- test-rs -)
    success
    $ (doco --with "x y" test-rs -)
    test-rs cannot be used on multiple services
    [64]
    $ (doco --with foo test-rs -)
    success

# + = at least one service
    $ (doco -- test-rs +)
    no services specified for test-rs
    [64]
    $ (doco --with "x y" test-rs +)
    success
    $ (doco --with foo test-rs 1)
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

## Docker-Compose Integration

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
    $ doco --with x port --protocol udp 53
    docker-compose * port --protocol udp x 53 (glob)

    $ doco --with "x y z" run -e FOO=bar foo
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

### Docker-Compose Options

  A few (like `--version` and `--help`) need to exit immediately, and a few others need special handling:

#### Generic Options

Most docker-compose global options are added to the `DOCO_OPTS` variable, where they will pass through to any subcommand.

```shell
docker-compose-options() {
    while (($#)); do
        printf -v REPLY 'doco.%s() { doco opt %s "$@"; }' "$1" "$1"; eval "$REPLY"; shift
    done
}

docker-compose-optargs() {
    while (($#)); do
        eval "doco.$1() { doco opt $1 opt \"\$@\"; }"; shift
    done
}
doco.opt() { local DOCO_OPTS="$DOCO_OPTS $1"; doco "${@:2}"; }
docker-compose-options --verbose --no-ansi --tls --tlsverify --skip-hostname-check
docker-compose-optargs -f --file -H --host --tlscacert --tlscert --tlskey
```

~~~shell
    $ doco -f x --verbose --tlskey blah foo
    docker-compose * -f x --verbose --tlskey blah foo (glob)
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
    $ doco -f x --help --verbose something blah
    docker-compose --help --verbose something blah
~~~

#### Project-level Options

Project level options are fixed and can't be changed via the command line.

```shell
doco.-p() { loco_error "You must use COMPOSE_PROJECT_NAME to set the project name."; }
doco.--project-name() { doco -p "$@"; }
doco.--project-directory() { loco_error "doco: --project-directory cannot be overridden"; }
```

~~~shell
    $ (doco -f x --verbose -p blah foo)
    You must use COMPOSE_PROJECT_NAME to set the project name.
    [64]

    $ (doco --project-directory x blah)
    doco: --project-directory cannot be overridden
    [64]
~~~

## Command-line Interface

### doco options

#### `--with` *service [subcommand args...]*

The `with`  subcommand sets one or more services in `DOCO_SERVICES` and invokes the given `doco` subcommand with the given arguments.  The *service* argument is either a single service name or a string containing a space-separated list of service names.

```shell
# Execute the rest of the command line with specified service(s)
doco.--with() { local DOCO_SERVICES=($1); doco "${@:2}"; }
```

At first glance, this command might appear redundant to simply adding the service names to the end of a regular command.  But since you can write custom subcommands that execute multiple docker commands, or that loop over `DOCO_SERVICES` to perform other operations (not to mention subcommands that invoke `with` with a preset list of services), it can come quite in handy.

~~~shell
    $ doco --with "a b c" ps
    docker-compose * ps a b c (glob)
~~~

#### `--` *[subcommand args...]*

`--` is short for `--with ''`; it can be used to ensure a command is invoked for all (or no) services, even if a service set was previously selected:

```shell
# Execute the rest of the command line with NO specified service(s)
doco.--()   { doco --with '' "$@"; }
```

~~~shell
    $ doco --with "a b c" -- ps
    docker-compose * ps (glob)
~~~

#### `--with-default` *alias [subcommand args...]*

If no services are selected, invoke *alias subcommand args...*; otherwise invoke *subcommand args...*.  *alias* must be a valid `doco` subcommand, normally a service or group alias created with `SERVICES` or `ALIAS`.

```shell
doco.--with-default() {
    if ((${#DOCO_SERVICES[@]})); then doco "${@:2}"; else doco "$@"; fi
}
```

~~~shell
    $ doco -- --with-default alfa ps
    docker-compose * ps alfa (glob)

    $ doco foxtrot --with-default alfa ps -q
    docker-compose * ps -q foxtrot (glob)
~~~

#### `--require-services` *flag [subcommand args...]*

This is the command-line equivalent of calling `require-services` *flag subcommand* before invoking *subcommand args...*.  That is, it checks that the relevant number of services are present and exits with a usage error if not.

```shell
doco.--require-services() { require-services "${@:1:2}" && doco "${@:2}"; }
```

~~~shell
    $ (doco -- --require-services 1 ps)
    no services specified for ps
    [64]
~~~

### doco subcommands

#### `cp` *[opts] src dest*

Copy a file in or out of a service container.  Functions the same as `docker cp`, except that instead of using a container name as a prefix, you can use either a service name or an empty string (meaning, the currently-selected service).  So, e.g. `doco cp :/foo bar` copies `/foo` from the current service to `bar`, while `doco cp baz spam:/thing` copies `baz` to `/thing` inside the `spam` service's first container.  If no service is selected and no service name is given, the `shell-default` alias is tried.

```shell
doco.cp() {
    local opts= seen=
    while (($#)); do
        case "$1" in
        -a|--archive|-L|--follow-link) opts+=" $1" ;;
        --help|-h) docker help cp || true; return ;;
        -*) loco_error "Unrecognized option $1; see 'docker help cp'" ;;
        *) break ;;
        esac
        shift
    done
    (($# == 2)) || loco_error "cp requires two non-option arguments (src and dest)"
    while (($#)); do
        if [[ $1 == *:* ]]; then
            [[ ! "$seen" ]] || loco_error "cp: only one argument may contain a :"
            seen=yes
            if [[ "${1%%:*}" ]]; then
                project-name "${1%%:*}"; set -- "$REPLY:${1#*:}" "${@:2}"
            elif ((${#DOCO_SERVICES[@]} == 1)); then
                project-name "$DOCO_SERVICES"; set -- "$REPLY$1" "${@:2}"
            else
                doco --with-default shell-default --require-services 1 cp $opts "$@"; return $?
            fi
        fi
        printf -v opts "%s %q" "$opts" "$1"; shift
    done
    [[ "$seen" ]] || loco_error "cp: either source or destination must contain a :"
    docker cp $opts
}
```

~~~shell
# Nominal cases

    $ doco cp -h
    docker help cp

    $ doco cp -L /foo bar:/baz
    docker cp -L /foo docomd_bar_1:/baz

    $ doco cp bar:/spam -
    docker cp docomd_bar_1:/spam -

    $ (doco cp :x y)
    no services specified for cp
    [64]

    $ (ALIAS shell-default tango; doco cp :x y)
    docker cp docomd_tango_1:x y

# Bad usages

    $ (doco --with "too many" cp foo :bar)
    cp cannot be used on multiple services
    [64]

    $ (doco cp --nosuch)
    Unrecognized option --nosuch; see 'docker help cp'
    [64]

    $ (doco cp foo bar baz)
    cp requires two non-option arguments (src and dest)
    [64]

    $ (doco cp foo bar)
    cp: either source or destination must contain a :
    [64]

    $ (doco cp foo:bar baz:spam)
    cp: only one argument may contain a :
    [64]
~~~

#### `jq`

`doco jq` *args...* pipes the docker-compose configuration to `jq` *args...* as JSON.  Any functions defined via jqmd's facilities  (`DEFINES`, `IMPORTS`, `jq defs` blocks, `const` blocks, etc.) will be available to the given jq expression, if any.  If no expression is given, `.` is used.

```shell
doco.jq() { echo "$DOCO_CONFIG" | RUN_JQ "$@"; }
```

~~~shell
    $ doco jq .version
    "2.1"
~~~

#### `sh`

`doco sh` *args...* executes `bash` *args* in the specified service's container.  If no service is specified, it defaults to the `shell-default` alias.  Multiple services are not allowed.

```shell
doco.sh() { doco --with-default shell-default --require-services 1 exec bash "$@"; }
doco.shell-default() { doco "$@"; }   # no-op until/unless aliased
```

~~~shell
    $ (doco sh)
    no services specified for exec
    [64]

    $ (doco tango sh)
    exec cannot be used on multiple services
    [64]

    $ doco alfa sh
    docker-compose * exec alfa bash (glob)

    $ (ALIAS shell-default foxtrot; doco sh -c 'echo foo')
    docker-compose * exec foxtrot bash -c echo\ foo (glob)
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

