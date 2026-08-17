#!/usr/bin/env bash

set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  echo "Usage: $0 <llama.cpp-tag> [packaging-revision]" >&2
  exit 2
fi

tag=$1
revision=${2:-1}

if [[ ! $tag =~ ^b([0-9]+)$ ]]; then
  echo "Unsupported llama.cpp tag '$tag'; expected b followed by digits" >&2
  exit 2
fi

build_number=${BASH_REMATCH[1]}
if [[ $build_number != 0 && $build_number == 0* ]]; then
  echo "Non-canonical llama.cpp tag '$tag'; build numbers must not have leading zeroes" >&2
  exit 2
fi

if [[ ! $revision =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid packaging revision '$revision'; expected a positive integer" >&2
  exit 2
fi

printf '0.0.%s-%s\n' "$build_number" "$revision"
