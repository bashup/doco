## Configuration

<!-- toc -->

- [Configuration vs. Runtime](#configuration-vs-runtime)
- [File and Function Names](#file-and-function-names)
- [Project-Level Configuration](#project-level-configuration)
- [Declarations](#declarations)
  * [`GROUP` *name(s)... operator target(s)...*](#group-names-operator-targets)
  * [`SERVICES` *name...*](#services-name)
  * [`VERSION` *docker-compose version*](#version-docker-compose-version)
- [Configuration Files API](#configuration-files-api)
  * [`export-env` *filename*](#export-env-filename)
  * [`export-source` *filename*](#export-source-filename)
  * [`include` *markdownfile [cachefile]*](#include-markdownfile-cachefile)

<!-- tocstop -->

### Configuration vs. Runtime

Some APIs are only available after configuration is complete, or only during configuration.  We expose a `project-is-finalized` function to indicate whether the docker-compose project definition has been generated yet.

```shell
project-is-finalized() { [[ ${DOCO_CONFIG-} ]]; }
```

### File and Function Names

Configuration is loaded using loco.  Specifically, by searching for `*.doco.md`, `.doco`, or `docker-compose.yml` above the current directory.  The loco script name is hardcoded to `doco`, so even if it's run via a symlink the function names for custom subcommands will still be `doco.subcommand-name`.  User and site-level configs are also defined.

```shell
loco_preconfig() {
    set -- "${BASH_VERSINFO[@]}"
    (( $1 > 4 || $1 == 4 && $2 >= 4 )) || mdsh-error "Sorry; doco requires bash 4.4 or better"
    export COMPOSE_PROJECT_NAME=
    LOCO_FILE=("?*[-.]doco.md" ".doco" "docker-compose.yml")
    LOCO_NAME=doco
    LOCO_USER_CONFIG=$HOME/.config/doco
    LOCO_SITE_CONFIG=/etc/doco/config
}
```

### Project-Level Configuration

Project configuration is loaded into `$LOCO_ROOT/.doco-cache.json` as JSON text, and `COMPOSE_FILE` is set to point to that file, for use by docker-compose.  (`COMPOSE_FILE` also gets the name of the `docker-compose.override` file, if any, with  `COMPOSE_PATH_SEPARATOR` set to a newline.)

If the configuration is a `*doco.md` file, it's entirely responsible for generating the configuration, and any standard `docker-compose{.override,}.y{a,}ml` file(s) are ignored.  Otherwise, the main YAML config is read before sourcing `.doco`, and the standard files are used to source the configuration.  (Note: the `.override` file, if any, is passed to docker-compose, but is *not* included in any jq filters or queries done by doco.)

Either way, service targets are created for any services that don't already have them.  (Minus any services that are only defined in an `.override`.)

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

    event fire "finalize_project"  # allow overriding the final compose project def
    RUN_JQ -c -n >"$json"; DOCO_CONFIG=$json; services-matching || return
    DOCO_CONFIG='' GROUP --all := "${REPLY[@]}"   # ensure SERVICES exist for all services
    target --all readonly          # make --all a read-only group
    event fire "before_commands"   # hook to set up aliases, custom commands, etc.
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

#### `GROUP` *name(s)... operator target(s)...*

Add *targets* to the named group(s), defining or redefining jq functions to map those groups to the targeted services.  The *targets* may be services or groups; if a target name isn't recognized it's assumed to be a service and defined as such.  The *operator* can be any of the following:

* `+=` adds *targets* to the named groups,
* `:=` clears the the named groups before adding the *targets*, and
* `/=` only adds the targets to groups that don't already exist.

Note that this function recursively expands groups in the target list, but this expansion is *immediate*: redefining a group used in the target list will *not* update the definition of the referencing group.

```shell
GROUP() {
    (($#>1)) || loco_error "GROUP requires at least two arguments"
    local op groups=(); while (($#)) && [[ $1 != [+:/]= ]]; do groups+=("$1"); shift; done
    for svc in "${@:2}"; do target "$svc" exists || target "$svc" declare-service || return; done
    case "${1-}" in
        +=) op='add' ;;
        :=) op='set' ;;
        /=) op='set-default' ;;
        *) fail "GROUP needs an operator: +=, :=, or /=" || return
    esac
    [[ ${groups[*]-} ]] || fail "No groups given" || return
    for REPLY in "${groups[@]}"; do target "$REPLY" "$op" "${@:2}"; done
}
```

Also note: services can't be declared once the docker-compose project definition has been finalized, so any targets passed to `GROUP` after the project definition is finalized must be *existing* services or groups.  Otherwise an error will occur.

#### `SERVICES` *name...*

Declare the named targets to be services and define jq functions for them.  `SERVICES foo bar` will create jq functions `foo()` and `bar()` that can be used to alter `.services.foo` and `.services.bar`, respectively.  The given names must be valid container names and must not already be defined as groups.

Note: services can't be declared once the docker-compose project definition has been finalized.

```shell
SERVICES() { for REPLY; do target "$REPLY" declare-service; done; }
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

