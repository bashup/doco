#!/usr/bin/env bash
: '
<!-- ex: set syntax=markdown : '; eval "$(mdsh -E "$BASH_SOURCE")"; # -->

# doco - Project Automation and Literate Devops for docker-compose

doco is a project automation tool for doing literate devops with docker-compose.  It's an extension of both loco and jqmd, written as a literate program using mdsh.  Within this source file, `shell` code blocks are the main program, while `shell mdsh` blocks are metaprogramming, and `~~~shell` blocks are examples tested with cram.

The main program begins with a `#!` line and edit warning:

```shell
#!/usr/bin/env bash
# ---
# This file was automatically generated from doco.md - DO NOT EDIT!
# ---
```

Followed by its license text:

```shell mdsh
# incorporate the LICENSE file as bash comments
source realpaths; realpath.location "$MDSH_SOURCE"
echo; sed -e '1,2d; s/^\(.\)/# \1/; s/^$/#/;' "$REPLY/LICENSE"; echo
```

### Contents

<!-- toc -->

## Configuration

## API

## Commands

### Docker-Compose Commands

### Service Selection

#### with

#### where

### Other

#### jq

## Extending jqmd and loco

