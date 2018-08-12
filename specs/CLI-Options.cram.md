## Built-in Options

~~~shell
# Pre-define service names used in examples:

    $ SERVICES a b c alfa foxtrot
~~~

#### `--`

Reset the active service set to empty (and non-existent).  In terms of target selection, everything after the `--` executes as if it were the first thing on the command line passed to doco, with any prior targets discarded.

If no services are explicitly added after this point in the command line, then docker-compose subcommands will have their default behavior and argument parsing.  (That is, commands that take multiple services will apply to all services unless a service is listed, and commands that apply to a single service will require it as the first post-option argument.)

~~~shell
    $ doco a b c -- ps
    docker-compose ps
~~~

#### `--all`

Update the service set to include *all* services for the remainder of the command line (unless reset again with `--`). Note that this is different from executing normal docker-compose commands with an explicitly empty set (e.g. using  `--` or an empty group), in that it explicitly passes along all the service names.  (Among other things, this lets you use commands like `foreach`to run single-target commands (e.g. `exec`) against each service.)

~~~shell
    $ doco --all ps
    docker-compose ps example1
~~~

(Note: this option is actually implemented as a built-in `GROUP`, defined immediately after the project configuration is generated.)

#### `--where=`*jq-filter*

Add services matching *jq-filter* to the current service set for the remainder of the command line.  If this is the last thing on the command line, outputs service names to stdout, one per line.  The filter is a jq expression that will be applied to the body of a service definition as it appears in the form *provided* to docker-compose.  (That is, values supplied by compose via `extends` or variable interpolation are not available.)

~~~shell
    $ doco --where true
    example1
    $ doco --where false
    $ doco --where=false ps
    no services specified for ps
    [64]
    $ doco --where=true ps
    docker-compose ps example1
~~~

#### `--with=`*target*

The `--with`  option adds one or more services or groups to the current service set for the remainder of the command line, unless reset with `--`.  The *target* argument is either a single service or group name, or a string containing a space-separated list of service or group names.  `--with` can be given more than once.  To reset the service set to empty, use `--`.

~~~shell
    $ doco --with "a b" ps
    docker-compose ps a b
    $ doco --with "a b" --with c ps
    docker-compose ps a b c
~~~

You don't normally need to use this option, because you can simply run `doco` *targets... subcommand...* in the first place.  It's really only useful in cases where you have service or group names that might conflict with other subcommand names, or need to store a set of group/service names in a non-array variable (e.g. in a `.env` file.)

#### `--with-default=`*target*

Invoke `doco` *subcommand args...*, adding *target* to the current service set if the current set is empty.  Note that *target* could still be nonexistent or empty, so you may wish to follow this option with `--require-services` to verify the new count.

~~~shell
    $ GROUP tango := alfa foxtrot

    $ doco -- --with-default alfa ps
    docker-compose ps alfa

    $ doco foxtrot --with-default=alfa ps -q
    docker-compose ps -q foxtrot
~~~

#### `--require-services=`*flag [subcommand args...]*

This is the command-line equivalent of calling `require-services` *flag subcommand* before invoking *subcommand args...*.  That is, it checks that the relevant number of services are present and exits with a usage error if not.  The *flag* argument can include a space and a command name to be used in place of *subcommand* in any error messages.

~~~shell
    $ (doco -- --require-services="1 somecommand" ps)
    no services specified for somecommand
    [64]
    $ (doco -- --require-services ps)
    --require-services argument must begin with ., -, +, or 1
    [64]
~~~