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

#### `foreach-service` *cmd args...*

Invoke *cmd args...* once for each service in the current service set; the service set will contain exactly one service during each invocation.

~~~shell
    $ SERVICES foo bar
    $ with-targets foo bar -- foreach-service eval 'echo "${DOCO_SERVICES[@]}"'
    foo
    bar
    $ foreach-service eval 'echo "${DOCO_SERVICES[@]}"'
~~~~

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

#### `require-services` *flag command-name*

Checks the number of currently selected services, based on *flag*.  If flag is `1`, then exactly one service must be selected; if `-`, then 0 or 1 services.  `+` means 1 or more services are required.  A flag of `.` is a no-op; i.e. all counts are acceptable. If the number of services selected (e.g. via the `--with` subcommand), does not match the requirement, abort with a usage error using *command-name*.

~~~shell
# Test harness:
    $ SERVICES x y
    $ doco.test-rs() { require-services "$1" test-rs || return; echo success; }
    $ test-rs() { (doco -- "${@:2}" test-rs "$1") || echo "[$?]"; }
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