## Targets (Services and Groups)

Targets are the names of services, or groups of services.  They follow the rules of docker-compose container names:

~~~shell
    $ is-target-name "foo.bar_BAZ-54" && echo yep
    yep

    $ is-target-name "&%(@'" || echo nope
    nope
~~~

You can reference a target using `target "name"`, but will get an error if the name is invalid.

~~~shell
    $ target "foo/bar"
    Group or service name 'foo/bar' contains invalid characters
    [64]
~~~

### Target Types

Until a target name is made into a service or a group, it is considered neither, and is nonexistent:

~~~shell
    $ target "nosuch" exists || echo non-existent
    non-existent

    $ target "nosuch" is-group || echo not a group
    not a group

    $ target "nosuch" is-service || echo not a service either
    not a service either
~~~

A target's type is set using `declare-service` or `declare-group`.  When the target is initialized, an event is emitted.  (Services actually get two events; one generic, one specific to the service name.)  Subsequent declarations have no effect, other than to verify that the target is of that type.

~~~shell
    $ event on "create service" @_ echo "created service:"
    $ event on "create group"   @_ echo "created group:"

    $ target "aService" declare-service
    created service: aService

    $ target "aGroup" declare-group
    created group: aGroup

    $ target "aService" declare-service   # no events once they already exist
    $ target "aGroup" declare-group

    $ target "aGroup"   is-group   && ! target "aGroup"   is-service && echo yep
    yep
    $ target "aService" is-service && ! target "aService" is-group   && echo yep
    yep

    $ target "aService" declare-group
    aService is a service, but a group was expected
    [64]

    $ target "aGroup" declare-service
    aGroup is a group, but a service was expected
    [64]
~~~

#### Async Events

In addition to the generic `create-service` and `create-group` events, there are also service and group-specific events that are asynchronous.  Registering for `created-service X` or `created-group Y` will invoke the callback immediately if the named service or group already exists.  Otherwise, the callback will be invoked later, if and when the service or group is actually defined.

~~~shell
# "created" events are async: they fire even after the creation took place

    $ event on "created service aService" @_ echo "Specifically created aService w/arg"
    Specifically created aService w/arg aService

    $ event on "created group aGroup" @_ echo "Specifically created aGroup w/arg"
    Specifically created aGroup w/arg aGroup


~~~

### Target Contents

Targets expand to an array of service names.  A service is a target that expands to exactly one service name: itself.  Groups, on the other hand, can expand to zero or more service names.  (And undeclared targets don't expand.)  You can fetch the names into the `REPLY` array using `get`, and check the count using `has-count`.

~~~shell
    $ target "aService" get exists && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    1 items: aService

    $ target "aGroup" get exists && echo "${#REPLY[@]} items"
    0 items

    $ target "nosuch" exists || echo "nonexistent"
    nonexistent

# has-count returns the truth value of the number of items

    $ target "aService" has-count && echo "it has a count"
    it has a count
    $ target "aGroup" has-count || echo "no count"
    no count

# or if given a condition argument, it performs a numeric comparison

    $ target "aService" has-count '==1' && echo "it has a count of 1"
    it has a count of 1

    $ target "aGroup" has-count '<1' && echo "it has a count less than 1"
    it has a count less than 1
~~~

#### Adding to Groups

You can add targets to groups or non-existent targets (making them into a group), but the added targets have to exist first.  Events are issued for group changes, and a given service can only exist once within a given group.  Groups can be added to other groups, but the result still contains only services:

~~~shell
    $ event on "change group" @_ echo "group changed:"

    $ target "aService" add "nosuch"
    aService is a service, but a group was expected
    [64]

    $ target "aGroup" add "nosuch"
    'nosuch' is not a known group or service
    [64]

    $ target "aGroup" add "aService"
    group changed: aGroup aService

    $ target "aGroup" get exists && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    1 items: aService

    $ target "aGroup" add "aService"   # second add does nothing
    $ target "aGroup" get exists && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    1 items: aService

    $ target "svc2" declare-service
    created service: svc2

    $ target "nosuch" add svc2 aService   # nosuch is now a group
    created group: nosuch
    group changed: nosuch svc2 aService

    $ target "nosuch" get exists && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    2 items: svc2 aService

    $ target "aGroup" add "nosuch"
    group changed: aGroup aService svc2
~~~

#### Resetting a Group

Groups can be `set` to a list of targets (i.e., existing services or groups), dropping whatever was there before and possibly issuing a change event.

~~~shell
    $ target "nosuch" set
    group changed: nosuch

    $ target "nosuch" get exists && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    0 items:

    $ target "nosuch" set aService svc2
    group changed: nosuch aService svc2

    $ target "nosuch" set aService svc2   # no change = no event
~~~

#### Setting Default Contents

The `set-default` method works like `set`, except that it only works on non-existent groups

~~~shell
    $ target "nosuch" set-default svc2   # no change, no event

    $ target "not-yet" set-default svc2
    created group: not-yet
    group changed: not-yet svc2

    $ target "not-yet" set-default aService  # no change, no event
~~~

#### Read-only Targets

Groups can be made read-only; services are always read-only.  Any attempt to change a read-only group (even to its existing value) immediately terminates the current bash process.

~~~shell
    $ target "nosuch" readonly
    $ (target "nosuch" set aService svc2)
    *: TARGET: readonly variable (glob)
    [1]

    $ declare -p __doco_target_aService   # services are read-only variables
    declare -ar __doco_target_aService=([0]="aService")
~~~

### Target Environments

Service targets can fetch their environments as an array of `key=val` strings using `get-env`, or run a command with local variables set from them (using `with-env`).  docker-compose's escaping of `$` is handled correctly, as are multi-line values.  (You can also dump them to stdout with `cat-env`.)

~~~sh
# Only services can get-env

    $ target aGroup get-env
    aGroup is not a service
    [64]

    $ target @current get-env
    @current is not a service
    [64]

# Environment is loaded from compose-config, so let's mock that and
# pretend we already have the configuration

    $ compose-config() { echo "calling compose-config" >&2; }
    $ COMPOSED_JSON='{"services": {"svc2": {"environment": { "X": "y$$z", "Q": "r\ns" }}}}'

# aService has no environment, so we get nothing.

    $ target aService get-env; echo ${#REPLY[@]}
    calling compose-config
    0
    $ target aService get-env; echo ${#REPLY[@]}  # call 2 is cached, so no config fetch
    0

# svc2 has two variables, one with `$$` and the other with a linefeed

    $ target svc2 cat-env
    calling compose-config
    X='y$z'
    Q='r
    s'

# But they are correctly parsed into k=v strings by get-env:
# (cat-env doesn't cache, so compose-config will be called again)

    $ target svc2 get-env; printf '%q\n' "${REPLY[@]}"
    calling compose-config
    X=y\$z
    $'Q=r\ns'

# with-env exposes the variables to the shell

    $ target svc2 with-env declare -p Q
    declare -- Q="r
    s"
~~~

### The Current Target

A special target `@current` is used to access a special read-only group whose contents are stored in the `DOCO_SERVICES` variable.  It is used to designate what service names will be passed to docker-compose for a given command.

~~~shell
    $ declare -p DOCO_SERVICES
    *: declare: DOCO_SERVICES: not found (glob)
    [1]

    $ target @current exists || echo nope
    nope

    $ target @current add nosuch
    @current group is read-only
    [64]

~~~

#### `with-targets`

The current target can be set for the duration of one command/function call using `with-targets` *targets...* `--` *command...*, during which the `DOCO_SERVICES` variable will be read-only, but still changeable using `with-targets`.  You can include `@current` in the target list, to merge the other targets with the current target set.

The value of `DOCO_COMMAND` is reset to empty during the execution of *command*.

~~~shell
# with-targets expands groups, and issues change events for @current

    $ DOCO_COMMAND=foo
    $ with-targets "nosuch" -- declare -p DOCO_SERVICES DOCO_COMMAND
    declare -ar DOCO_SERVICES=([0]="aService" [1]="svc2")
    declare -- DOCO_COMMAND

    $ declare -p DOCO_SERVICES   # back to not existing
    *: declare: DOCO_SERVICES: not found (glob)
    [1]

    $ with-targets -- declare -p DOCO_SERVICES
    declare -ar DOCO_SERVICES=()

    $ with-targets svc2 -- declare -p DOCO_SERVICES
    declare -ar DOCO_SERVICES=([0]="svc2")

# with-targets can stack, and target list can inlcude @current to merge

    $ with-targets aService -- with-targets @current svc2 -- declare -p DOCO_SERVICES
    declare -ar DOCO_SERVICES=([0]="aService" [1]="svc2")

    $ declare -p DOCO_SERVICES
    *: declare: DOCO_SERVICES: not found (glob)
    [1]

~~~

#### `without-targets` *command...*

Run *command* with a non-existent  `@current` target.

~~~shell
    $ target @current exists || echo nonexistent
    nonexistent

    $ with-targets -- target @current exists && echo exists # empty @current DOES exist
    exists

    $ without-targets target @current exists || echo nonexistent
    nonexistent
~~~

#### `target` *target* `foreach` *command...*

Run *command* zero or more times, once for each service in *target*, with the current target set to the corresponding service.

~~~shell
    $ target @current foreach declare -p DOCO_SERVICES   # no entries; doesn't run

    $ target aService foreach declare -p DOCO_SERVICES
    declare -ar DOCO_SERVICES=([0]="aService")

    $ target "nosuch" foreach declare -p DOCO_SERVICES
    declare -ar DOCO_SERVICES=([0]="aService")
    declare -ar DOCO_SERVICES=([0]="svc2")
~~~

### Finding and Merging Targets

The `all-targets` function takes one or more target names, and sets `REPLY` to a unique array of the service names referenced by those targets, returning success unless any of the named targets are invalid or undefined.  (As a special case, `@current` not existing is treated as if it did exist, but was empty.)

The `any-targets` function takes one or more target names, and sets `REPLY` to the array of services referenced by the first target that `exists`, whether that target is empty or not.  (But `@current` is not treated specially; if non-existent, it's skipped.)  Success is returned unless none of the supplied targets exist.

~~~shell
# all-targets returns unique items from all the named targets

    $ all-targets nosuch aService && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    2 items: aService svc2

# but fails if any targets (other than @current) don't exist:

    $ all-targets svc2 @current not-defined
    'not-defined' is not a known group or service
    [64]

# any-target returns failure if no target exists:

    $ any-target @current not-defined || echo nope
    nope

# or success and contents of first matching target:

    $ any-target @current aService && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    1 items: aService
~~~

### jq Names

Sometimes it's useful to define a jq function based on a service or group name.  But jq names don't allow dots or dashes, like docker-compose names do.  So the `jq-name` method returns an escaped form of the target name that can be used as a jq function name:

~~~sh
    $ target svc2 jq-name && echo "$REPLY"
    svc2

    $ target --all jq-name && echo "$REPLY"
    _::dash::dash::all

    $ target foo.bar-baz jq-name && echo "$REPLY"
    foo::dot::bar::dash::baz

    $ target @current jq-name && echo "$REPLY"
    @current has no jq name
    [64]
~~~

