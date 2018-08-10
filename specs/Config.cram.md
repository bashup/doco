## Configuration

~~~shell
# Use README.md for default config
    $ cp $TESTDIR/../README.md readme.doco.md

# Ignore/null out all configuration for testing
    $ doco --
~~~

### File and Function Names

Configuration is loaded using loco.  Specifically, by searching for `*.doco.md`, `.doco`, or `docker-compose.yml` above the current directory.  The loco script name is hardcoded to `doco`, so even if it's run via a symlink the function names for custom subcommands will still be `doco.subcommand-name`.  User and site-level configs are also defined.

~~~shell
    $ declare -p LOCO_FILE LOCO_NAME LOCO_USER_CONFIG LOCO_SITE_CONFIG
    declare -a LOCO_FILE=([0]="?*[-.]doco.md" [1]=".doco" [2]="docker-compose.yml")
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
    $ declare -p COMPOSE_FILE DOCO_CONFIG COMPOSE_PATH_SEPARATOR
    declare -x COMPOSE_FILE="/*/Config.cram.md/.doco-cache.json" (glob)
    declare -- DOCO_CONFIG="/*/Config.cram.md/.doco-cache.json" (glob)
    declare -x COMPOSE_PATH_SEPARATOR="
    "

# .cache has same timestamp as what it's built from; and is rebuilt if it changes
    $ [[ readme.doco.md -ot .doco-cache.sh || readme.doco.md -nt .doco-cache.sh ]] || echo equal
    equal
    $ touch -r readme.doco.md savetime; touch readme.doco.md
    $ command doco --all
    example1
    $ [[ "$(stat -c %y readme.doco.md)" != "$(stat -c %y savetime)" ]] && echo changed
    changed
    $ [[ readme.doco.md -ot .doco-cache.sh || readme.doco.md -nt .doco-cache.sh ]] || echo equal
    equal

# There can be only one! ([.-]doco.md file, that is)
    $ touch another-doco.md
    $ command doco
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
    $ COMPOSE_PROJECT_NAME=foo command doco dump
    cleared!
    {"services":{"t":{"command":"bash -c echo test","image":"alpine"}}}
    declare -x COMPOSE_PROJECT_NAME=""

# Must be only one docker-compose.y{a,}ml
    $ touch docker-compose.yaml
    $ command doco dump
    Multiple docker-compose files in /*/Config.cram.md/t (glob)
    [64]
    $ rm docker-compose.yaml

# docker-compose.override.yml and docker-compose.override.yaml are included in COMPOSE_FILE
    $ echo 'doco.dump() { declare -p COMPOSE_FILE; }' >.doco
    $ command doco dump
    declare -x COMPOSE_FILE="/*/Config.cram.md/t/.doco-cache.json" (glob)
    $ touch docker-compose.override.yml; command doco dump
    declare -x COMPOSE_FILE="/*/Config.cram.md/t/.doco-cache.json (glob)
    /*/Config.cram.md/t/docker-compose.override.yml" (glob)
    $ touch docker-compose.override.yaml; command doco dump
    Multiple docker-compose.override files in /*/Config.cram.md/t (glob)
    [64]
    $ rm docker-compose.override.yml; command doco dump
    declare -x COMPOSE_FILE="/*/Config.cram.md/t/.doco-cache.json (glob)
    /*/Config.cram.md/t/docker-compose.override.yaml" (glob)

# .env file is auto-loaded, using docker-compose .env syntax, and
# the "finalize_project" and "before_commands" events are run, with
# a readonly '--all' group defined:

    $ echo "FOO=baz'bar" >.env

    $ cat <<'EOF' >.doco
    > doco.dump() { echo "${DOCO_SERVICES[@]}"; echo "$FOO"; }
    > event on "finalize_project" echo "hi!"
    > event on "before_commands" declare -p __doco_target__2d_2dall
    > EOF

    $ command doco t dump
    hi!
    declare -ar __doco_target__2d_2dall=([0]="t")
    t
    baz'bar

# doco command(s) can't be run from config:

    $ echo 'doco --all' >.doco
    $ command doco
    doco CLI cannot be used before the project spec is finalized
    [64]

# Back to the test root
    $ cd ..
~~~

