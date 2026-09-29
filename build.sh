#!/usr/bin/env bash

set -euo pipefail

VET_OPTIONS=(
	-vet-cast
	-vet-semicolon
	-vet-tabs
)

LLDB_COMMANDS_FILE=".lldbinit"

build_debug() {
	odin build src/ -out=kerrek -show-timings -debug "${VET_OPTIONS[@]}"
}

build_release() {
	odin build src/ -out=kerrek -show-timings -o:speed "${VET_OPTIONS[@]}"
}

usage() {
	printf 'Usage: %s [debug|debug-run|release] [program arguments...]\n' "$0" >&2
}

command="${1:-debug}"
if (($# > 0)); then
	shift
fi

case "$command" in
	debug)
		if (($# > 0)); then
			usage
			exit 2
		fi
		build_debug
		;;
	debug-run)
		build_debug

		quit_on_exit='script import os; os._exit(0) if lldb.debugger.GetSelectedTarget().GetProcess().GetState() == lldb.eStateExited else None'
		lldb_options=(-o run -o "$quit_on_exit")
		if [[ -f "$LLDB_COMMANDS_FILE" ]]; then
			lldb_options=(-s "$LLDB_COMMANDS_FILE" "${lldb_options[@]}")
		fi

		lldb "${lldb_options[@]}" -- ./kerrek "$@"
		;;
	release)
		if (($# > 0)); then
			usage
			exit 2
		fi
		build_release
		;;
	*)
		usage
		exit 2
		;;
esac
