## Built-in Commands

~~~shell
# Pre-define service names used in examples:

    $ SERVICES bravo a b x y alfa foxtrot
~~~

#### The Null Command

If no arguments remain on the command line, `doco` outputs the current target service list, one item per line, and returns success.  However, if there are no arguments *left* because none were ever *given*, a usage message is output:

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

#### Command/Target Lookup

~~~shell
# Something that's not a command or existing target gets an error:

    $ doco foo2
    'foo2' is not a recognized option, command, service, or group
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

#### `cmd` *"quantifier[ cmd...]" subcommand...*

Verify the number of services in the current target, after applying defaults if the current service set is undefined.  Defaults are looked up for the current command, any explicitly specified *cmd* words included in `$1`, *subcommand*, and the global default target.  If the verification succeeds, `doco` *subcommand...* is run with an explicit service set matching the first default group found (or with the same service set).

The first argument after `cmd` must begin with a quantifier suitable for use with `quantify-services`, and may optionally include whitespace-separated command names.  If given, these names will be treated as commands whose defaults should be searched.  (The exact lookup order for defaults is `LOCO_COMMAND`, followed by any supplied *cmd* words, followed by *subcommand*, followed by `--default`.)

~~~shell
# Must have arg

    $ doco cmd
    service quantifier must be ., -, +, or 1
    [64]

# Validate current services

    $ trace any-target doco cmd 1
    any-target @current --default
    no services specified for the current command
    [64]

# Targets are looked up for DOCO_CMD, named commands, and the trailing command

    $ DOCO_COMMAND=X trace any-target doco cmd "1 foo bar" ps
    any-target @current --X-default --foo-default --bar-default --ps-default --default
    no services specified for foo
    [64]

# Subcommand gets picked up if no current command

    $ doco cmd 1 test
    no services specified for test
    [64]

    $ doco.some-command() { doco cmd 1 "$@"; }
    $ doco some-command
    no services specified for some-command
    [64]

    $ GROUP --some-command-default := foxtrot
    $ doco some-command exec testme
    docker-compose exec foxtrot testme

    $ (GROUP --default := foxtrot; trace compose-defaults doco cmd "1 foo" exec testme)
    compose-defaults foo exec
    compose-defaults exec
    docker-compose exec foxtrot testme
~~~

#### `cp` *[opts] src dest*

Copy a file in or out of a service container.  Functions the same as `docker cp`, except that instead of using a container name as a prefix, you can use either a service name or an empty string (meaning, the currently-selected service).  So, e.g. `doco cp :/foo bar` copies `/foo` from the current service to `bar`, while `doco cp baz spam:/thing` copies `baz` to `/thing` inside the `spam` service's first container.  If no service is selected and no service name is given, the `--cp-default`, `--sh-default`, `--exec-default`, and `--default` targets are tried.

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

    $ (GROUP --sh-default := bravo; trace compose-defaults doco cp :x y)
    compose-defaults cp sh exec
    docker cp clicommandscrammd_bravo_1:x /*/CLI-Commands.cram.md/y (glob)

    $ (GROUP --exec-default := bravo; doco cp :x y)
    docker cp clicommandscrammd_bravo_1:x /*/CLI-Commands.cram.md/y (glob)

    $ LOCO_PWD=$PWD/t doco bravo cp y :x
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

`doco jq` *args...* pipes the docker-compose configuration to `jq` *args...* as JSON.   The JSON is the contents of the configuration as it appears in the form *provided* to docker-compose.  (That is, values supplied by compose via `extends` or variable interpolation will not be visible.)

Any functions defined via jqmd's facilities  (`DEFINES`, `IMPORTS`, `jq defs` blocks, `const` blocks, etc.) will be available to the given jq expression, if any.  If no expression is given, `.` is used.

If stdout is a TTY, the output is paged (using `$DOCO_PAGER` or `less -FRX`) and colorized by jq.

~~~shell
    $ doco jq .version
    "2.1"
~~~

#### `jqc`

`doco jqc` *args...* pipes the *complete* docker-compose configuration to `jq` *args...* as JSON.  The JSON is generated by converting the output of `docker-compose config` from YAML to JSON, making this command slower than `doco jq` with the same arguments, but the effects of `extends`, variable interpolation, etc. will be available.

If stdout is a TTY, the output is paged (using `$DOCO_PAGER` or `less -FRX`) and colorized by jq.

~~~shell
    $ compose-config() { echo "calling compose-config" >&2; }
    $ COMPOSED_JSON='{"services": {"svc2": {"environment": { "X": "y$$z", "Q": "r\ns" }}}}'

    $ doco jqc .services.svc2.environment.Q
    calling compose-config
    "r\ns"
~~~

#### `sh`

`doco sh` *args...* executes `bash` *args* in the specified service's container.  Multiple services are not allowed, unless you preface `sh` with `foreach`.

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

    $ GROUP --exec-default := foxtrot; doco sh -c 'echo foo'
    docker-compose exec foxtrot bash -c echo\ foo

    $ GROUP --sh-default := ; doco sh -c 'echo foo'
    no services specified for sh
    [64]
~~~

#### `tag` *[tag]*

Tag the current service's `image` with *tag*.  If no *tag* is given, outputs the service's `image`.

If *tag* contains a `:`, it is passed to the `docker tag` command as-is.  Otherwise, if it contains a `/`, `:latest` will be added to the end of it.  If it contains neither a `:` nor a `/`, it is appended to the base image with a `:`.

That is, if a service `foo` has an `image` of `foo/bar:1.2` then:

* `doco foo tag bar/baz:bing` will tag the image as `bar/baz:bing`
* `doco foo tag bar/baz` will tag the image as `bar/baz:latest`
* `doco foo tag latest` will tag the image as `foo/bar:latest`
* `doco foo tag baz` will tag the image as `foo/bar:baz`

Exactly one service must be selected, either explicitly or via the `--tag-default` or `--default` targets.  The service must have an `image` key, or the command will fail.

~~~sh
    $ doco example1 tag
    bash

    $ doco example1 tag bing/bang:boom
    docker tag bash bing/bang:boom

    $ doco example1 tag bing/bang
    docker tag bash bing/bang:latest

    $ doco example1 tag boom
    docker tag bash bash:boom
~~~
