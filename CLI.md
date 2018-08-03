## Command-line Interface

<!-- toc -->

- [Option Parsing and Command Dispatch](#option-parsing-and-command-dispatch)
  * [Options and Arguments](#options-and-arguments)
  * [Subcommands and Targets](#subcommands-and-targets)
- [doco options](#doco-options)
  * [`--`](#--)
  * [`--all`](#--all)
  * [`--where=`*jq-filter*](#--wherejq-filter)
  * [`--with=`*target*](#--withtarget)
  * [`--with-default=`*target*](#--with-defaulttarget)
  * [`--require-services=`*flag [subcommand args...]*](#--require-servicesflag-subcommand-args)
- [doco subcommands](#doco-subcommands)
  * [`cmd` *flag subcommand...*](#cmd-flag-subcommand)
  * [`cp` *[opts] src dest*](#cp-opts-src-dest)
  * [`foreach` *subcommand...*](#foreach-subcommand)
  * [`jq`](#jq)
  * [`sh`](#sh)

<!-- tocstop -->

### Option Parsing and Command Dispatch

doco parses options and commands with support for GNU-like short and long options.  Multiple usage patterns are supported, including breaking strings like `-xyzabc` into `-x -y -z=abc` (if `-z` takes an argument and `-x` and `-y` don't).  Option values can use explicit `=` (e.g. `--foo=bar`, `-z=q`), separate arguments (`--foo bar`, `-z q`), or even optional arguments (where `=` invokes a different code path than the standalone option).

```shell
loco_do() {
	[[ "${1-}" ]] || loco_usage   # No non-empty command given, exit w/usage
	case $1 in
		--*=*)    doco-optarg  "$@" ;;  # --[option]=value
		--*)      doco-option  "$@" ;;  # --[option]
		-[^=]=*)  doco-optarg  "$@" ;;  # -a=bcd
		-[^=]?*)  doco-options "$@" ;;  # -abcd
		-?)       doco-option  "$@" ;;  # -x
		*)        doco-other   "$@" ;;  # commands, services, and groups
	esac
}
```

#### Options and Arguments

Options are defined using functions whose names begin with `doco.`, followed by `-` or `--`, the option name, and optionally an `=`.  If the option name ends with an `=`, it requires an argument, which can be supplied as a separate argument (e.g. `--foo bar` or `-f bar`), or as part of the same argument (e.g. `--foo=bar` or `-f=bar` or `-fbar`).  If a given option has functions for both `=` and non-`=`  variants, the non-`=` variant will be called for the standalone option (`--foo` or `-f`).

```shell
doco-options() {
	if fn-exists "doco.${1:0:2}="; then
		"doco.${1:0:2}=" "${1:2}" "${@:2}"  # -a= bcd ...
	elif fn-exists "doco.${1:0:2}"; then
		"doco.${1:0:2}" "-${1:2}" "${@:2}"  # -a -bcd ...
	else doco-other "$@"   # maybe -abcd is a command, group, or service?
	fi
}

doco-option() {
	if fn-exists "doco.$1"; then "doco.$@"
	elif fn-exists "doco.$1="; then
		if (($#>1)); then "doco.$1=" "${@:2}"
		else fail "$1 requires an argument"
		fi
	else doco-other "$@"   # maybe --longopt is a group or service?
	fi
}

doco-optarg() {
	if fn-exists "doco.${1%%=*}="; then
		"doco.${1%%=*}=" "${1#*=}" "${@:2}"
	elif fn-exists "doco.${1%%=*}"; then
		fail "${1%%=*} does not accept values"
	else doco-other "$@"   # maybe it's a command/group/service?
	fi
}
```

#### Subcommands and Targets

If a name passed to doco on the command line isn't recognized as an option, it's checked for a subcommand function (`doco.X`, where `X` is the possible subcommand).  If that doesn't work, we fall  back to see if `X` is a service or group defined by the configuration.  If so, the services it targets are added to the "current target" set, and command parsing continues with the next argument.  So, if `a` and `b` are services or groups, then `doco a b ps` is roughly equivalent to `doco ps a b`.  (Except that if say, `b` is a group containing `c` and `d`, it'd be equivalent to `doco ps a c d` instead.)

```shell
doco-other() {
	if fn-exists "doco.$1"; then "doco.$@"
	elif is-target-name "$1" && target "$1" exists; then
		with-targets @current "$1" -- ${2+doco "${@:2}"}
	else fail "'$1' is not a recognized option, command, service, or group"
	fi
}
```

### doco options

#### `--`

Explicitly set the active service set to empty and disable doco's support for default command targets for the remainder of the command line.

If no services are explicitly added after this point in the command line, then docker-compose subcommands will have their default behavior and argument parsing.  (That is, commands that take multiple services will apply to all services unless a service is listed, and commands that apply to a single service will require it as the first post-option argument.)

```shell
# Execute the rest of the command line with NO specified service(s)
doco.--()   { with-targets -- doco "$@"; }
```

#### `--all`

Update the service set to include *all* services for the remainder of the command line (unless reset again with `--`). Note that this is different from executing normal docker-compose commands with an explicitly empty set (e.g. using  `--` or an empty group), in that it explicitly passes along all the service names.  (Among other things, this lets you use commands like `foreach`to run single-target commands (e.g. `exec`) against each service.)

```shell
doco.--all() { doco --where true "$@"; }
```

#### `--dry-run`

Output any docker or docker-compose commands that would be issued, instead of actually running them.

```shell
doco.--dry-run() {
	docker() { printf -v REPLY ' %q' "docker" "$@"; echo "${REPLY# }"; } >&2
	docker-compose() { printf -v REPLY ' %q' "docker-compose" "$@"; echo "${REPLY# }"; } >&2
	((! $#)) || { doco "$@"; unset -f docker docker-compose; }
}
```

#### `--where=`*jq-filter*

Add services matching *jq-filter* to the current service set for the remainder of the command line.  If this is the last thing on the command line, outputs service names to stdout, one per line, returning a failure status of 1 and a message on stderr if no services match the given filter.  The filter is a jq expression that will be applied to the body of a service definition as it appears in the form *provided* to docker-compose.  (That is, values supplied by compose via `extends` or variable interpolation are not available.)

```shell
function doco.--where=() {
    find-services "${@:1}"
    if (($#>1)); then
        with-targets @current "${REPLY[@]}" -- doco "${@:2}"   # run command on matching services
    elif ! ((${#REPLY[@]})); then
        echo "No matching services" >&2; return 1
    else
        printf '%s\n' "${REPLY[@]}"   # list matching services
    fi
}
```

#### `--with=`*target*

The `--with`  option adds one or more services or groups to the current service set for the remainder of the command line, unless reset with `--`.  The *target* argument is either a single service or group name, or a string containing a space-separated list of service or group names.  `--with` can be given more than once.  To reset the service set to empty, use `--`.

```shell
# Execute the rest of the command line with specified service(s)
function doco.--with=() {
	mdsh-splitwords "$1"; with-targets @current "${REPLY[@]}" -- doco "${@:2}"
}
```

Note that you don't normally need to use this option, because you can simply run `doco` *targets... commands...* in the first place.  It's really only useful in cases where you have service or group names that might conflict with other subcommand names, or need to use a set of group/service names stored in a non-array variable (e.g. in a `.env` file)

#### `--with-default=`*target*

Invoke `doco` *subcommand args...*, adding *target* to the current service set if the current set is empty.  Note that  *target* could still be nonexistent or empty, so you may wish to follow this option with `--require-services` to verify the new count.

```shell
function doco.--with-default=() {
    if target @current has-count || ! target "$1" exists; then doco "${@:2}"
    else with-targets "$1" -- doco "${@:2}"; fi
}
```

#### `--require-services=`*flag [subcommand args...]*

This is the command-line equivalent of calling `require-services` *flag subcommand* before invoking *subcommand args...*.  That is, it checks that the relevant number of services are present and exits with a usage error if not.  The *flag* argument can include a space and a command name to be used in place of *subcommand* in any error messages.

```shell
function doco.--require-services=() {
    [[ ${1:0:1} == [-+1.] ]] || loco_error "--require-services argument must begin with ., -, +, or 1"
    mdsh-splitwords "$1" && require-services "${REPLY[@]}" "${2-}" && doco "${@:2}";
}
```

### doco subcommands

#### `cmd` *flag subcommand...*

Shorthand for `--with-default cmd-default --require-services` *flag subcommand...*.  That is, if the current service set is empty, it defaults to the `cmd-default` target, if defined.  The number of services is then verified with `--require-services` before executing *subcommand*.  This makes it easy to define new subcommands that work on a default container or group of containers.  (For example, the `doco sh` command is defined as `doco cmd 1 exec bash "$@"` -- i.e., it runs on exactly one service, defaulting to the `cmd-default` group.)

```shell
doco.cmd() { doco --with-default cmd-default --require-services "$@"; }
```

#### `cp` *[opts] src dest*

Copy a file in or out of a service container.  Functions the same as `docker cp`, except that instead of using a container name as a prefix, you can use either a service name or an empty string (meaning, the currently-selected service).  So, e.g. `doco cp :/foo bar` copies `/foo` from the current service to `bar`, while `doco cp baz spam:/thing` copies `baz` to `/thing` inside the `spam` service's first container.  If no service is selected and no service name is given, the `shell-default` target is tried.

```shell
doco.cp() {
    local opts=() seen=''
    while (($#)); do
        case "$1" in
        -a|--archive|-L|--follow-link) opts+=("$1") ;;
        --help|-h) docker help cp || true; return ;;
        -*) loco_error "Unrecognized option $1; see 'docker help cp'" ;;
        *) break ;;
        esac
        shift
    done
    (($# == 2)) || loco_error "cp requires two non-option arguments (src and dest)"
    while (($#)); do
        if [[ $1 == *:* ]]; then
            [[ ! "$seen" ]] || loco_error "cp: only one argument may contain a :"
            seen=yes
            if [[ "${1%%:*}" ]]; then
                project-name "${1%%:*}"; set -- "$REPLY:${1#*:}" "${@:2}"
            elif have-services '==1'; then
                project-name "${DOCO_SERVICES[0]}"; set -- "$REPLY$1" "${@:2}"
            else
                doco --with-default=shell-default --require-services=1 cp "${opts[@]}" "$@"
                return
            fi
        elif [[ $1 != /* && $1 != - ]]; then
            # make paths relative to original run directory
            set -- "$LOCO_PWD/$1" "${@:2}";
        fi
        opts+=("$1"); shift
    done
    [[ "$seen" ]] || loco_error "cp: either source or destination must contain a :"
    docker cp ${opts[@]+"${opts[@]}"}
}
```

#### `foreach` *subcommand...*

Execute the given `doco` subcommand once for each service in the current service set, with the service set restricted to a single service for each subcommand invocation.  This can be useful for explicit multiple (or zero) execution of a command that is otherwise restricted in how many times it can be executed.

```shell
doco.foreach() { foreach-service doco "$@"; }
```

#### `jq`

`doco jq` *args...* pipes the docker-compose configuration to `jq` *args...* as JSON.   The filter is a jq expression that will be applied to the configuration as it appears in the form *provided* to docker-compose.  (That is, values supplied by compose via `extends` or variable interpolation will not be visible.)

Any functions defined via jqmd's facilities  (`DEFINES`, `IMPORTS`, `jq defs` blocks, `const` blocks, etc.) will be available to the given jq expression, if any.  If no expression is given, `.` is used.

```shell
doco.jq() { RUN_JQ "$@" <"$DOCO_CONFIG"; }
```

#### `sh`

`doco sh` *args...* executes `bash` *args* in the specified service's container.  If no service is specified, it defaults to the `cmd-default` target.  Multiple services are not allowed, unless you preface `sh` with `foreach`.

```shell
doco.sh() { doco cmd 1 exec bash "$@"; }
```

