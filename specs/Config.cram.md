## Configuration

~~~shell
# Use README.md for default config
    $ cp $TESTDIR/../README.md readme.doco.md
~~~

### File and Function Names

Configuration is loaded using loco.  Specifically, by searching for `*.doco.md`, `.doco`, or `docker-compose.y{a,}ml` above the current directory.  The loco script name is hardcoded to `doco`, so even if it's run via a symlink the function names for custom subcommands will still be `doco.subcommand-name`.  User and site-level configs are also defined.

~~~shell
    $ run-doco declare LOCO_FILE LOCO_NAME LOCO_USER_CONFIG LOCO_SITE_CONFIG
    declare -a LOCO_FILE=([0]="?*[-.]doco.md" [1]=".doco" [2]="docker-compose.yml" [3]="docker-compose.yaml")
    declare -- LOCO_NAME="doco"
    declare -- LOCO_USER_CONFIG="/*/.config/doco" (glob)
    declare -- LOCO_SITE_CONFIG="/etc/doco/config"
~~~

### Project-Level Configuration

Project configuration is loaded into `$LOCO_ROOT/.doco-cache.json` as JSON text, and `COMPOSE_FILE` is set to point to that file, for use by docker-compose.  (`COMPOSE_FILE` also gets the name of the `docker-compose.override` file, if any, with  `COMPOSE_PATH_SEPARATOR` set to a newline.)

If the configuration is a `*doco.md` file, it's entirely responsible for generating the configuration, and any standard `docker-compose{.override,}.y{a,}ml` file(s) are ignored.  Otherwise, the main YAML config is read before sourcing `.doco`, and the standard files are used to source the configuration.  (Note: the `.override` file, if any, is passed to docker-compose, but is *not* included in any jq filters or queries done by doco.)

Either way, service targets are created for any services that don't already have them.  (Minus any services that are only defined in an `.override`.)

~~~shell
# COMPOSE_FILE is exported, pointing to the cache; DOCO_CONFIG is the same,
# and COMPOSE_PATH_SEPARATOR is a line break
    $ run-doco declare COMPOSE_FILE DOCO_CONFIG COMPOSE_PATH_SEPARATOR
    declare -x COMPOSE_FILE="/*/Config.cram.md/.doco-cache.json" (glob)
    declare -- DOCO_CONFIG="/*/Config.cram.md/.doco-cache.json" (glob)
    declare -x COMPOSE_PATH_SEPARATOR="
    "

# .cache has same timestamp as what it's built from; and is rebuilt if it changes
    $ [[ readme.doco.md -ot .doco-cache.sh || readme.doco.md -nt .doco-cache.sh ]] || echo equal
    equal
    $ touch -r readme.doco.md savetime; touch readme.doco.md
    $ run-doco --all
    example1
    $ [[ "$(stat -c %y readme.doco.md)" != "$(stat -c %y savetime)" ]] && echo changed
    changed
    $ [[ readme.doco.md -ot .doco-cache.sh || readme.doco.md -nt .doco-cache.sh ]] || echo equal
    equal

# There can be only one! ([.-]doco.md file, that is)
    $ touch another-doco.md
    $ run-doco
    Multiple doco.md files in /*/Config.cram.md (glob)
    [64]
    $ rm another-doco.md

# Config is loaded from .doco and docker-compose.yml if not otherwise found;
# COMPOSE_PROJECT_NAME is reset to empty before config runs:
    $ mkdir t; cd t
    $ echo 'FILTER .
    > doco.dump() {
    >     HAVE_FILTERS || echo "cleared!"
    >     RUN_JQ -c . <"$DOCO_CONFIG";
    >     declare -p COMPOSE_PROJECT_NAME
    > }
    > ' >.doco
    $ echo 'services: {t: {image: alpine, command: "bash -c echo test"}}' >docker-compose.yml
    $ COMPOSE_PROJECT_NAME=foo run-doco dump
    cleared!
    {"services":{"t":{"command":"bash -c echo test","image":"alpine"}}}
    declare -x COMPOSE_PROJECT_NAME=""

# Must be only one docker-compose.y{a,}ml
    $ touch docker-compose.yaml
    $ run-doco dump
    Multiple docker-compose files in /*/Config.cram.md/t (glob)
    [64]
    $ rm docker-compose.yaml

# docker-compose.override.yml and docker-compose.override.yaml are included in COMPOSE_FILE
    $ echo 'doco.dump() { declare -p COMPOSE_FILE; }' >.doco
    $ run-doco dump
    declare -x COMPOSE_FILE="/*/Config.cram.md/t/.doco-cache.json" (glob)
    $ touch docker-compose.override.yml; run-doco dump
    declare -x COMPOSE_FILE="/*/Config.cram.md/t/.doco-cache.json (glob)
    /*/Config.cram.md/t/docker-compose.override.yml" (glob)
    $ touch docker-compose.override.yaml; run-doco dump
    Multiple docker-compose.override files in /*/Config.cram.md/t (glob)
    [64]
    $ rm docker-compose.override.yml; run-doco dump
    declare -x COMPOSE_FILE="/*/Config.cram.md/t/.doco-cache.json (glob)
    /*/Config.cram.md/t/docker-compose.override.yaml" (glob)

# .env file is auto-loaded, using docker-compose .env syntax, and
# the "finalize project" and "before commands" events are run, with
# a readonly '--all' group defined:

    $ echo "FOO=baz'bar" >.env

    $ cat <<'EOF' >.doco
    > doco.dump() { echo "${DOCO_SERVICES[@]}"; echo "$FOO"; }
    > event on "finalize project" echo "hi!"
    > event on "before commands" declare -p __doco_target__2d_2dall
    > include "$TESTDIR/../README.md"
    > include "dummy.md" test-caching.sh
    > include "dummy.md"  # multiple includes of same file are a no-op
    > EOF

    $ cat <<'EOF' >dummy.md
    > ```shell
    > echo "dummy loaded"
    > ```
    > EOF

    $ run-doco t dump
    dummy loaded
    hi!
    declare -ar __doco_target__2d_2dall=([0]="t" [1]="example1")
    t
    baz'bar

    $ ls .doco-cache/includes  # cached compiled README
    *%2Fspecs%2F..%2FREADME.md (glob)

    $ cat test-caching.sh
    echo "dummy loaded"

# doco command(s) can't be run from config:

    $ echo 'doco --all' >.doco
    $ run-doco
    doco CLI cannot be used before the project spec is finalized
    [64]

# Back to the test root
    $ cd ..
~~~

### Docker-Compose Configuration

The JSON form of the docker-compose configuration can be obtained using `compose-config` (with the result in `$COMPOSED_JSON`), so long as the project configuration has been finalized.

~~~shell
# Can't read the config till it's done

    $ compose-config
    compose configuration isn't finished
    [64]

# Mock the load

    $ docker-compose() {
    >     if [[ "$*" == config ]]; then
    >         echo "calling doco config" >&2; cat <<'EOF'
    > services:
    >   foo: { image: bar/baz }
    > EOF
    >     else { printf -v REPLY ' %q' "docker-compose" "$@"; echo "${REPLY# }"; } >&2
    >     fi
    > }
    $ DOCO_CONFIG=x.json

# First load calls docker-compose config:

    $ compose-config && { echo "$COMPOSED_JSON" | jq .; }
    calling doco config
    {
      "services": {
        "foo": {
          "image": "bar/baz"
        }
      }
    }

# But subsequent loads come from cache

    $ compose-config && { echo "$COMPOSED_JSON" | jq -c .; }
    {"services":{"foo":{"image":"bar/baz"}}}

~~~

