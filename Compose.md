## Docker-Compose Integration

<!-- toc -->

- [Docker-Compose Subcommands](#docker-compose-subcommands)
  * [`compose`](#compose)
  * [Multi-Service Subcommands](#multi-service-subcommands)
  * [Non-Service Subcommands](#non-service-subcommands)
  * [Single-Service Subcommands](#single-service-subcommands)
- [Docker-Compose Options](#docker-compose-options)
  * [Generic Options](#generic-options)
  * [Aborting Options (--help, --version, etc.)](#aborting-options---help---version-etc)
  * [Project-level Options](#project-level-options)

<!-- tocstop -->

### Docker-Compose Subcommands

#### `compose`

`compose` *args* is short for `docker-compose` *args*, except that the project directory and config files are set to the ones calculated by doco.  The contents of the `DOCO_OPTS` array are included before the supplied arguments:

```shell
DOCO_OPTS=()
compose() { docker-compose ${DOCO_OPTS[@]+"${DOCO_OPTS[@]}"} "$@"; }
```

#### Multi-Service Subcommands

Unrecognized subcommands are first checked to see if they're a valid service or group.  If not, they're sent to docker-compose, with the current service set appended to the command line.  (The service set is empty by default, causing docker-compose to apply commands to all services by default.)

```shell
loco_exec() {
    if is-target-name "$1" && target "$1" exists; then
        with-targets @current "$1" -- ${2+doco "${@:2}"};
    else
        compose "$@" ${DOCO_SERVICES[@]+"${DOCO_SERVICES[@]}"};
    fi
}
```

#### Non-Service Subcommands

But docker-compose subcommands that *don't* take services as their sole positional arguments don't get services appended:

```shell
# Commands that don't accept a list of services
for cmd in bundle config down help scale version; do
    eval "doco.$cmd() { compose $cmd \"\$@\"; }"
done
```

#### Single-Service Subcommands

Commands that take exactly *one* service (exec, run, and port) are modified to run on multiple services or no services.  When there are no services in the service set, they take an explicit service positionally, just like with docker-compose.  Otherwise, the positional service argument is assumed to be missing, and the command is run once for each service in the current set.

Inserting the service argument at the appropriate place requires parsing the command's options, specifically those that take an argument.

```shell
doco.exec() { __compose_one exec '-e|--env|-u|--user|--index' "$@"; }
doco.run()  { __compose_one run  '-p|--publish|-v|--volume|-w|--workdir|-e|--env|-u|--user|--name|--entrypoint' "$@"; }
doco.port() { __compose_one port '--protocol|--index' "$@"; }

__compose_one() {
    local svc opts=^$2\$ argv=("$1"); shift

    # Parse the command line, skipping options' argument values
    while shift && (($#)) && [[ $1 == -* ]]; do
        # Treat '--' as end of options
        if [[ $1 == -- ]]; then shift; break; fi
        argv+=("$1"); if [[ $1 =~ $opts ]]; then shift; argv+=("$1"); fi
    done

    if have-services; then
        for svc in "${DOCO_SERVICES[@]}"; do compose "${argv[@]}" "$svc" "$@"; done
    else
        # XXX should check that $1 is a valid service
        compose "${argv[@]}" "$@"
    fi
}
```

### Docker-Compose Options

  A few (like `--version` and `--help`) need to exit immediately, and a few others need special handling:

#### Generic Options

Most docker-compose global options are added to the `DOCO_OPTS` array, where they will pass through to any subcommand.

```shell
docker-compose-options() {
    while (($#)); do
        # shellcheck disable=SC2089  # shellcheck hates metaprogramming
        printf -v REPLY 'doco.%s() { doco-opt %s doco "$@"; }' "$1" "$1"; eval "$REPLY"; shift
    done
}

docker-compose-optargs() {
    while (($#)); do
        eval "doco.$1() { doco-opt $1 doco-opt \"\$1\" doco \"\${@:2}\"; }"; shift
    done
}
doco-opt() { local DOCO_OPTS=(${DOCO_OPTS[@]+"${DOCO_OPTS[@]}"} "$1"); "${@:2}"; }
docker-compose-options --verbose --no-ansi --tls --tlsverify --skip-hostname-check
docker-compose-optargs -H --host --tlscacert --tlscert --tlskey
```

#### Aborting Options (--help, --version, etc.)

Some options pass directly the rest of the command line directly to docker-compose, ignoring any preceding options or prefix options:

```shell
docker-compose-immediate() {
    while (($#)); do eval "doco.$1() { docker-compose $1 \"\$@\"; }"; shift; done
}
docker-compose-immediate -h --help -v --version
```

#### Project-level Options

Project level options are fixed and can't be changed via the command line.

```shell
doco.-p() { loco_error "You must use COMPOSE_PROJECT_NAME to set the project name."; }
doco.-f() { loco_error "doco does not support -f and --file."; }
doco.--file() { doco -f "$@"; }
doco.--project-name() { doco -p "$@"; }
doco.--project-directory() { loco_error "doco: --project-directory cannot be overridden"; }
```

