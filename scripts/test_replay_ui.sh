#!/bin/sh
# Compatibility entry point for the V replay UI check.
set -eu
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec v run "$dir/test_replay_ui.vsh" "$@"
