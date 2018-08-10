## Docker-Compose Integration

~~~shell
# Pre-define service names used in examples:

    $ SERVICES x y z foo bar
~~~

### `compose`

`compose` *args* is short for `docker-compose` *args*, except that the project directory and config files are set to the ones calculated by doco.  The contents of the `DOCO_OPTS` array are included before the supplied arguments:

```shell
    $ (DOCO_OPTS=(--tls -f foo); compose bar baz)
    docker-compose --tls -f foo bar baz
```

### Docker-Compose Subcommands

#### Multi-Service Subcommands

Subcommands that accept multiple services get any services in the current service set appended to the command line.  (The service set is empty by default, causing docker-compose to apply commands to all services by default.)

```shell
    $ doco foo2
    'foo2' is not a recognized option, command, service, or group
    [64]
    $ (GROUP foo2 += bar; doco foo2 ps)
    docker-compose ps bar
    $ (GROUP foo2 += bar; doco foo2 bar)
    bar
```

#### Non-Service Subcommands

But docker-compose subcommands that *don't* take services as their sole positional arguments don't get services appended:

```shell
    $ declare -f doco.config | sed 's/ $//'
    doco.config ()
    {
        compose-untargeted config "$@"
    }
    $ doco config
    docker-compose config
```

#### Single-Service Subcommands

Commands that take exactly *one* service (exec, run, and port) are modified to optionally accept a service or group alias specified before the command.  When there are no services in the service set, they take an explicit service positionally, just like with docker-compose.  Otherwise, the positional service argument is assumed to be missing, and the current service set is used as the target.  (Which requires that the service set contain exactly one service: no more, no less.)

Inserting the service argument at the appropriate place requires parsing the command's options, specifically those that take an argument.

```shell
    $ doco x port --protocol udp 53
    docker-compose port --protocol udp x 53

    $ doco x y z run -e FOO=bar foo
    run cannot be used on multiple services
    [64]

    $ doco -- exec bash -c 'blah'    # bash is not a service, so this fails
    No service/group specified for exec
    [64]

    $ doco -- exec foo bash          # foo *is* a service, so this succeeds
    docker-compose exec foo bash
```

### Docker-Compose Options

  A few (like `--version` and `--help`) need to exit immediately, and a few others need special handling:

#### Global Options

Most docker-compose global options are simply accumulated and passed through to docker-compose.

```shell
    $ doco --verbose --tlskey blah ps
    docker-compose --verbose --tlskey=blah ps
```

#### Informational Options (--help, --version, etc.)

Some options pass directly the rest of the command line directly to docker-compose, ignoring any preceding options or prefix options:

```shell
    $ doco --help --verbose something blah
    docker-compose --help --verbose something blah

    $ doco -vh foo
    docker-compose -v -h foo
```

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