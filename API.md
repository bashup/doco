#!/usr/bin/env bash
: '
<!-- ex: set syntax=markdown : '; eval "$(mdsh -E "$BASH_SOURCE")"; # -->

## doco API

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

### Contents

<!-- toc -->

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

<!-- tocstop -->

### Declarations

#### `ALIAS` *name(s) targets...*

Add *targets* to the named alias(es), defining or redefining subcommands and jq functions to map those aliases to the targeted services.  The *targets* may be services or aliases; if a target name isn't recognized it's assumed to be a service and defined as such.  Multiple aliases can be updated at once by passing them as a space-separated string in the first argument, e.g. `ALIAS "foo bar" baz spam` adds `baz` and `spam` to both the `foo` and `bar` aliases.

(Note that this function *adds* to the existing alias(es) and recursively expands aliases in the target list.  If you want to set an exact list of services, use `set-alias` instead.  Also note that the "recursive" expansion is *immediate*: redefining an alias used in the target list will not change the definition of the alias referencing it.)

```shell
ALIAS() {
    local alias svc DOCO_SERVICES=()
    (($#>1)) || loco_error "ALIAS requires at least two arguments"
    SERVICES "${@:2}"; for alias in $1; do __mkalias "$alias" "${@:2}"; done
}
__mkalias() {
     if (($#)); then with-alias "$1" __mkalias "${@:2}"; return; fi
     set-alias "$alias" ${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"}
}
```

~~~shell
# Arguments required

    $ (ALIAS)
    ALIAS requires at least two arguments
    [64]

# Alias one, non-existing name

    $ ALIAS delta-xray echo gamma-zulu
    $ doco delta-xray ps
    docker-compose ps echo gamma-zulu
    $ RUN_JQ -c -n '{} | delta_xray(.image = "test")'
    {"services":{"echo":{"image":"test"},"gamma-zulu":{"image":"test"}}}

# Add to multiple aliases, adding but not duplicating

    $ ALIAS "tango delta-xray" niner gamma-zulu
    $ doco delta-xray ps
    docker-compose ps echo gamma-zulu niner
    $ RUN_JQ -c -n '{} | delta_xray(.image = "test")'
    {"services":{"echo":{"image":"test"},"gamma-zulu":{"image":"test"},"niner":{"image":"test"}}}

    $ doco tango ps
    docker-compose ps niner gamma-zulu
    $ RUN_JQ -c -n '{} | tango(.image = "test")'
    {"services":{"niner":{"image":"test"},"gamma-zulu":{"image":"test"}}}

# "Recursive" alias expansion

    $ ALIAS whiskey tango foxtrot
    $ doco whiskey ps
    docker-compose ps niner gamma-zulu foxtrot
~~~

#### `SERVICES` *name...*

Define subcommands and jq functions for the given service names.  `SERVICES foo bar` will create `foo` and `bar` commands that set the current service set (`DOCO_SERVICES`)  to that service, along with jq functions `foo()` and `bar()` that can be used to alter `.services.foo` and `.services.bar`, respectively.  If an alias of a given *name* is already defined, it is *not* redefined.

(Note: this command is effectively a shortcut for aliasing a service name to itself if it doesn't already exist, i.e. `set-alias` *name name*.)

```shell
SERVICES() { for svc in "$@"; do alias-exists "$svc" || set-alias "$svc" "$svc"; done; }
```

~~~shell
    $ SERVICES alfa foxtrot

# command alias sets the active service set
    $ doco alfa ps
    docker-compose ps alfa

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

~~~shell
    $ export() { printf "export %q\n" "$@"; }   # stub
    $ export-env /dev/stdin <<'EOF'
    > # comment
    >    # indented comment
    >    THIS=$that
    > SOME=thing = else  
    > 
    >  OTHER
    > EOF
    export THIS=\$that
    export SOME=thing\ =\ else
    export OTHER
    $ unset -f export   # ditch the stub
~~~

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

~~~shell
    $ declare -p FOO 2>/dev/null || echo undefined
    undefined
    $ echo "FOO=bar" >dummy.env
    $ export-source dummy.env
    $ declare -p FOO 2>/dev/null || echo undefined
    declare -x FOO="bar"
~~~

### Automation

#### `alias-exists` *name*

Return success if *name* has previously been defined as a service or alias.

```shell
alias-exists() { fn-exists "doco-alias-$1"; }
```

~~~shell
    $ alias-exists nonesuch || echo nope
    nope
    $ (SERVICES nonesuch; alias-exists nonesuch && echo yep)
    yep
~~~

#### `compose`

`compose` *args* is short for `docker-compose` *args*, except that the project directory and config files are set to the ones calculated by doco.  The contents of the `DOCO_OPTS` array are included before the supplied arguments:

```shell
DOCO_OPTS=()
compose() { docker-compose ${DOCO_OPTS[@]+"${DOCO_OPTS[@]}"} "$@"; }
```

~~~shell
    $ (DOCO_OPTS=(--tls -f foo); compose bar baz)
    docker-compose --tls -f foo bar baz
~~~

#### `find-services` *[jq-filter]*

Search the docker compose configuration for `services_matching(`*jq-filter*`)`, returning their names as an array in `REPLY`.  If *jq-filter* isn't supplied, `true` is used.  (i.e., find all services.)

```shell
find-services() { REPLY=$(RUN_JQ -r "services_matching(${1-true}) | .key" "$DOCO_CONFIG") && IFS=$'\n' mdsh-splitwords "$REPLY"; }
```

~~~shell
    $ find-services; declare -p REPLY | sed "s/'//g"
    declare -a REPLY=([0]="example1")
    $ find-services false; declare -p REPLY | sed "s/'//g"
    declare -a REPLY=()
~~~

#### `foreach-service` *cmd args...*

Invoke *cmd args...* once for each service in the current service set; the service set will contain exactly one service during each invocation.

```shell
foreach-service() {
    for REPLY in ${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"}; do
        local DOCO_SERVICES=("$REPLY"); "$@"
    done
}
```

~~~shell
    $ with-service "foo bar" foreach-service eval 'echo "${DOCO_SERVICES[@]}"'
    foo
    bar
    $ foreach-service eval 'echo "${DOCO_SERVICES[@]}"'
~~~

#### `get-alias` *alias*

Return the current value of alias *alias* as an array in `REPLY`.  Returns an empty array if the alias doesn't exist.

```shell
get-alias() { REPLY=(); ! alias-exists "$1" || "doco-alias-$1"; }
```

~~~shell
    $ get-alias tango; printf '%q\n' ${REPLY[@]}
    niner
    gamma-zulu
    $ get-alias nonesuch; echo ${#REPLY[@]}
    0
~~~

#### `have-services` *[compexpr]*

Return true if the current service count matches the bash numeric comparison *compexpr*; if no *compexpr* is supplied, returns true if the current service count is non-zero.

```shell
# shellcheck disable=SC2120  # shellcheck doesn't understand optional arguments
have-services() { eval "((${#DOCO_SERVICES[@]} ${1-}))"; }
```

~~~shell
    $ with-service "a b" have-services '>1' && echo yes
    yes
    $ with-service "a b" have-services '>2' || echo no
    no
    $ have-services || echo no
    no
~~~

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

~~~shell
    $ project-name; echo $REPLY
    apimd
    $ COMPOSE_PROJECT_NAME=foo project-name bar 3; echo $REPLY
    foo_bar_3
~~~

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

~~~shell
# Test harness:
    $ doco.test-rs() { require-services "$1" test-rs; echo success; }
    $ test-rs() { (doco -- "${@:2}" test-rs "$1") || echo "[$?]"; }
    $ test-rs-all() { test-rs $1; test-rs $1 --with "x y"; test-rs $1 --with foo; }

# 1 = exactly one service
    $ test-rs-all 1
    no services specified for test-rs
    [64]
    test-rs cannot be used on multiple services
    [64]
    success

# - = at most one service
    $ test-rs-all -
    success
    test-rs cannot be used on multiple services
    [64]
    success

# + = at least one service
    $ test-rs-all +
    no services specified for test-rs
    [64]
    success
    success

# . = any number of services
    $ test-rs-all .
    success
    success
    success
~~~

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

~~~shell
    $ set-alias fiz bar baz; get-alias fiz; printf '%q\n' "${REPLY[@]}"
    bar
    baz
    $ set-alias fiz bar; get-alias fiz; printf '%q\n' "${REPLY[@]}"
    bar
~~~

#### `with-alias` *alias command...*

Run *command...* with the expansion of *alias* added to the current service set (without duplicating existing services).   (Note that *command* is a shell command, not a `doco` subcommand!)

```shell
with-alias() { get-alias "$1"; with-service "${REPLY[*]-}" "${@:2}"; }
```

~~~shell
    $ with-alias fiz eval $'printf \'%q\n\' "${DOCO_SERVICES[@]}"'
    bar
~~~

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

~~~shell
    $ with-service "foo bar" with-service "bar baz" eval $'printf \'%q\n\' "${DOCO_SERVICES[@]}"'
    foo
    bar
    baz
~~~



### jq API

#### `services`

Assuming that `.` is a docker-compose configuration, return the (possibly-empty) dictionary of services from it.  If the configuration is empty or a compose v1 file (i.e. it lacks both `.services` and `.version`), `.` is returned.

```jq api
def services: if .services // .version then .services else . end;
```

~~~shell
    $ RUN_JQ -n -c '{x: 27} | services'                 # root if no services
    {"x":27}
    $ RUN_JQ -n -c '{services: {y:42}} | services'      # .services if present
    {"y":42}
    $ RUN_JQ -n -c '{version: "2.1"} | services'        # .services if .version
    null
~~~

#### `services_matching(filter)`

Assuming `.` is a docker-compose configuration, return a stream of `{key:, value:}` pairs containing the names and service dictionaries of services for which `(.value | filter)` returns truth.

```jq api
def services_matching(f): services | to_entries | .[] | select( .value | f ) ;
```

~~~shell
    $ RUN_JQ -r 'services_matching(true) | .key' "$DOCO_CONFIG"
    example1
    $ RUN_JQ -r 'services_matching(.image == "bash") | .value.command' "$DOCO_CONFIG"
    bash -c 'echo hello world; echo'
~~~

