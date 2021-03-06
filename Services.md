## Services API

The services API depends on the [Targets API](Targets.md) and [bashup/events](https://github.com/bashup/events):

```shell mdsh
@require bashup/events cat         "$BASHER_PACKAGES_PATH/bashup/events/bashup.events"; echo
@require doco/targets  mdsh-source "$DEVKIT_ROOT/Targets.md"
```

### Automation

#### `have-services` *[compexpr]*

Return true if the current service count matches the bash numeric comparison *compexpr*; if no *compexpr* is supplied, returns true if the current service count is non-zero.

```shell
have-services() { target @current has-count "$@"; }
```

#### `project-name` *[service index]*

Returns the the container name of the specified *service* (in `$REPLY`), or the name of the docker-composer project if no *service* is given.  If a *service* is given, its configuration is checked for a custom `container_name`, and it's returned if present.  Otherwise, the returned name is constructed from the project name plus the service name and the *index* (or `1` if no index is given).  So if the project name is `foo`, the service is `bar`, and the index is 3, the return value is `foo_bar_3`.

The project name is derived from  `$COMPOSE_PROJECT_NAME` (or the project directory name if not set).

```shell
project-name() {
    if (($#)); then
        REPLY=$(
            CLEAR_FILTERS; FILTER 'services[%s].container_name//""' "$1"
            RUN_JQ -r <"$DOCO_CONFIG"
        )
        [[ ! $REPLY ]] || return 0
    fi
    REPLY=${COMPOSE_PROJECT_NAME-}
    [[ $REPLY ]] || realpath.basename "$LOCO_ROOT"   # default to directory name
    REPLY=${REPLY//[^[:alnum:]]/}; REPLY=${REPLY,,}  # lowercase and remove non-alphanumerics
    ! (($#)) || REPLY=$REPLY"_${1}_${2-1}"           # container name
}
```

#### `quantify-services` *quantifier command-name [services...]*

Checks the number of *services* supplied, based on *flag*.  Returns without changing `${REPLY[@]}`.

If *quantifier* is `1`, then the list must contain exactly one service; if `-`, then 0 or 1 services are acceptable.  `+` means 1 or more services are required.  A *quantifier* of `.` is a no-op; i.e. any service count is acceptable.

If the number of services does not match the *quantifier*, failure is returned, with a usage error containing *command-name*.  (If *command-name* is empty or not given, the current `DOCO_COMMAND` is used, or failing that, the words "the current command".)

```shell
quantify-services() {
	[[ ${1-} == [-+1.] ]] ||
		fail "service quantifier must be ., -, +, or 1" || return
	set -- "$1" "${2-}" "${@:3}"
	set -- "$1$(($#-2))" "${2:-${DOCO_COMMAND:-the current command}}"
	case $1 in
		?1|-0|.*) return ;;  # 1 is always acceptable
		?0)    fail "no services specified for $2" ;;
		[-1]*) fail "$2 cannot be used on multiple services" ;;
	esac
}
```

#### `require-services` *quantifier [commands...]*

Like `quantify-services` except that it is applied to the current service set, or any default for any *commands*.  On success, `${REPLY[@]}` contains the applicable list of services.

```shell
require-services() {
	compose-defaults "${@:2}" || true
	quantify-services "${1-}" "${2-}" "${REPLY[@]}"
}
```

#### `services-matching` *[jq-filter]*

Search the docker compose configuration for `services_matching(`*jq-filter*`)`, returning their names as an array in `REPLY`.  If *jq-filter* isn't supplied, `true` is used.  (i.e., find all currently-defined services.)

```shell
services-matching() {
	REPLY=()
	local t="services_matching(${1-true}) | .key"
	t="$(
		[[ ${DOCO_CONFIG:+_} ]] || JQ_OPTS -n;
		RUN_JQ -r "$t" ${DOCO_CONFIG:+"$DOCO_CONFIG"}
	)" &&
	IFS=$'\n' mdsh-splitwords "$t"
}
```

Note that if this function is called while the compose project file is being generated, it returns only the services that match as of the moment it was invoked.  Any YAML, JSON, jq, or shell manipulation that follows its invocation could render the results out-of-date.  (If you're trying to dynamically alter the configuration, you should probably use a jq function or filter instead, perhaps using the jq [`services_matching`](#services_matchingfilter) function.)

### jq API

#### `services`

Assuming that `.` is a docker-compose configuration, return the (possibly-empty) dictionary of services from it.  If the configuration is empty or a compose v1 file (i.e. it lacks both `.services` and `.version`), `.` is returned.

```jq api
def services: if .services // .version then .services else . end;
```

#### `services_matching(filter)`

Assuming `.` is a docker-compose configuration, return a stream of `{key:, value:}` pairs containing the names and service dictionaries of services for which `(.value | filter)` returns truth.

```jq api
def services_matching(f): services // {} | to_entries | .[] | select( .value | f ) ;
```

#### Generated Service Functions

doco automatically defines jq functions for all services and groups declared explicitly via `SERVICES` or `GROUP`.  These functions take one argument (an expression) and apply it to the service or services specified.  These functions are defined on the fly whenever jq is run, so that the initial definition of the functions will match the contents of the groups as of the time RUN_JQ is called (e.g. at project finalization).

Because jq has a more limited character set than the allowable names for docker containers, function names are translated to have `::dot::` in place of `.`, and `::dash::` in place of `-`.  If a service or group name *begins* with a `-` or `.`, it's preceded by an `_`, e.g. a jq function for the group named `.foo` would be called `_::dot::foo`.

```shell
event on "create service" @1 event on "RUN_JQ" generate-jq-func
event on "create group"   @1 event on "RUN_JQ" generate-jq-func

RUN_JQ() {
	local jqmd_defines=${jqmd_defines-}
	event emit "RUN_JQ"  # allow on-the-fly defines
	JQ_CMD "$@" && "${REPLY[@]}"
}

generate-jq-func() {
    if [[ $1 != "@current" ]]; then
        target "$1" get; set -- "$1" "${REPLY[@]}"
        local t=; (($#<2)) || { printf -v t '| (.services."%s" |= f ) ' "${@:2}"; t=${t:2}; }
        target "$1" jq-name; DEFINE "def $REPLY(f): ${t:-.};"
    fi
}
```

### Legacy API (Deprecated)

```shell
ALIAS() { mdsh-splitwords "$1"; GROUP "${REPLY[@]}" += "${@:2}"; }
alias-exists() { target "$1" exists; }
get-alias() { target "$1" get; }
set-alias() { target "$1" set "$@"; }
with-alias() { target "$1" call "${@:2}"; }
with-service() { mdsh-splitwords "$1"; with-targets @current "${REPLY[@]}" -- "${@:2}"; }
find-services() { services-matching "$@"; }
foreach-service() { target @current foreach "$@"; }
```

