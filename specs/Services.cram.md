## Service Selection API

~~~shell
# Pre-define service names used in examples:

    $ SERVICES a b x y foo bar

# Set up services based on README.md

    $ cp "$TESTDIR"/../README.md readme.doco.md
    $ rm docker-compose.yml
    $ doco --  # initialize doco
~~~

### Automation

#### `have-services` *[compexpr]*

Return true if the current service count matches the bash numeric comparison *compexpr*; if no *compexpr* is supplied, returns true if the current service count is non-zero.

~~~shell
    $ SERVICES a b
    $ with-targets a b -- have-services '>1' && echo yes
    yes
    $ with-targets a b -- have-services '>2' || echo no
    no
    $ have-services || echo no
    no
~~~

#### `project-name` *[service index]*

Returns the project name or container name of the specified service in `REPLY`.  The project name is derived from  `$COMPOSE_PROJECT_NAME` (or the project directory name if not set).  If no *index* is given, it defaults to `1`.  (e.g. `project_service_1`).

(Note: custom container names are **not** supported.)

~~~shell
    $ project-name; echo $REPLY
    servicescrammd
    $ COMPOSE_PROJECT_NAME=foo project-name bar 3; echo $REPLY
    foo_bar_3
~~~

#### `quantify-services` *quantifier command-name [services...]*

Checks the number of *services* supplied, based on *flag*.  Returns without changing `${REPLY[@]}`.

If *quantifier* is `1`, then the list must contain exactly one service; if `-`, then 0 or 1 services are acceptable.  `+` means 1 or more services are required.  A *quantifier* of `.` is a no-op; i.e. any service count is acceptable.

If the number of services does not match the *quantifier*, failure is returned, with a usage error containing *command-name*.  (If *command-name* is empty or not given, the current `DOCO_COMMAND` is used, or failing that, the words "the current command".)

~~~shell
# First argument is validated

    $ quantify-services
    service quantifier must be ., -, +, or 1
    [64]

    $ quantify-services x
    service quantifier must be ., -, +, or 1
    [64]

# Test harness for exhaustive condition checking

    $ doco.test-rs() { quantify-services "$1" "" "${@:2}" || return; echo success; }
    $ test-rs() { doco test-rs "$@" || echo "[$?]"; }
    $ test-rs-all() { test-rs $1; test-rs $1 x y; test-rs $1 foo; }

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

#### `require-services` *quantifier [commands...]*

Like `quantify-services` except that it is applied to the current service set, or any default for any *commands*.  On success, `${REPLY[@]}` contains the applicable list of services.

~~~shell
# Check current set, default command name, require at least one service

    $ require-services +
    no services specified for the current command
    [64]

# Empty list returned, since @current was empty

    $ declare -p REPLY
    declare -a REPLY=()

# Multiple targets given, require at most one service

    $ with-targets x y -- require-services - SomeCommand
    SomeCommand cannot be used on multiple services
    [64]

# The targets are in REPLY

    $ declare -p REPLY
    declare -a REPLY=([0]="x" [1]="y")

# Explicit requirements: first existing group or target is checked and returned

    $ GROUP --empty-default :=
    $ GROUP --xy-default := x y

    $ require-services . test not-real empty xy && declare -p REPLY
    declare -a REPLY=()

    $ require-services . test not-real also-not-real xy empty && declare -p REPLY
    declare -a REPLY=([0]="x" [1]="y")
~~~

#### `services-matching` *[jq-filter]*

Search the docker compose configuration for `services_matching(`*jq-filter*`)`, returning their names as an array in `REPLY`.  If *jq-filter* isn't supplied, `true` is used.  (i.e., find all currently-defined services.)

~~~shell
    $ services-matching && declare -p REPLY | sed "s/'//g"
    declare -a REPLY=([0]="example1")

    $ services-matching false && declare -p REPLY | sed "s/'//g"
    declare -a REPLY=()

    $ DOCO_CONFIG= services-matching true && declare -p REPLY
    declare -a REPLY=()
~~~

Note that if this function is called while the compose project file is being generated, it returns only the services that match as of the moment it was invoked.  Any YAML, JSON, jq, or shell manipulation that follows its invocation could render the results out-of-date.  (If you're trying to dynamically alter the configuration, you should probably use a jq function or filter instead, perhaps using the jq [`services_matching`](#services_matchingfilter) function.)

### jq API

#### `services`

Assuming that `.` is a docker-compose configuration, return the (possibly-empty) dictionary of services from it.  If the configuration is empty or a compose v1 file (i.e. it lacks both `.services` and `.version`), `.` is returned.

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

~~~shell
    $ RUN_JQ -r 'services_matching(true) | .key' "$DOCO_CONFIG"
    example1
    $ RUN_JQ -r 'services_matching(.image == "bash") | .value.command' "$DOCO_CONFIG"
    bash -c 'echo hello world; echo'
~~~