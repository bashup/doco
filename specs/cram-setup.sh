# Load functions and turn off error exit
source doco; set +e

# Ignore/null out all configuration for testing
loco_user_config() { :;}
loco_site_config() { :;}

# stub docker and docker-compose to output arguments
doco.--dry-run

# default empty compose file
echo '{"version": "2.1", "services": {"example1":{"image":"bash"}}}' >docker-compose.yml

# Initialize doco in-process when run without other initialization
doco() { unset -f doco; loco_main "$@"; }

# command to dump variables
doco.declare() { declare -p "$@"; }

# Run uninitialized doco in a subprocess, with -e re-enabled
run-doco() (
	set -e
	doco "$@"
)

# Trace execution of a specific function
trace() {
	local __trace_ret=0 __trace_old=$(declare -f "$1")
	eval "${__trace_old/$1/__trace_old_$1}";
	eval "$1(){ echo $1 \"\$@\"; __trace_old_$1 \"\$@\"; }"
	"${@:2}" || __trace_ret=$?
	eval "$__trace_old"
	return $__trace_ret
}