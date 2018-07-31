## Command-line Interface

<!-- toc -->

- [doco options](#doco-options)
  * [`--` *[subcommand args...]*](#---subcommand-args)
  * [`--all` *subcommand args...*](#--all-subcommand-args)
  * [`--where` *jq-filter [subcommand args...]*](#--where-jq-filter-subcommand-args)
  * [`--with` *target [subcommand args...]*](#--with-target-subcommand-args)
  * [`--with-default` *target [subcommand args...]*](#--with-default-target-subcommand-args)
  * [`--require-services` *flag [subcommand args...]*](#--require-services-flag-subcommand-args)
- [doco subcommands](#doco-subcommands)
  * [`cmd` *flag subcommand...*](#cmd-flag-subcommand)
  * [`cp` *[opts] src dest*](#cp-opts-src-dest)
  * [`foreach` *subcmd arg...*](#foreach-subcmd-arg)
  * [`jq`](#jq)
  * [`sh`](#sh)

<!-- tocstop -->

### doco options

#### `--` *[subcommand args...]*

Reset the active service set to empty.  This can be used to ensure a command is invoked for all (or no) services, even if a service set was previously selected:

```shell
# Execute the rest of the command line with NO specified service(s)
doco.--()   { with-targets -- doco "$@"; }
```

#### `--all` *subcommand args...*

Update the service set to include *all* services, then invoke `doco` *subcommand args*.... Note that this is different from executing normal docker-compose commands with an empty (`--`) set, in that it explicitly lists all the services.

```shell
doco.--all() { doco --where true "$@"; }
```

#### `--where` *jq-filter [subcommand args...]*

Add services matching *jq-filter* to the current service set and invoke `doco` *subcommand args...*.  If the subcommand is omitted, outputs service names to stdout, one per line, returning a failure status of 1 and a message on stderr if no services match the given filter.  The filter is a jq expression that will be applied to the body of a service definition as it appears in the form *provided* to docker-compose.  (That is, values supplied by `extends` or variable interpolation are not available.)

```shell
doco.--where() {
    find-services "${@:1}"
    if (($#>1)); then
        with-targets "${REPLY[@]}" -- doco "${@:2}"   # run command on matching services
    elif ! ((${#REPLY[@]})); then
        echo "No matching services" >&2; return 1
    else
        printf '%s\n' "${REPLY[@]}"   # list matching services
    fi
}
```

#### `--with` *target [subcommand args...]*

The `--with`  option adds one or more services or groups to the current service set and then invokes  `doco` *subcommand args...*.  The *target* argument is either a single service or group name, or a string containing a space-separated list of service or group names.  `--with` can be given more than once.  (To reset the service set to empty, use `--`.)

```shell
# Execute the rest of the command line with specified service(s)
doco.--with() { mdsh-splitwords "$1"; with-targets @current "${REPLY[@]}" -- doco "${@:2}"; }
```

You don't normally need to use this option, because you can simply run `doco` *targets... subcommand...* in the first place.  It's really only useful in cases where you have service or group names that might conflict with other subcommand names, or need to store a set of group/service names in a non-array variable (e.g. in a `.env` file.)

#### `--with-default` *target [subcommand args...]*

Invoke `doco` *subcommand args...*, adding *target* to the current service set if the current set is empty.  *target* can be nonexistent or empty, so you may wish to follow this option with `--require-services` to verify the new count.

```shell
doco.--with-default() {
    if target @current has-count || ! target "$1" exists; then doco "${@:2}"
    else with-targets "$1" -- doco "${@:2}"; fi
}
```

#### `--require-services` *flag [subcommand args...]*

This is the command-line equivalent of calling `require-services` *flag subcommand* before invoking *subcommand args...*.  That is, it checks that the relevant number of services are present and exits with a usage error if not.  The *flag* argument can include a space and a command name to be used in place of *subcommand* in any error messages.

```shell
doco.--require-services() {
    [[ ${1:0:1} == [-+1.] ]] || loco_error "--require-services argument must begin with ., -, +, or 1"
    # shellcheck disable=SC2090  # bash 4.3 needs this syntax because "${x[@]:0}" doesn't play nice w/-u
    mdsh-splitwords "$1" && require-services ${REPLY[@]+"${REPLY[@]}"} "$2" && doco "${@:2}";
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
                project-name "$DOCO_SERVICES"; set -- "$REPLY$1" "${@:2}"
            else
                doco --with-default shell-default --require-services 1 cp ${opts[@]+"${opts[@]}"} "$@"; return $?
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

#### `foreach` *subcmd arg...*

Execute the given `doco` subcommand once for each service in the current service set, with the service set restricted to a single service for each subcommand.  This can be useful for explicit multiple (or zero) execution of a command that is otherwise restricted in how many times it can be executed.

```shell
doco.foreach() { foreach-service doco "$@"; }
```

#### `jq`

`doco jq` *args...* pipes the docker-compose configuration to `jq` *args...* as JSON.  Any functions defined via jqmd's facilities  (`DEFINES`, `IMPORTS`, `jq defs` blocks, `const` blocks, etc.) will be available to the given jq expression, if any.  If no expression is given, `.` is used.

```shell
doco.jq() { RUN_JQ "$@" <"$DOCO_CONFIG"; }
```

#### `sh`

`doco sh` *args...* executes `bash` *args* in the specified service's container.  If no service is specified, it defaults to the `cmd-default` target.  Multiple services are not allowed.

```shell
doco.sh() { doco cmd 1 exec bash "$@"; }
```

