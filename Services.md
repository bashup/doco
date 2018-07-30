## Services API

The services API depends on the [Targets API](Targets.md) and [bashup/events](https://github.com/bashup/events):

```shell mdsh
@require bashup/events cat         "$BASHER_PACKAGES_PATH/bashup/events/bashup.events"; echo
@require doco/targets  mdsh-source "$DEVKIT_ROOT/Targets.md"
```

### Automation

#### `find-services` *[jq-filter]*

Search the docker compose configuration for `services_matching(`*jq-filter*`)`, returning their names as an array in `REPLY`.  If *jq-filter* isn't supplied, `true` is used.  (i.e., find all services.)

```shell
find-services() { REPLY=$(RUN_JQ -r "services_matching(${1-true}) | .key" "$DOCO_CONFIG") && IFS=$'\n' mdsh-splitwords "$REPLY"; }
```

#### `foreach-service` *cmd args...*

Invoke *cmd args...* once for each service in the current service set; the service set will contain exactly one service during each invocation.  Does nothing if the current service set is empty.

```shell
foreach-service() {
    for REPLY in ${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"}; do
        local DOCO_SERVICES=("$REPLY"); "$@"
    done
}
```

#### `have-services` *[compexpr]*

Return true if the current service count matches the bash numeric comparison *compexpr*; if no *compexpr* is supplied, returns true if the current service count is non-zero.

```shell
have-services() { current-target has-count "$@"; }
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
    current-target get || REPLY=()
    case "$1${#REPLY[@]}" in
    ?1|-0|.*) return ;;  # 1 is always acceptable
    ?0)    loco_error "no services specified for $2" ;;
    [-1]*) loco_error "$2 cannot be used on multiple services" ;;
    esac
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

#### Generated Service Functions

doco automatically defines jq functions for all services and groups declared explicitly via `SERVICES` or `GROUP`.  These functions take one argument (an expression) and apply it to the service or services specified.  As a group's members change, the functions are updated.  When jq is finally run, the initial definition of the functions will match the final contents of the groups.

Because jq has a more limited character set than the allowable names for docker containers, function names are translated to have `::dot::` in place of `.`, and `::dash::` in place of `-`.  If a service or group name *begins* with a `-` or `.`, it's preceded by an `_`, e.g. a jq function for the group named `.foo` would be called `_::dot::foo`.

```shell
event on "change-group"   @_ generate-jq-func
event on "create-service" @_ generate-jq-func

generate-jq-func() {
    if [[ $1 != "@current" ]]; then
        local t; printf -v t '| (.services."%s" |= f ) ' "${@:2}"
        # jq function names can only have '_' or '::', not '-' or '.'
        set -- "${1//-/::dash::}"; set -- "${1//./::dot::}"; set -- "${1/#::/_::}"
        DEFINE "def $1(f): ${t:2};"
    fi
}
```

### Legacy API (Deprecated)

```shell
ALIAS() { mdsh-splitwords "$1"; GROUP "${REPLY[@}}" += "$@"; }
alias-exists() { target "$1" exists; }
get-alias() { target "$1" get || true; }
set-alias() { target "$1" set "$@"; }
with-alias() { target "$1" call "${@:2}"; }
with-service() { mdsh-splitwords "$1"; with-targets "${REPLY[@]}" -- "${@:2}"; }
```

