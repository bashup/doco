## Built-in Commands

~~~shell
# Pre-define service names used in examples:

    $ SERVICES bravo a b x y alfa foxtrot
~~~

#### The Null Command

If no arguments are given, `doco` outputs the current target service list, one item per line, and returns success.  If there is no current target, however, a usage message is output:

~~~shell
    $ doco example1  # explicit services/groups, map to output names
    example1

    $ doco --all  # output current target set
    example1

    $ doco --  # empty target set; outputs nothing

    $ (command doco)   # no set defined = usage + error
    Usage: doco command args...
    [64]
~~~

#### Command Name Tracing

The name of the current command is tracked in `DOCO_COMMAND`; it's set to the name of the first `doco` subcommand run since the most recent setting of targets (other than `--with-default`).  (This allows error messages to know what command the arguments were passed to.)

~~~shell
# First command is 'declare'

    $ doco declare DOCO_COMMAND
    declare -- DOCO_COMMAND="declare"

    $ doco example1 declare DOCO_COMMAND
    declare -- DOCO_COMMAND="declare"

# First command is 'mycmd'

    $ doco.mycmd() { doco declare "$@"; }

    $ doco mycmd DOCO_COMMAND
    declare -- DOCO_COMMAND="mycmd"

    $ doco example1 mycmd DOCO_COMMAND
    declare -- DOCO_COMMAND="mycmd"

# First command since change in targets is 'declare'

    $ doco.mycmd() { doco example1 declare "$@"; }

    $ doco mycmd DOCO_COMMAND
    declare -- DOCO_COMMAND="declare"

# First command since non-default change in targets is 'mycmd'

    $ doco.mycmd() { doco --with-default example1 declare "$@"; }

    $ doco mycmd DOCO_COMMAND
    declare -- DOCO_COMMAND="mycmd"
~~~



#### `cmd` *flag subcommand...*

Shorthand for `--with-default cmd-default --require-services` *flag subcommand...*.  That is, if the current service set is empty, it defaults to the `cmd-default` target, if defined.  The number of services is then verified with `--require-services` before executing *subcommand*.  This makes it easy to define new subcommands that work on a default container or group of containers.  (For example, the `doco sh` command is defined as `doco cmd 1 exec bash "$@"` -- i.e., it runs on exactly one service, defaulting to the `cmd-default` group.)

~~~shell
    $ doco cmd 1 test
    no services specified for test
    [64]

    $ (GROUP cmd-default := foxtrot; doco cmd 1 exec testme)
    docker-compose exec foxtrot testme
~~~

#### `cp` *[opts] src dest*

Copy a file in or out of a service container.  Functions the same as `docker cp`, except that instead of using a container name as a prefix, you can use either a service name or an empty string (meaning, the currently-selected service).  So, e.g. `doco cp :/foo bar` copies `/foo` from the current service to `bar`, while `doco cp baz spam:/thing` copies `baz` to `/thing` inside the `spam` service's first container.  If no service is selected and no service name is given, the `shell-default` target is tried.

~~~shell
# Nominal cases

    $ doco cp -h
    docker help cp

    $ doco cp -L /foo bar:/baz
    docker cp -L /foo clicommandscrammd_bar_1:/baz

    $ doco cp bar:/spam -
    docker cp clicommandscrammd_bar_1:/spam -

    $ doco cp :x y
    no services specified for cp
    [64]

    $ GROUP shell-default := bravo; doco cp :x y
    docker cp clicommandscrammd_bravo_1:x /*/CLI-Commands.cram.md/y (glob)

    $ GROUP shell-default := bravo; LOCO_PWD=$PWD/t doco bravo cp y :x
    docker cp /*/CLI-Commands.cram.md/t/y clicommandscrammd_bravo_1:x (glob)

# Bad usages

    $ doco a b cp foo :bar
    cp cannot be used on multiple services
    [64]

    $ doco cp --nosuch
    Unrecognized option --nosuch; see 'docker help cp'
    [64]

    $ doco cp foo bar baz
    cp requires two non-option arguments (src and dest)
    [64]

    $ doco cp foo bar
    cp: either source or destination must contain a :
    [64]

    $ doco cp foo:bar baz:spam
    cp: only one argument may contain a :
    [64]
~~~

#### `foreach` *subcommand...*

Execute the given `doco` subcommand once for each service in the current service set, with the service set restricted to a single service for each subcommand invocation.  This can be useful for explicit multiple (or zero) execution of a command that is otherwise restricted in how many times it can be executed.

~~~shell
    $ doco x y foreach ps
    docker-compose ps x
    docker-compose ps y

    $ doco -- foreach ps
~~~

#### `jq`

`doco jq` *args...* pipes the docker-compose configuration to `jq` *args...* as JSON.   The filter is a jq expression that will be applied to the configuration as it appears in the form *provided* to docker-compose.  (That is, values supplied by compose via `extends` or variable interpolation will not be visible.)

Any functions defined via jqmd's facilities  (`DEFINES`, `IMPORTS`, `jq defs` blocks, `const` blocks, etc.) will be available to the given jq expression, if any.  If no expression is given, `.` is used.

~~~shell
    $ doco jq .version
    "2.1"
~~~

#### `sh`

`doco sh` *args...* executes `bash` *args* in the specified service's container.  If no service is specified, it defaults to the `cmd-default` target.  Multiple services are not allowed, unless you preface `sh` with `foreach`.

~~~shell
    $ doco sh
    no services specified for sh
    [64]

    $ GROUP tango := alfa foxtrot
    $ doco tango sh
    sh cannot be used on multiple services
    [64]

    $ doco alfa sh
    docker-compose exec alfa bash

    $ GROUP cmd-default += foxtrot; doco sh -c 'echo foo'
    docker-compose exec foxtrot bash -c echo\ foo

    $ GROUP cmd-default := ; doco sh -c 'echo foo'
    no services specified for sh
    [64]
~~~
