## Docker-Compose Integration

~~~shell
# Pre-define service names used in examples:

    $ SERVICES x y z foo bar
~~~

### `compose`

`compose` *args* is short for `docker-compose` *args*, except that the project directory and config files are set to the ones calculated by doco.  The contents of the `DOCO_OPTS` array are included before the supplied arguments:

~~~shell
    $ (DOCO_OPTS=(--tls -f foo); compose bar baz)
    docker-compose --tls -f foo bar baz
~~~

### Docker-Compose Subcommands

#### Default Targets

When a compose command accepts services, the services can come from:

* The `@current` service group
* A group called `--X-default`, where `X` is `DOCO_COMMAND` or one of the arguments to `compose-defaults`
* The `--default` group

The `compose-defaults` function, when given the name of the docker-compose command, returns success if at least one of the above groups exists.  `REPLY` is set to an array with the contents of the first such group that exists, or an empty array if none do.

~~~shell
    $ DOCO_COMMAND=GLOBAL trace any-target compose-defaults C1 C2 C3
    any-target @current --GLOBAL-default --C1-default --C2-default --C3-default --default
    [1]

    $ trace any-target compose-defaults LOCAL  # No DOCO_COMMAND
    any-target @current --LOCAL-default --default
    [1]

    $ DOCO_COMMAND= trace any-target compose-defaults LOCAL  # Empty DOCO_COMMAND
    any-target @current --LOCAL-default --default
    [1]

    $ DOCO_COMMAND=LOCAL trace any-target compose-defaults LOCAL  # Duplicate DOCO_COMMAND
    any-target @current --LOCAL-default --default
    [1]

~~~

#### Multi-Service Subcommands

Subcommands that accept multiple services get any services in the current service set appended to the command line.  (The service set is empty by default, causing docker-compose to apply commands to all services by default.)  If any targets have been explicitly specified, there must be at least one service in the current set.

~~~shell
# No explicit targets runs command without args

    $ compose-targeted some-command arg1 arg2
    docker-compose some-command arg1 arg2

# Explicit targets are added to args

    $ with-targets bar -- compose-targeted some-command arg1 arg2
    docker-compose some-command arg1 arg2 bar

# Explicit empty target produces error

    $ with-targets -- compose-targeted some-command arg1 arg2
    no services specified for some-command
    [64]

# ps, start, stop, etc. are all targeted commands

    $ with-targets bar -- trace compose-targeted eval 'doco ps; doco start; doco stop'
    compose-targeted ps
    docker-compose ps bar
    compose-targeted start
    docker-compose start bar
    compose-targeted stop
    docker-compose stop bar
~~~

#### Non-Service Subcommands

But docker-compose subcommands that *don't* take services as their sole positional arguments don't get services appended:

~~~shell
    $ doco config
    docker-compose config

    $ doco x config
    config cannot target specific services
    [64]
~~~

#### Single-Service Subcommands

Commands that take exactly *one* service (exec, run, and port) are modified to optionally accept a service or group alias specified before the command.  When there are no services in the service set, they take an explicit service positionally, just like with docker-compose.  Otherwise, the positional service argument is assumed to be missing, and the current service set is used as the target.  (Which requires that the service set contain exactly one service: no more, no less.)

Inserting the service argument at the appropriate place requires parsing the command's options, specifically those that take an argument.

~~~shell
# Single-service commands look up default targets w/compose-target

    $ trace compose-defaults doco x port --protocol udp 53
    compose-defaults port
    docker-compose port --protocol udp x 53

    $ trace compose-defaults doco x y z run -e FOO=bar foo
    compose-defaults run
    run cannot be used on multiple services
    [64]

    $ trace compose-defaults doco -- exec bash -c 'blah'  # bash != service, so this fails
    compose-defaults exec
    no services specified for exec
    [64]

    $ doco -- exec foo bash          # foo *is* a service, so this succeeds
    docker-compose exec foo bash
~~~

### Docker-Compose Options

  A few (like `--version` and `--help`) need to exit immediately, and a few others need special handling:

#### Global Options

Most docker-compose global options are simply accumulated and passed through to docker-compose.

~~~shell
    $ doco --verbose --tlskey blah ps
    docker-compose --verbose --tlskey=blah ps
~~~

#### Informational Options (--help, --version, etc.)

Some options pass directly the rest of the command line directly to docker-compose, ignoring any preceding options or prefix options:

~~~shell
    $ doco --help --verbose something blah
    docker-compose --help --verbose something blah

    $ doco -vh foo
    docker-compose -v -h foo
~~~

#### Project Options

The project name, file(s) and directory are controlled using doco's configuration or by doco itself, so doco explicitly rejects any docker-compose options that affect them:

~~~shell
    $ (doco -fx)
    doco does not support -f and --file.
    [64]

    $ (doco --verbose -p blah foo)
    You must use COMPOSE_PROJECT_NAME to set the project name.
    [64]

    $ (doco --project-directory=x blah)
    doco: --project-directory cannot be overridden
    [64]
~~~