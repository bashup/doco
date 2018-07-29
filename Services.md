## Services API

### Automation

#### `alias-exists` *name*

Return success if *name* has previously been defined as a service or alias.

```shell
alias-exists() { fn-exists "doco-alias-$1"; }
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

