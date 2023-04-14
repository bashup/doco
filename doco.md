#!/usr/bin/env bash
: '
<!-- ex: set syntax=markdown : '; eval "$(mdsh -E "$BASH_SOURCE")"; # -->

# doco - Project Automation and Literate Devops for docker-compose

doco is a project automation tool for doing literate devops with docker-compose.  It's an extension of both loco and jqmd, written as a literate program using mdsh.  Within this source file, `shell` code blocks are the main program, while `shell mdsh` blocks are metaprogramming.

The main program begins with a `#!` line and edit warning, followed by its license text and embedded copies of jqmd and loco, and finally the individual doco modules for [configuration](Config.md), [services](Services.md), [docker-compose integration](Compose.md), and the [command-line interface](CLI.md):

```shell mdsh
@module doco.md
@main loco_main

@require pjeby/license @comment LICENSE

@require bashup/jqmd   mdsh-source "$BASHER_PACKAGES_PATH/bashup/jqmd/jqmd.md"
@require bashup/loco   mdsh-source "$BASHER_PACKAGES_PATH/bashup/loco/loco.md"
@require bashup/c3-mro mdsh-source "$BASHER_PACKAGES_PATH/bashup/c3-mro/c3-mro.md"

@require doco/config   mdsh-source "$DEVKIT_ROOT/Config.md"
@require doco/services mdsh-source "$DEVKIT_ROOT/Services.md"
@require doco/compose  mdsh-source "$DEVKIT_ROOT/Compose.md"
@require doco/cli      mdsh-source "$DEVKIT_ROOT/CLI.md"

@require .devkit/tty   cat "$DEVKIT_HOME/modules/tty" <(echo "tty_prefix=DOCO_")
```

## Merging jqmd and loco

We pass along our jq API functions to jqmd, and override the `mdsh-error` function to call `loco_error` so that all errors ultimately go through the same function.

```shell
DEFINE "${mdsh_raw_jq_api[*]}"

# shellcheck disable=SC2059  # argument is a printf format string
mdsh-error() { printf -v REPLY "$1"'\n' "${@:2}"; loco_error "$REPLY"; }
```
