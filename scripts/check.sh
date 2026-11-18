#!/bin/sh
# Compatibility entry point for the V repository check.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec v run "$script_dir/check.vsh" "$@"
