## Configuration

<!--toc-->

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

### Configuration Files API

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

