## Project Definition API

### Declarations

#### `GROUP` *name(s) operator target(s)...*

Add *targets* to the named group(s), defining or redefining jq functions to map those groups to the targeted services.  The *targets* may be services or groups; if a target name isn't recognized it's assumed to be a service and defined as such.  The *operator* is either `:=` or `+=` -- if `+=`, the targets are are added to any existing contents of the groups.  If `:=`, the groups' existing contents are erased and replaced with *targets*.

(Note that this function *adds* to the existing group(s) and recursively expands groups in the target list.  If you want to set an exact list of services, use `target "groupname" set ...` instead.  Also note that the "recursive" expansion is *immediate*: redefining a group used in the target list will *not* update the definition of the referencing group.)

```shell
# Arguments required

    $ (GROUP)
    GROUP requires at least two arguments
    [64]

# Define one group, non-existing name

    $ GROUP delta-xray += echo gamma-zulu
    $ doco delta-xray ps
    docker-compose ps echo gamma-zulu
    $ RUN_JQ -c -n '{} | delta::dash::xray(.image = "test")'
    {"services":{"echo":{"image":"test"},"gamma-zulu":{"image":"test"}}}

# Add to multiple groups, adding but not duplicating

    $ GROUP tango delta-xray += niner gamma-zulu
    $ doco delta-xray ps
    docker-compose ps echo gamma-zulu niner
    $ RUN_JQ -c -n '{} | delta::dash::xray(.image = "test")'
    {"services":{"echo":{"image":"test"},"gamma-zulu":{"image":"test"},"niner":{"image":"test"}}}

    $ doco tango ps
    docker-compose ps niner gamma-zulu
    $ RUN_JQ -c -n '{} | tango(.image = "test")'
    {"services":{"niner":{"image":"test"},"gamma-zulu":{"image":"test"}}}

# "Recursive" group expansion

    $ GROUP whiskey += tango foxtrot
    $ doco whiskey ps
    docker-compose ps niner gamma-zulu foxtrot

# Overwrite contents using :=

    $ GROUP fiz := bar baz; target fiz get; printf '%q\n' "${REPLY[@]}"
    bar
    baz
    $ GROUP fiz := bar; target fiz get; printf '%q\n' "${REPLY[@]}"
    bar
```

#### `SERVICES` *name...*

Declare the named targets to be services and define jq functions for them.  `SERVICES foo bar` will create jq functions `foo()` and `bar()` that can be used to alter `.services.foo` and `.services.bar`, respectively.  The given names must be valid container names and must not already be defined as groups.

```shell
    $ SERVICES alfa foxtrot

# services or groups as subcommands update the active service set
    $ doco alfa ps
    docker-compose ps alfa

# jq function makes modifications to the service entry
    $ RUN_JQ -c -n '{} | foxtrot(.image = "test")'
    {"services":{"foxtrot":{"image":"test"}}}
```

#### `VERSION` *docker-compose version*

Set the version of the docker-compose configuration (by way of a jq filter):

```shell
    $ VERSION 2.1
    $ echo '{}' | RUN_JQ -c
    {"version":"2.1"}
```

### Config

#### `export-env` *filename*

Parse a docker-compose format `env_file`, exporting the variables found therein.  Used to load the [project-level configuration](#project-level-configuration), but can also be used to load additional environment files.

Blank and comment lines are ignored, all others are fed to `export` after stripping the leading and trailing spaces.  The file should not use quoting, or shell escaping: the exact contents of a line after the `=` (minus trailing spaces) are used as the variable's contents.

```shell
    $ export() { printf "export %q\n" "$@"; }   # stub
    $ export-env /dev/stdin <<'EOF'
    > # comment
    >    # indented comment
    >    THIS=$that
    > SOME=thing = else  
    > 
    >  OTHER
    > EOF
    export THIS=\$that
    export SOME=thing\ =\ else
    export OTHER
    $ unset -f export   # ditch the stub
```

#### `export-source` *filename*

`source` the specified file, exporting any variables defined by it that didn't previously exist.  (Note: the environment files are in *shell* syntax (bash syntax to be precise), *not* docker-compose syntax.)

```shell
    $ declare -p FOO 2>/dev/null || echo undefined
    undefined
    $ echo "FOO=bar" >dummy.env
    $ export-source dummy.env
    $ declare -p FOO 2>/dev/null || echo undefined
    declare -x FOO="bar"
```

#### `include` *markdownfile [cachefile]*

Source the mdsh compilation  of the specified markdown file, saving it in *cachefile* first.  If *cachefile* exists and has the same timestamp as *markdownfile*, *cachefile* is sourced without compiling.  If no *cachefile* is given, compilation is done to a file under `.doco-cache/includes`.  A given *markdownfile* can only be included once: this operation is a no-op if *markdownfile* has been `include`d  before.