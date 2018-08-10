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

A target's type is set using `declare-service` or `declare-group`.  When the target is initialized, an event is emitted.  Subsequent declarations have no effect, other than to verify that the target is of that type.

~~~shell
    $ event on create-service @_ echo "created service:"
    $ event on create-group @_ echo "created group:"

    $ target "aService" declare-service
    created service: aService aService

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

### Target Contents

Targets expand to an array of service names.  A service is a target that expands to exactly one service name: itself.  Groups, on the other hand, can expand to zero or more service names.  (And undeclared targets don't expand.)  You can fetch the names into the `REPLY` array using `get`, and check the count using `has-count`.

~~~shell
    $ target "aService" get && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    1 items: aService

    $ target "aGroup" get && echo "${#REPLY[@]} items"
    0 items

    $ target "nosuch" get || echo "nonexistent"
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
    $ event on "change-group" @_ echo "group changed:"

    $ target "aService" add "nosuch"
    aService is a service, but a group was expected
    [64]

    $ target "aGroup" add "nosuch"
    'nosuch' is not a known group or service
    [64]

    $ target "aGroup" add "aService"
    group changed: aGroup aService

    $ target "aGroup" get && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    1 items: aService

    $ target "aGroup" add "aService"   # second add does nothing
    $ target "aGroup" get && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    1 items: aService

    $ target "svc2" declare-service
    created service: svc2 svc2

    $ target "nosuch" add svc2 aService   # nosuch is now a group
    created group: nosuch
    group changed: nosuch svc2 aService

    $ target "nosuch" get && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    2 items: svc2 aService

    $ target "aGroup" add "nosuch"
    group changed: aGroup aService svc2
~~~

#### Resetting a Group

Groups can be `set` to a list of targets (i.e., existing services or groups), dropping whatever was there before and possibly issuing a change event.

~~~shell
    $ target "nosuch" set
    group changed: nosuch

    $ target "nosuch" get && echo "${#REPLY[@]} items:" "${REPLY[@]}"
    0 items:

    $ target "nosuch" set aService svc2
    group changed: nosuch aService svc2

    $ target "nosuch" set aService svc2   # no change = no event
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

The current target can be set for the duration of one command/function call using `with-targets` *targets...* `--` *command...*, during which the `DOCO_SERVICES` variable will be read-only, but still changeable using `with-targets`.  You can include `@current` in the target list, to merge the other targets with the current target set:

~~~shell
# with-targets expands groups, and issues change events for @current

    $ with-targets "nosuch" -- declare -p DOCO_SERVICES
    declare -ar DOCO_SERVICES=([0]="aService" [1]="svc2")

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

