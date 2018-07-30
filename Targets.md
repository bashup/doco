## Targets API (Services and Groups)

Targets are implemented as array variables named in the form `__doco_target_X`, where `X` is the encoded form of a docker-compatible container name.  (i.e. with `_`, `.` and `-` escaped)

```shell
is-target-name() { [[ $1 && $1 != *[^-._A-Za-z0-9]* ]]; }

target() {
	is-target-name "$1" ||
		fail "Group or service name '$1' contains invalid characters" || return
	local TARGET_NAME="$1" TARGET_VAR=${1//_/_5f}
	TARGET_VAR=${TARGET_VAR//./_2e}; TARGET_VAR=__doco_target_${TARGET_VAR//-/_2d}
	local -n TARGET="$TARGET_VAR"
	local TARGET_OLD=${TARGET[*]-} __mro__=(doco-target); this "${@:2}"
}

fail() { echo "$1">&2; return "${2-64}"; }
this() { ! (($#)) || "${__mro__[0]}::$@"; } # XXX
```

### Target Types

A target is a service if it contains exactly one name: its own.  Any other target is a group, provided that the variable actually exists.  Once a target is declared to be one or the other, it can't be redeclared.  Creation events are issued when a target is initially declared.

```shell
doco-target::is-service() { [[ ${TARGET[*]-} == "$TARGET_NAME" ]]; }
doco-target::is-group() { this exists && ! this is-service; }
doco-target::exists() { [[ ${TARGET+_} ]] || declare -p "$TARGET_VAR" >/dev/null 2>&1; }

doco-target::declare-service() {
	if ! this exists; then
		TARGET=("$TARGET_NAME"); event emit "create-service" "$TARGET_NAME" "$TARGET_NAME"
		this "$@"
	elif ! this is-service; then
		fail "$TARGET_NAME is a group, but a service was expected"
	fi
}

doco-target::declare-group() {
	if ! this exists; then
		TARGET=(); event emit "create-group" "$TARGET_NAME"
		this "$@"
	elif this is-service; then
		fail "$TARGET_NAME is a service, but a group was expected"
	fi
}
```

### Target Contents

```shell
doco-target::get() { REPLY=("${TARGET[@]}"); this "${1-exists}" "${@:2}"; }
doco-target::has-count() { REPLY=("${TARGET[@]}"); eval "(( ${#REPLY[@]} ${1-} ))"; }

doco-target::add() {
	this declare-group || return
	while (($#)); do
		target "$1" get || fail "'$1' is not a known group or service" || return
		for REPLY in "${REPLY[@]}"; do
			[[ " ${TARGET[*]-} " == *" $REPLY "* ]] || TARGET+=("$REPLY")
		done
		shift
	done
	if [[ ${TARGET[*]-} != "$TARGET_OLD" ]]; then
		event emit "change-group" "$TARGET_NAME" "${TARGET[@]}"
	fi
}

doco-target::set() {
	this declare-group || return; TARGET=(); this add "$@"
}
```

### The Current Target

The current target maps to the variable `DOCO_SERVICES` -- the array of names that will be passed to docker-compose.  It has the internal name of `@current`, which is an intentionally invalid target name, so it can't collide with any actual groups or services, and so that it can't be turned into a service by adding its own name to it.  It can only ever be nonexistent or a group.  The current target can be added to for the duration of a command/function call using `target` *name* `call` *command...*, or multiple targets can be added using `with-targets` *names* `--` *command...*.

```shell
current-target() {
	local TARGET_NAME="@current" TARGET_VAR=DOCO_SERVICES; local -n TARGET="$TARGET_VAR"
	local TARGET_OLD=${TARGET[*]-} __mro__=(doco-target); this "$@"
}

doco-target::call() {
	if [[ $TARGET_NAME == "@current" ]]; then "$@"
	else with-targets "$TARGET_NAME" -- "$@"; fi
}

with-targets() {
	REPLY=(); while (($#)) && [[ $1 != -- ]]; do REPLY+=("$1"); shift; done
	local DOCO_SERVICES=("${DOCO_SERVICES[@]}")
	current-target add "${REPLY[@]}"; "${@:2}"
}
```

