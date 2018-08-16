## Targets API (Services and Groups)

Targets are implemented as array variables named in the form `__doco_target_X`, where `X` is the encoded form of a docker-compatible container name.  (i.e. with `_`, `.` and `-` escaped)  The `@current` target, however, is stored in `DOCO_SERVICES`.

```shell
is-target-name() { [[ $1 && $1 != *[^-._A-Za-z0-9]* ]]; }

target() {
	local TARGET_NAME="$1" __mro__=(doco-target)
	if is-target-name "$1"; then
		local t=${1//_/_5f}; t=${t//./_2e}; t=${t//-/_2d}
		local TARGET_VAR=__doco_target_$t
	elif [[ $1 == @current ]]; then
		local TARGET_VAR=DOCO_SERVICES __mro__=(@current-target doco-target)
	else fail "Group or service name '$1' contains invalid characters" || return
	fi
	local -n TARGET="$TARGET_VAR"
	local TARGET_OLD=${TARGET[*]-}
	this "${@:2}"
}

fail() { echo "$1">&2; return "${2-64}"; }
this() {
	if (($#)); then
		local m; for m in "${__mro__[@]}"; do if fn-exists "$m::$1"; then break; fi; done
		"$m::$@"
	fi
}

```

### Target Types

A target is a service if it contains exactly one name: its own.  Any other target is a group, provided that the variable actually exists.  Once a target is declared to be one or the other, it can't be redeclared.  Creation events are issued when a target is initially declared.

```shell
array-exists() { declare -p "$1" >/dev/null 2>&1; }

doco-target::exists() { [[ ${TARGET+_} ]] || array-exists "$TARGET_VAR"; }
doco-target::is-service() { [[ ${TARGET[*]-} == "$TARGET_NAME" ]]; }
doco-target::is-group() { this exists && ! this is-service; }

doco-target::declare-service() {
	if ! this exists; then
		if project-is-finalized; then
			fail "$TARGET_NAME: services must be created before project spec is finalized" ||
			return
		fi
		this __create service "$TARGET_NAME"
		this readonly "$@"
	elif ! this is-service; then
		fail "$TARGET_NAME is a group, but a service was expected"
	fi
}

doco-target::declare-group() {
	if ! this exists; then
		this __create group
		this "$@"
	elif this is-service; then
		fail "$TARGET_NAME is a service, but a group was expected"
	fi
}

doco-target::__create() {
	TARGET=("${@:2}")
	event emit    "create $1" "$TARGET_NAME"
	event resolve "created $1 $TARGET_NAME" "$TARGET_NAME"
}

```

### Target Contents

```shell
doco-target::get() { REPLY=("${TARGET[@]}"); this "$@"; }
doco-target::has-count() { this get; eval "(( ${#REPLY[@]} ${1-} ))"; }

doco-target::readonly() { readonly "${TARGET_VAR}"; this "$@"; }

doco-target::add() { this set "$TARGET_NAME" "$@"; }
doco-target::set() {
	this declare-group || return
	all-targets "$@" || return
	TARGET=("${REPLY[@]}")
	if [[ ${TARGET[*]-} != "$TARGET_OLD" ]]; then
		event emit "change group" "$TARGET_NAME" "${TARGET[@]}"
	fi
}

doco-target::set-default() { this exists || this set "$@"; }

doco-target::foreach() {
	this get; for REPLY in "${REPLY[@]}"; do with-targets "$REPLY" -- "$@"; done
}
```

### The Current Target

The `@current` target is a read-only target that maps to the variable `DOCO_SERVICES` (the array of service names that will be passed to docker-compose).  The name `@current` is an intentionally invalid container name, so it can't collide with any actual groups or services, and it can't be turned into a service by adding its own name to it.  It can only ever be nonexistent or a group.

The current target can be set for the duration of a single command/function call using `with-targets` *names* `--` *command...*; you can include `@current` in the name list to add the other names to the existing target set.  `without-targets` is similar, except that it doesn't take any targets and makes `@current` not exist (instead of just being empty).

```shell
@current-target::set() { fail "@current group is read-only"; }
@current-target::declare-service() { fail "@current is a group, but a service was expected"; }
@current-target::declare-group() { :; }
@current-target::jq-name() { fail "@current has no jq name"; }

@current-target::exists() { [[ ${HAVE_SERVICES-} ]]; }
@current-target::get() {
	REPLY=(); [[ ! ${HAVE_SERVICES-} ]] || REPLY=("${TARGET[@]}"); this "$@"
}

with-targets() {
	local s=(); while (($#)) && [[ $1 != -- ]]; do s+=("$1"); shift; done
	all-targets "${s[@]}" || return
	__apply-targets = "${REPLY[@]}" -- "${@:2}"
}

without-targets() { __apply-targets '' -- "$@"; }

__apply-targets() {
	local HAVE_SERVICES=$1 DOCO_SERVICES DOCO_COMMAND
	DOCO_SERVICES=(); shift
	while (($#)) && [[ $1 != -- ]]; do DOCO_SERVICES+=("$1"); shift; done
	readonly DOCO_SERVICES
	"${@:2}"
}
```

### Target Set Operations

The `all-targets` and `any-target` functions return a `REPLY` array consisting of either the contents of all named targets, or the first named target that exists (even if empty).  For `all-targets`, all targets other than `@current` must exist or the result is a failure.  For `any-target`, the operation is a success unless none of the targets exist.

```shell
# set REPLY to merge of all given target names
all-targets() {
	local services=()
	while (($#)); do
		target "$1" get exists || [[ $1 == @current ]] ||
			fail "'$1' is not a known group or service" || return
		for REPLY in "${REPLY[@]}"; do
			[[ " ${services[*]-} " == *" $REPLY "* ]] || services+=("$REPLY")
		done
		shift
	done
	REPLY=("${services[@]}")
}

# set REPLY to contents of the first existing target
any-target() {
	for REPLY; do
		if target "$REPLY" get exists; then return ; fi
	done
	REPLY=(); false
}

```

### Misc. Utilities

```shell
doco-target::jq-name() {
	# jq function names can only have '_' or '::', not '-' or '.'
	set -- "${TARGET_NAME//-/::dash::}"; set -- "${1//./::dot::}"; set -- "${1/#::/_::}"
	REPLY=("${1//::::/::}")
}

__get-compose-env() {
	CLEAR_FILTERS
	APPLY '.services[$svc].environment // {} | to_entries' svc="$1"
	FILTER 'map( "\(.key)=\(.value / "$$" | map (. + "$") | add | .[:-1] | @sh)\n" )'
	FILTER '.+[""] | add | .[:-1]'
	RUN_JQ -r -j <<<"$COMPOSED_JSON"
}

doco-target::get-env() {
	this is-service || fail "$TARGET_NAME is not a service" || return
	# Fetch parsed env values from docker-compose config
	local name=${TARGET_VAR}__env; local -n vals=$name
	if ! array-exists "$name"; then
		compose-config && eval "vals=($(__get-compose-env "$TARGET_NAME"))" || return
	fi
	REPLY=("${vals[@]}")
}

doco-target::with-env() { this get-env || return; local "${REPLY[@]}"; "$@"; }
```

