## Docker-Compose Integration

<!-- toc -->

- [Docker-Compose Options](#docker-compose-options)
  * [Global Options](#global-options)
  * [Informational Options (--help, --version, etc.)](#informational-options---help---version-etc)
  * [Project Options](#project-options)
- [Docker-Compose Subcommands](#docker-compose-subcommands)
  * [Default Targets](#default-targets)
  * [Multi-Service Subcommands](#multi-service-subcommands)
  * [Non-Service Subcommands](#non-service-subcommands)
  * [Single-Service Subcommands](#single-service-subcommands)

<!-- tocstop -->

### Docker-Compose Options

#### Global Options

docker-compose supports various global options such as `--verbose` and `--host` and the like.  These options are accumulated using the `doco-opt` function, and then get passed to docker-compose via the `compose` function.

```shell
# doco opt OPTION CMD...  --> run CMD with OPTION added to project options
doco-opt() { local DOCO_OPTS=("${DOCO_OPTS[@]}" "$1"); "${@:2}"; }

# compose SUBCOMMAND... --> docker-compose DOCO_OPTS SUBCOMMAND...
compose() { docker-compose "${DOCO_OPTS[@]}" "$@"; }

# Global docker-compose flags
doco.--verbose()   { doco-opt --verbose   doco "$@"; }
doco.--no-ansi()   { doco-opt --no-ansi   doco "$@"; }
doco.--tls()       { doco-opt --tls       doco "$@"; }
doco.--tlsverify() { doco-opt --tlsverify doco "$@"; }

doco.--skip-hostname-check() { doco-opt --skip-hostname-check doco "$@"; }

# Options that take arguments
function doco.-H=()          { doco-opt -H="$1"          doco "${@:2}"; }
function doco.--host=()      { doco-opt --host="$1"      doco "${@:2}"; }
function doco.--tlscacert=() { doco-opt --tlscacert="$1" doco "${@:2}"; }
function doco.--tlscert=()   { doco-opt --tlscert="$1"   doco "${@:2}"; }
function doco.--tlskey=()    { doco-opt --tlskey="$1"    doco "${@:2}"; }

```

#### Informational Options (--help, --version, etc.)

Informational options cause the rest of the command line to be passed directly to docker-compose, ignoring any previously-given options:

```shell
# Informational options
doco.-h()        { docker-compose -h        "$@"; }
doco.-v()        { docker-compose -v        "$@"; }
doco.--help()    { docker-compose --help    "$@"; }
doco.--version() { docker-compose --version "$@"; }

```

#### Project Options

The project name, file(s) and directory are controlled using doco's configuration or by doco itself, so doco explicitly rejects any docker-compose options that affect them:

```shell
# Project options can't be set on the command line

function doco.--project-name=() {
	loco_error "You must use COMPOSE_PROJECT_NAME to set the project name."
}
function doco.--file=() {
	loco_error "doco does not support -f and --file."
}
function doco.--project-directory=() {
	loco_error "doco: --project-directory cannot be overridden"
}
function doco.-f=() { doco --file "$@"; }
function doco.-p=() { doco --project-name "$@"; }

```

### Docker-Compose Subcommands

Every docker-compose subcommand has a corresponding `doco` subcommand.   Generally speaking, docker-compose subcommands are either:

* Targetable (i.e., taking zero or more services in tail position),
* Non-targetable (i.e., always applying to all containers),
* Singular (taking exactly one service name after the options), or
* Informational (i.e., not applying to any service, but to docker-compose itself)

So each `doco` subcommand invokes `compose-targeted`, `compose-untargeted`, `compose-singular`, or plain `docker-compose`, appropriately:

```shell
# All supported docker-compose subcommands should be placed here
doco.build()   { compose-targeted   build   "$@"; }
doco.bundle()  { compose-untargeted bundle  "$@"; }
doco.config()  { compose-untargeted config  "$@"; }
doco.create()  { compose-targeted   up --no-start "$@"; }
doco.down()    { compose-untargeted down    "$@"; }
doco.events()  { compose-targeted   events  "$@"; }
doco.exec()    { compose-singular   exec \
	'-e|--env|-u|--user|--index' "$@"; }
doco.help()    { docker-compose     help    "$@"; }
doco.images()  { compose-targeted   images  "$@"; }
doco.kill()    { compose-targeted   kill    "$@"; }
doco.logs()    { compose-targeted   logs    "$@"; }
doco.pause()   { compose-targeted   pause   "$@"; }
doco.port()    { compose-singular   port \
	'--protocol|--index' "$@"; }
doco.ps()      { compose-targeted   ps      "$@"; }
doco.pull()    { compose-targeted   pull    "$@"; }
doco.push()    { compose-targeted   push    "$@"; }
doco.restart() { compose-targeted   restart "$@"; }
doco.rm()      { compose-targeted   rm      "$@"; }
doco.run()     { compose-singular   run \
	'-p|--publish|-v|--volume|-w|--workdir|-e|--env|-u|--user|--name|--entrypoint' "$@"; }
doco.scale()   { compose-untargeted scale   "$@"; }
doco.start()   { compose-targeted   start   "$@"; }
doco.stop()    { compose-targeted   stop    "$@"; }
doco.top()     { compose-targeted   top     "$@"; }
doco.unpause() { compose-targeted   unpause "$@"; }
doco.up()      { compose-targeted   up      "$@"; }
doco.version() { docker-compose     version "$@"; }

```

#### Default Targets

When a compose command accepts services, the services can come from:

* The `@current` service group
* A group called `--X-default`, where `X` is `DOCO_COMMAND` or one of the arguments to `compose-defaults`
* The `--default` group

The `compose-defaults` function, when given the name of the docker-compose command, returns success if at least one of the above groups exists.  `REPLY` is set to an array with the contents of the first such group that exists, or an empty array if none do.

```shell
compose-defaults() {
	set -- "${DOCO_COMMAND:-${1-}}" "$@"; [[ $1 && $1 != "${2-}" ]] || shift
	set -- "${@/#/--}"; any-target @current "${@/%/-default}" --default
}
```

#### Multi-Service Subcommands

Subcommands that accept multiple services get any services in the current service set appended to the command line.  (The service set is empty by default, causing docker-compose to apply commands to all services by default.)  If any targets have been explicitly specified, or a matching default group exists, there must be at least one service in the set.

```shell
# Commands that accept services
compose-targeted() {
	if compose-defaults "$1"; then
		# Either an explicit or default target was defined; make sure it's not empty
		quantify-services + "${DOCO_COMMAND:-$1}" "${REPLY[@]}" || return
	fi
	compose "$@" "${REPLY[@]}"
}
```

#### Non-Service Subcommands

But docker-compose subcommands that *don't* take services as their sole positional arguments don't get services appended:

```shell
# Commands that don't accept a list of services
compose-untargeted() {
	target @current has-count ==0 || fail "$1 cannot target specific services" || return
	compose "$@";
}
```

#### Single-Service Subcommands

Commands that take exactly *one* service (exec, run, and port) are modified to optionally accept a service or group alias specified before the command.  When no services are specified and no matching default group is defined, they take an explicit service positionally, just like with docker-compose.  The positional argument is then checked to make sure it's an actual service.

But if a service is specified or a matching default group is found, the positional service argument is assumed to be missing, and the matching target is used.  (The target must consist of exactly **one** service, however, or an error occurs.  Looping over multiple services or skipping execution altogether requires explicit use of the `foreach` command.)

Inserting the service argument at the appropriate place requires parsing the command's options, specifically those that take an argument.

```shell
compose-singular() {
	local svc cmd=$1 opts=^$2\$ argv=("$1"); shift

	# Parse the command line, skipping options' argument values
	while shift && (($#)) && [[ $1 == -* ]]; do
		# Treat '--' as end of options
		if [[ $1 == -- ]]; then shift; break; fi
		argv+=("$1"); if [[ $1 =~ $opts ]]; then shift; argv+=("$1"); fi
	done

	if ! compose-defaults "$cmd"; then
		# no current or default target, check command line for one and remove it
		if is-target-name "${1-}" && target "$1" get exists; then shift; fi
	fi

	quantify-services 1 "${DOCO_COMMAND:-$cmd}" "${REPLY[@]}" || return
	compose "${argv[@]}" "${REPLY[@]}" "$@"
}

```