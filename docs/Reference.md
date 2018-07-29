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

<!-- tocstop -->

# doco - Project Automation and Literate Devops for docker-compose

doco is a project automation tool for doing literate devops with docker-compose.  It's an extension of both loco and jqmd, written as a literate program using mdsh.  Within this source file, `shell` code blocks are the main program, while `shell mdsh` blocks are metaprogramming, and `~~~shell` blocks are examples tested with cram.

And for our tests, we source this file and set up some testing tools:

~~~shell
# Load functions and turn off error exit
    $ source doco; set +e
    $ doco.no-op() { :;}

# Use README.md for default config
    $ cp $TESTDIR/../README.md readme.doco.md

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

~~~shell
# COMPOSE_FILE is exported, pointing to the cache; DOCO_CONFIG is the same,
# and COMPOSE_PATH_SEPARATOR is a line break
    $ declare -p COMPOSE_FILE DOCO_CONFIG COMPOSE_PATH_SEPARATOR
    declare -x COMPOSE_FILE="/*/Reference.md/.doco-cache.json" (glob)
    declare -- DOCO_CONFIG="/*/Reference.md/.doco-cache.json" (glob)
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
    Multiple doco.md files in /*/Reference.md (glob)
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
    Multiple docker-compose files in /*/Reference.md/t (glob)
    [64]
    $ rm docker-compose.yaml

# docker-compose.override.yml and docker-compose.override.yaml are included in COMPOSE_FILE
    $ echo 'doco.dump() { declare -p COMPOSE_FILE; }' >.doco
    $ command doco dump
    declare -x COMPOSE_FILE="/*/Reference.md/t/.doco-cache.json" (glob)
    $ touch docker-compose.override.yml; command doco dump
    declare -x COMPOSE_FILE="/*/Reference.md/t/.doco-cache.json (glob)
    /*/Reference.md/t/docker-compose.override.yml" (glob)
    $ touch docker-compose.override.yaml; command doco dump
    Multiple docker-compose.override files in /*/Reference.md/t (glob)
    [64]
    $ rm docker-compose.override.yml; command doco dump
    declare -x COMPOSE_FILE="/*/Reference.md/t/.doco-cache.json (glob)
    /*/Reference.md/t/docker-compose.override.yaml" (glob)

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

## API

### Declarations

#### `ALIAS` *name(s) targets...*

Add *targets* to the named alias(es), defining or redefining subcommands and jq functions to map those aliases to the targeted services.  The *targets* may be services or aliases; if a target name isn't recognized it's assumed to be a service and defined as such.  Multiple aliases can be updated at once by passing them as a space-separated string in the first argument, e.g. `ALIAS "foo bar" baz spam` adds `baz` and `spam` to both the `foo` and `bar` aliases.

(Note that this function *adds* to the existing alias(es) and recursively expands aliases in the target list.  If you want to set an exact list of services, use `set-alias` instead.  Also note that the "recursive" expansion is *immediate*: redefining an alias used in the target list will not change the definition of the alias referencing it.)

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

~~~shell
    $ VERSION 2.1
    $ echo '{}' | RUN_JQ -c
    {"version":"2.1"}
~~~

### Config

#### `export-env` *filename*

Parse a docker-compose format `env_file`, exporting the variables found therein.  Used to load the [project-level configuration](#project-level-configuration), but can also be used to load additional environment files.

Blank and comment lines are ignored, all others are fed to `export` after stripping the leading and trailing spaces.  The file should not use quoting, or shell escaping: the exact contents of a line after the `=` (minus trailing spaces) are used as the variable's contents.

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

~~~shell
    $ alias-exists nonesuch || echo nope
    nope
    $ (SERVICES nonesuch; alias-exists nonesuch && echo yep)
    yep
~~~

#### `compose`

`compose` *args* is short for `docker-compose` *args*, except that the project directory and config files are set to the ones calculated by doco.  The contents of the `DOCO_OPTS` array are included before the supplied arguments:

~~~shell
    $ (DOCO_OPTS=(--tls -f foo); compose bar baz)
    docker-compose --tls -f foo bar baz
~~~

#### `find-services` *[jq-filter]*

Search the docker compose configuration for `services_matching(`*jq-filter*`)`, returning their names as an array in `REPLY`.  If *jq-filter* isn't supplied, `true` is used.  (i.e., find all services.)

~~~shell
    $ find-services; declare -p REPLY | sed "s/'//g"
    declare -a REPLY=([0]="example1")
    $ find-services false; declare -p REPLY | sed "s/'//g"
    declare -a REPLY=()
~~~

#### `foreach-service` *cmd args...*

Invoke *cmd args...* once for each service in the current service set; the service set will contain exactly one service during each invocation.

~~~shell
    $ with-service "foo bar" foreach-service eval 'echo "${DOCO_SERVICES[@]}"'
    foo
    bar
    $ foreach-service eval 'echo "${DOCO_SERVICES[@]}"'
~~~

#### `get-alias` *alias*

Return the current value of alias *alias* as an array in `REPLY`.  Returns an empty array if the alias doesn't exist.

~~~shell
    $ get-alias tango; printf '%q\n' ${REPLY[@]}
    niner
    gamma-zulu
    $ get-alias nonesuch; echo ${#REPLY[@]}
    0
~~~

#### `have-services` *[compexpr]*

Return true if the current service count matches the bash numeric comparison *compexpr*; if no *compexpr* is supplied, returns true if the current service count is non-zero.

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

#### `project-name` *[service index]*

Returns the project name or container name of the specified service in `REPLY`.  The project name is derived from  `$COMPOSE_PROJECT_NAME` (or the project directory name if not set).  If no *index* is given, it defaults to `1`.  (e.g. `project_service_1`).

(Note: custom container names are **not** supported.)

~~~shell
    $ project-name; echo $REPLY
    referencemd
    $ COMPOSE_PROJECT_NAME=foo project-name bar 3; echo $REPLY
    foo_bar_3
~~~

#### `require-services` *flag command-name*

Checks the number of currently selected services, based on *flag*.  If flag is `1`, then exactly one service must be selected; if `-`, then 0 or 1 services.  `+` means 1 or more services are required.  A flag of `.` is a no-op; i.e. all counts are acceptable. If the number of services selected (e.g. via the `--with` subcommand), does not match the requirement, abort with a usage error using *command-name*.

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

~~~shell
    $ set-alias fiz bar baz; get-alias fiz; printf '%q\n' "${REPLY[@]}"
    bar
    baz
    $ set-alias fiz bar; get-alias fiz; printf '%q\n' "${REPLY[@]}"
    bar
~~~

#### `with-alias` *alias command...*

Run *command...* with the expansion of *alias* added to the current service set (without duplicating existing services).   (Note that *command* is a shell command, not a `doco` subcommand!)

~~~shell
    $ with-alias fiz eval $'printf \'%q\n\' "${DOCO_SERVICES[@]}"'
    bar
~~~

#### `with-service` *service(s) command...*

Run command with *service(s)* added to the current service set (without duplicating existing services).  The first argument can be a space-separated list of service names.  (Note that *command* is a shell command, not a `doco` subcommand!)

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

## Docker-Compose Integration

### Docker-Compose Subcommands

#### Multi-Service Subcommands

Unrecognized subcommands are first checked to see if they're an alias.  If not, they're sent to docker-compose, with the current service set appended to the command line.  (The service set is empty by default, causing docker-compose to apply commands to all services by default.)

~~~shell
    $ doco foo
    docker-compose foo
    $ (ALIAS foo bar; doco foo ps)
    docker-compose ps bar
    $ (ALIAS foo bar; doco foo bar)
~~~

#### Non-Service Subcommands

But docker-compose subcommands that *don't* take services as their sole positional arguments don't get services appended:

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

### Docker-Compose Options

  A few (like `--version` and `--help`) need to exit immediately, and a few others need special handling:

#### Generic Options

Most docker-compose global options are added to the `DOCO_OPTS` array, where they will pass through to any subcommand.

~~~shell
    $ doco --verbose --tlskey blah foo
    docker-compose --verbose --tlskey blah foo
~~~

#### Aborting Options (--help, --version, etc.)

Some options pass directly the rest of the command line directly to docker-compose, ignoring any preceding options or prefix options:

~~~shell
    $ doco --help --verbose something blah
    docker-compose --help --verbose something blah
~~~

#### Project-level Options

Project level options are fixed and can't be changed via the command line.

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

## Command-line Interface

### doco options

#### `--` *[subcommand args...]*

Reset the active service set to empty.  This can be used to ensure a command is invoked for all (or no) services, even if a service set was previously selected:

~~~shell
    $ doco --with "a b c" -- ps
    docker-compose ps
~~~

#### `--all` *subcommand args...*

Update the service set to include *all* services, then invoke `doco` *subcommand args*.... Note that this is different from executing normal docker-compose commands with an empty (`--`) set, in that it explicitly lists all the services.

~~~shell
    $ doco --all ps
    docker-compose ps example1
~~~

#### `--where` *jq-filter [subcommand args...]*

Add services matching *jq-filter* to the current service set and invoke `doco` *subcommand args...*.  If the subcommand is omitted, outputs service names to stdout, one per line, returning a failure status of 1 and a message on stderr if no services match the given filter.  The filter is a jq expression that will be applied to the body of a service definition as it appears in the form *provided* to docker-compose.  (That is, values supplied by `extends` or variable interpolation are not available.)

~~~shell
    $ doco --where true
    example1
    $ doco --where false
    No matching services
    [1]
    $ doco --where false ps
    docker-compose ps
    $ doco --where true ps
    docker-compose ps example1
~~~

#### `--with` *service [subcommand args...]*

The `with`  subcommand adds one or more services to the current service set and invokes  `doco` *subcommand args...*.  The *service* argument is either a single service name or a string containing a space-separated list of service names.  `--with` can be given more than once.  (To reset the service set to empty, use `--`.)

At first glance, this command might appear redundant to simply adding the service names to the end of a regular command.  But since you can write custom subcommands that execute multiple docker commands, or that loop over `DOCO_SERVICES` to perform other operations (not to mention subcommands that invoke `with` with a preset list of services), it can come quite in handy.

~~~shell
    $ doco --with "a b" ps
    docker-compose ps a b
    $ doco --with "a b" --with c ps
    docker-compose ps a b c
~~~

#### `--with-default` *alias [subcommand args...]*

Invoke `doco` *subcommand args...*, adding *alias* to the current service set if the current set is empty.  *alias* can be nonexistent or empty, so you may wish to follow this option with `--require-services` to verify the new count.

~~~shell
    $ doco -- --with-default alfa ps
    docker-compose ps alfa

    $ doco foxtrot --with-default alfa ps -q
    docker-compose ps -q foxtrot
~~~

#### `--require-services` *flag [subcommand args...]*

This is the command-line equivalent of calling `require-services` *flag subcommand* before invoking *subcommand args...*.  That is, it checks that the relevant number of services are present and exits with a usage error if not.  The *flag* argument can include a space and a command name to be used in place of *subcommand* in any error messages.

~~~shell
    $ (doco -- --require-services "1 somecommand" ps)
    no services specified for somecommand
    [64]
    $ (doco -- --require-services ps)
    --require-services argument must begin with ., -, +, or 1
    [64]
~~~

### doco subcommands

#### `cmd` *flag subcommand...*

Shorthand for `--with-default cmd-default --require-services` *flag subcommand...*.  That is, if the current service set is empty, it defaults to the contents of the `cmd-default` alias, if any.  The number of services is then verified with `--require-services` before executing *subcommand*.  This makes it easy to define new subcommands that work on a default container or group of containers.  (For example, the `doco sh` command is defined as `doco cmd 1 exec bash "$@"` -- i.e., it runs on exactly one service, defaulting to the `cmd-default` alias.)

~~~shell
    $ (doco cmd 1 test)
    no services specified for test
    [64]

    $ (set-alias cmd-default foxtrot; doco cmd 1 exec testme)
    docker-compose exec foxtrot testme
~~~

#### `cp` *[opts] src dest*

Copy a file in or out of a service container.  Functions the same as `docker cp`, except that instead of using a container name as a prefix, you can use either a service name or an empty string (meaning, the currently-selected service).  So, e.g. `doco cp :/foo bar` copies `/foo` from the current service to `bar`, while `doco cp baz spam:/thing` copies `baz` to `/thing` inside the `spam` service's first container.  If no service is selected and no service name is given, the `shell-default` alias is tried.

~~~shell
# Nominal cases

    $ doco cp -h
    docker help cp

    $ doco cp -L /foo bar:/baz
    docker cp -L /foo referencemd_bar_1:/baz

    $ doco cp bar:/spam -
    docker cp referencemd_bar_1:/spam -

    $ (doco cp :x y)
    no services specified for cp
    [64]

    $ (ALIAS shell-default bravo; doco cp :x y)
    docker cp referencemd_bravo_1:x /*/Reference.md/y (glob)

    $ (ALIAS shell-default bravo; LOCO_PWD=$PWD/t doco --with bravo cp y :x)
    docker cp /*/Reference.md/t/y referencemd_bravo_1:x (glob)

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

#### `foreach` *subcmd arg...*

Execute the given `doco` subcommand once for each service in the current service set, with the service set restricted to a single service for each subcommand.  This can be useful for explicit multiple (or zero) execution of a command that is otherwise restricted in how many times it can be executed.

~~~shell
    $ doco --with "x y" foreach ps
    docker-compose ps x
    docker-compose ps y

    $ doco -- foreach ps
~~~

#### `jq`

`doco jq` *args...* pipes the docker-compose configuration to `jq` *args...* as JSON.  Any functions defined via jqmd's facilities  (`DEFINES`, `IMPORTS`, `jq defs` blocks, `const` blocks, etc.) will be available to the given jq expression, if any.  If no expression is given, `.` is used.

~~~shell
    $ doco jq .version
    "2.1"
~~~

#### `sh`

`doco sh` *args...* executes `bash` *args* in the specified service's container.  If no service is specified, it defaults to the `cmd-default` alias.  Multiple services are not allowed.

~~~shell
    $ (doco sh)
    no services specified for exec
    [64]

    $ (doco tango sh)
    exec cannot be used on multiple services
    [64]

    $ doco alfa sh
    docker-compose exec alfa bash

    $ (ALIAS cmd-default foxtrot; doco sh -c 'echo foo')
    docker-compose exec foxtrot bash -c echo\ foo
~~~
