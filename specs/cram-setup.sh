# Load functions and turn off error exit
source doco; set +e

# Ignore/null out all configuration for testing
loco_user_config() { :;}
loco_site_config() { :;}

# stub docker and docker-compose to output arguments
docker() {
	printf -v REPLY ' %q' "docker" "$@"; echo "${REPLY# }"
} >&2;

docker-compose() {
	printf -v REPLY ' %q' "docker-compose" "$@"; echo "${REPLY# }"
} >&2;

# define a no-op command
doco.no-op() { :;}

# and a default empty compose file
echo '{"version": "2.1", "services": {"example1":{}}}' >docker-compose.yml

# Initialize doco in-process when run without other initialization
doco() { unset -f doco; loco_main "$@"; }

