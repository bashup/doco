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

doco is a project automation tool for doing literate devops with docker-compose.  It's an extension of both loco and jqmd, written as a literate program using mdsh.  Within this source file, `shell` code blocks are the main program, while `shell mdsh` blocks are metaprogramming.

The main program begins with a `#!` line and edit warning, followed by its license text and embedded copies of jqmd and loco:

```shell mdsh
@module doco.md
@main loco_main

@require pjeby/license @comment LICENSE
@require bashup/jqmd   mdsh-source "$BASHER_PACKAGES_PATH/bashup/jqmd/jqmd.md"
@require bashup/loco   mdsh-source "$BASHER_PACKAGES_PATH/bashup/loco/loco.md"
```



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

## API

### Declarations

#### `ALIAS` *name(s) targets...*

Add *targets* to the named alias(es), defining or redefining subcommands and jq functions to map those aliases to the targeted services.  The *targets* may be services or aliases; if a target name isn't recognized it's assumed to be a service and defined as such.  Multiple aliases can be updated at once by passing them as a space-separated string in the first argument, e.g. `ALIAS "foo bar" baz spam` adds `baz` and `spam` to both the `foo` and `bar` aliases.

(Note that this function *adds* to the existing alias(es) and recursively expands aliases in the target list.  If you want to set an exact list of services, use `set-alias` instead.  Also note that the "recursive" expansion is *immediate*: redefining an alias used in the target list will not change the definition of the alias referencing it.)

```shell
ALIAS() {
    local alias svc DOCO_SERVICES=()
    (($#>1)) || loco_error "ALIAS requires at least two arguments"
    SERVICES "${@:2}"; mdsh-splitwords "$1"
    for alias in "${REPLY[@]}"; do __mkalias "$alias" "${@:2}"; done
}
__mkalias() {
     if (($#)); then with-alias "$1" __mkalias "${@:2}"; return; fi
     set-alias "$alias" ${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"}
}
```

#### `SERVICES` *name...*

Define subcommands and jq functions for the given service names.  `SERVICES foo bar` will create `foo` and `bar` commands that set the current service set (`DOCO_SERVICES`)  to that service, along with jq functions `foo()` and `bar()` that can be used to alter `.services.foo` and `.services.bar`, respectively.  If an alias of a given *name* is already defined, it is *not* redefined.

(Note: this command is effectively a shortcut for aliasing a service name to itself if it doesn't already exist, i.e. `set-alias` *name name*.)

```shell
SERVICES() { for svc in "$@"; do alias-exists "$svc" || set-alias "$svc" "$svc"; done; }
```

#### `VERSION` *docker-compose version*

Set the version of the docker-compose configuration (by way of a jq filter):

```shell
VERSION() { FILTER ".version=\"$1\""; }
```

### Config

#### `export-env` *filename*

Parse a docker-compose format `env_file`, exporting the variables found therein.  Used to load the [project-level configuration](#project-level-configuration), but can also be used to load additional environment files.

Blank and comment lines are ignored, all others are fed to `export` after stripping the leading and trailing spaces.  The file should not use quoting, or shell escaping: the exact contents of a line after the `=` (minus trailing spaces) are used as the variable's contents.

```shell
export-env() {
    while IFS= read -r; do
        REPLY="${REPLY#"${REPLY%%[![:space:]]*}"}"  # trim leading whitespace
        REPLY="${REPLY%"${REPLY##*[![:space:]]}"}"  # trim trailing whitespace
        [[ ! "$REPLY" || "$REPLY" == '#'* ]] || export "${REPLY?}"
    done <"$1"
}
```

#### `export-source` *filename*

`source` the specified file, exporting any variables defined by it that didn't previously exist.  (Note: the environment files are in *shell* syntax (bash syntax to be precise), *not* docker-compose syntax.)

```shell
export-source() {
    local before="" after=""
    before="$(compgen -v)"; source "$@"; after="$(compgen -v)"
    after="$(echo "$after" | grep -vxF -f <(echo "$before"))" || true
    [[ -z "$after" ]] || eval "export $after"
}
```

### Automation

#### `alias-exists` *name*

Return success if *name* has previously been defined as a service or alias.

```shell
alias-exists() { fn-exists "doco-alias-$1"; }
```

#### `compose`

`compose` *args* is short for `docker-compose` *args*, except that the project directory and config files are set to the ones calculated by doco.  The contents of the `DOCO_OPTS` array are included before the supplied arguments:

```shell
DOCO_OPTS=()
compose() { docker-compose ${DOCO_OPTS[@]+"${DOCO_OPTS[@]}"} "$@"; }
```

#### `find-services` *[jq-filter]*

Search the docker compose configuration for `services_matching(`*jq-filter*`)`, returning their names as an array in `REPLY`.  If *jq-filter* isn't supplied, `true` is used.  (i.e., find all services.)

```shell
find-services() { REPLY=$(RUN_JQ -r "services_matching(${1-true}) | .key" "$DOCO_CONFIG") && IFS=$'\n' mdsh-splitwords "$REPLY"; }
```

#### `foreach-service` *cmd args...*

Invoke *cmd args...* once for each service in the current service set; the service set will contain exactly one service during each invocation.

```shell
foreach-service() {
    for REPLY in ${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"}; do
        local DOCO_SERVICES=("$REPLY"); "$@"
    done
}
```

#### `get-alias` *alias*

Return the current value of alias *alias* as an array in `REPLY`.  Returns an empty array if the alias doesn't exist.

```shell
get-alias() { REPLY=(); ! alias-exists "$1" || "doco-alias-$1"; }
```

#### `have-services` *[compexpr]*

Return true if the current service count matches the bash numeric comparison *compexpr*; if no *compexpr* is supplied, returns true if the current service count is non-zero.

```shell
# shellcheck disable=SC2120  # shellcheck doesn't understand optional arguments
have-services() { eval "((${#DOCO_SERVICES[@]} ${1-}))"; }
```

#### `include` *markdownfile [cachefile]*

Source the mdsh compilation  of the specified markdown file, saving it in *cachefile* first.  If *cachefile* exists and has the same timestamp as *markdownfile*, *cachefile* is sourced without compiling.  If no *cachefile* is given, compilation is done to a file under `.doco-cache/includes`.  A given *markdownfile* can only be included once: this operation is a no-op if *markdownfile* has been `include`d  before.

```shell
include() {
    realpath.absolute "$1"
    if [[ ! "${2-}" ]]; then
        local MDSH_CACHE="$LOCO_ROOT/.doco-cache/includes"
        @require "doco-include:$REPLY" mdsh-run "$1" ""
    else
        __include() { mdsh-make "$1" "$2"; source "$2"; }
        @require "doco-include:$REPLY" __include "$@"
    fi
}
```

#### `project-name` *[service index]*

Returns the project name or container name of the specified service in `REPLY`.  The project name is derived from  `$COMPOSE_PROJECT_NAME` (or the project directory name if not set).  If no *index* is given, it defaults to `1`.  (e.g. `project_service_1`).

(Note: custom container names are **not** supported.)

```shell
project-name() {
    REPLY=${COMPOSE_PROJECT_NAME-}
    [[ $REPLY ]] || realpath.basename "$LOCO_ROOT"   # default to directory name
    REPLY=${REPLY//[^[:alnum:]]/}; REPLY=${REPLY,,}  # lowercase and remove non-alphanumerics
    ! (($#)) || REPLY=$REPLY"_${1}_${2-1}"           # container name
}
```

#### `require-services` *flag command-name*

Checks the number of currently selected services, based on *flag*.  If flag is `1`, then exactly one service must be selected; if `-`, then 0 or 1 services.  `+` means 1 or more services are required.  A flag of `.` is a no-op; i.e. all counts are acceptable. If the number of services selected (e.g. via the `--with` subcommand), does not match the requirement, abort with a usage error using *command-name*.

```shell
require-services() {
    case "$1${#DOCO_SERVICES[@]}" in
    ?1|-0|.*) return ;;  # 1 is always acceptable
    ?0)    loco_error "no services specified for $2" ;;
    [-1]*) loco_error "$2 cannot be used on multiple services" ;;
    esac
}
```

#### `set-alias` *alias services...*

Set the named *alias* to expand to the given list of services.  Similar to `ALIAS`, except that the existing service list for the alias is overwritten, only one *alias* can be supplied, and the supplied targets are interpreted as service names, ignoring any aliases.

```shell
set-alias() {
    local t=; (($#<2)) || printf -v t ' %q' "${@:2}"
    printf -v t 'doco-alias-%s() { REPLY=(%s); }' "$1" "$t"; eval "$t";
    printf -v t '| (.services."%s" |= f ) ' "${@:2}"
    DEFINE "def ${1//[^_[:alnum:]]/_}(f): . $t;"  # jqmd function names have a limited charset
}
```

#### `with-alias` *alias command...*

Run *command...* with the expansion of *alias* added to the current service set (without duplicating existing services).   (Note that *command* is a shell command, not a `doco` subcommand!)

```shell
with-alias() { get-alias "$1"; with-service "${REPLY[*]-}" "${@:2}"; }
```

#### `with-service` *service(s) command...*

Run command with *service(s)* added to the current service set (without duplicating existing services).  The first argument can be a space-separated list of service names.  (Note that *command* is a shell command, not a `doco` subcommand!)

```shell
with-service() {
    local svc DOCO_SERVICES=(${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"})
    for svc in $1; do
        [[ " ${DOCO_SERVICES[*]-} " == *" $svc "* ]] || DOCO_SERVICES+=("$svc")
    done
    "${@:2}"
}
```

### jq API

#### `services`

Assuming that `.` is a docker-compose configuration, return the (possibly-empty) dictionary of services from it.  If the configuration is empty or a compose v1 file (i.e. it lacks both `.services` and `.version`), `.` is returned.

```jq api
def services: if .services // .version then .services else . end;
```

#### `services_matching(filter)`

Assuming `.` is a docker-compose configuration, return a stream of `{key:, value:}` pairs containing the names and service dictionaries of services for which `(.value | filter)` returns truth.

```jq api
def services_matching(f): services | to_entries | .[] | select( .value | f ) ;
```

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

#### Non-Service Subcommands

But docker-compose subcommands that *don't* take services as their sole positional arguments don't get services appended:

```shell
# Commands that don't accept a list of services
for cmd in bundle config down help scale version; do
    eval "doco.$cmd() { compose $cmd \"\$@\"; }"
done
```

#### Single-Service Subcommands

Commands that take exactly *one* service (exec, run, and port) are modified to run on multiple services or no services.  When there are no services in the service set, they take an explicit service positionally, just like with docker-compose.  Otherwise, the positional service argument is assumed to be missing, and the command is run once for each service in the current set.

Inserting the service argument at the appropriate place requires parsing the command's options, specifically those that take an argument.

```shell
doco.exec() { __compose_one exec '-e|--env|-u|--user|--index' "$@"; }
doco.run()  { __compose_one run  '-p|--publish|-v|--volume|-w|--workdir|-e|--env|-u|--user|--name|--entrypoint' "$@"; }
doco.port() { __compose_one port '--protocol|--index' "$@"; }

__compose_one() {
    local svc opts=^$2\$ argv=("$1"); shift

    # Parse the command line, skipping options' argument values
    while shift && (($#)) && [[ $1 == -* ]]; do
        # Treat '--' as end of options
        if [[ $1 == -- ]]; then shift; break; fi
        argv+=("$1"); if [[ $1 =~ $opts ]]; then shift; argv+=("$1"); fi
    done

    if ((${#DOCO_SERVICES[@]})); then
        for svc in "${DOCO_SERVICES[@]}"; do compose "${argv[@]}" "$svc" "$@"; done
    else
        # XXX should check that $1 is a valid service
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

#### Aborting Options (--help, --version, etc.)

Some options pass directly the rest of the command line directly to docker-compose, ignoring any preceding options or prefix options:

```shell
docker-compose-immediate() {
    while (($#)); do eval "doco.$1() { docker-compose $1 \"\$@\"; }"; shift; done
}
docker-compose-immediate -h --help -v --version
```

#### Project-level Options

Project level options are fixed and can't be changed via the command line.

```shell
doco.-p() { loco_error "You must use COMPOSE_PROJECT_NAME to set the project name."; }
doco.-f() { loco_error "doco does not support -f and --file."; }
doco.--file() { doco -f "$@"; }
doco.--project-name() { doco -p "$@"; }
doco.--project-directory() { loco_error "doco: --project-directory cannot be overridden"; }
```

## Command-line Interface

### doco options

#### `--` *[subcommand args...]*

Reset the active service set to empty.  This can be used to ensure a command is invoked for all (or no) services, even if a service set was previously selected:

```shell
# Execute the rest of the command line with NO specified service(s)
doco.--()   { local DOCO_SERVICES=(); doco "$@"; }
```

#### `--all` *subcommand args...*

Update the service set to include *all* services, then invoke `doco` *subcommand args*.... Note that this is different from executing normal docker-compose commands with an empty (`--`) set, in that it explicitly lists all the services.

```shell
doco.--all() { doco --where true "$@"; }
```

#### `--where` *jq-filter [subcommand args...]*

Add services matching *jq-filter* to the current service set and invoke `doco` *subcommand args...*.  If the subcommand is omitted, outputs service names to stdout, one per line, returning a failure status of 1 and a message on stderr if no services match the given filter.  The filter is a jq expression that will be applied to the body of a service definition as it appears in the form *provided* to docker-compose.  (That is, values supplied by `extends` or variable interpolation are not available.)

```shell
doco.--where() {
    find-services "${@:1}"
    if (($#>1)); then
        with-service "${REPLY[*]-}" doco "${@:2}"   # run command on matching services
    elif ! ((${#REPLY[@]})); then
        echo "No matching services" >&2; return 1
    else
        printf '%s\n' "${REPLY[@]}"   # list matching services
    fi
}
```

#### `--with` *service [subcommand args...]*

The `with`  subcommand adds one or more services to the current service set and invokes  `doco` *subcommand args...*.  The *service* argument is either a single service name or a string containing a space-separated list of service names.  `--with` can be given more than once.  (To reset the service set to empty, use `--`.)

```shell
# Execute the rest of the command line with specified service(s)
doco.--with() { with-service "$1" doco "${@:2}"; }
```

At first glance, this command might appear redundant to simply adding the service names to the end of a regular command.  But since you can write custom subcommands that execute multiple docker commands, or that loop over `DOCO_SERVICES` to perform other operations (not to mention subcommands that invoke `with` with a preset list of services), it can come quite in handy.

#### `--with-default` *alias [subcommand args...]*

Invoke `doco` *subcommand args...*, adding *alias* to the current service set if the current set is empty.  *alias* can be nonexistent or empty, so you may wish to follow this option with `--require-services` to verify the new count.

```shell
doco.--with-default() {
    if have-services ''; then doco "${@:2}"; else with-alias "$1" doco "${@:2}"; fi
}
```

#### `--require-services` *flag [subcommand args...]*

This is the command-line equivalent of calling `require-services` *flag subcommand* before invoking *subcommand args...*.  That is, it checks that the relevant number of services are present and exits with a usage error if not.  The *flag* argument can include a space and a command name to be used in place of *subcommand* in any error messages.

```shell
doco.--require-services() {
    [[ ${1:0:1} == [-+1.] ]] || loco_error "--require-services argument must begin with ., -, +, or 1"
    # shellcheck disable=SC2090  # bash 4.3 needs this syntax because "${x[@]:0}" doesn't play nice w/-u
    mdsh-splitwords "$1" && require-services ${REPLY[@]+"${REPLY[@]}"} "$2" && doco "${@:2}";
}
```

### doco subcommands

#### `cmd` *flag subcommand...*

Shorthand for `--with-default cmd-default --require-services` *flag subcommand...*.  That is, if the current service set is empty, it defaults to the contents of the `cmd-default` alias, if any.  The number of services is then verified with `--require-services` before executing *subcommand*.  This makes it easy to define new subcommands that work on a default container or group of containers.  (For example, the `doco sh` command is defined as `doco cmd 1 exec bash "$@"` -- i.e., it runs on exactly one service, defaulting to the `cmd-default` alias.)

```shell
doco.cmd() { doco --with-default cmd-default --require-services "$@"; }
```

#### `cp` *[opts] src dest*

Copy a file in or out of a service container.  Functions the same as `docker cp`, except that instead of using a container name as a prefix, you can use either a service name or an empty string (meaning, the currently-selected service).  So, e.g. `doco cp :/foo bar` copies `/foo` from the current service to `bar`, while `doco cp baz spam:/thing` copies `baz` to `/thing` inside the `spam` service's first container.  If no service is selected and no service name is given, the `shell-default` alias is tried.

```shell
doco.cp() {
    local opts=() seen=''
    while (($#)); do
        case "$1" in
        -a|--archive|-L|--follow-link) opts+=("$1") ;;
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
                doco --with-default shell-default --require-services 1 cp ${opts[@]+"${opts[@]}"} "$@"; return $?
            fi
        elif [[ $1 != /* && $1 != - ]]; then
            # make paths relative to original run directory
            set -- "$LOCO_PWD/$1" "${@:2}";
        fi
        opts+=("$1"); shift
    done
    [[ "$seen" ]] || loco_error "cp: either source or destination must contain a :"
    docker cp ${opts[@]+"${opts[@]}"}
}
```

#### `foreach` *subcmd arg...*

Execute the given `doco` subcommand once for each service in the current service set, with the service set restricted to a single service for each subcommand.  This can be useful for explicit multiple (or zero) execution of a command that is otherwise restricted in how many times it can be executed.

```shell
doco.foreach() { foreach-service doco "$@"; }
```

#### `jq`

`doco jq` *args...* pipes the docker-compose configuration to `jq` *args...* as JSON.  Any functions defined via jqmd's facilities  (`DEFINES`, `IMPORTS`, `jq defs` blocks, `const` blocks, etc.) will be available to the given jq expression, if any.  If no expression is given, `.` is used.

```shell
doco.jq() { RUN_JQ "$@" <"$DOCO_CONFIG"; }
```

#### `sh`

`doco sh` *args...* executes `bash` *args* in the specified service's container.  If no service is specified, it defaults to the `cmd-default` alias.  Multiple services are not allowed.

```shell
doco.sh() { doco cmd 1 exec bash "$@"; }
```

## Merging jqmd and loco

We pass along our jq API functions to jqmd, and override the `mdsh-error` function to call `loco_error` so that all errors ultimately go through the same function.

```shell
DEFINE "${mdsh_raw_jq_api[*]}"
# shellcheck disable=SC2059  # argument is a printf format string
mdsh-error() { printf -v REPLY "$1"'\n' "${@:2}"; loco_error "$REPLY"; }
```