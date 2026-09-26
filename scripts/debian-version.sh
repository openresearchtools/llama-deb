#!/usr/bin/env bash

set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  echo "Usage: $0 <llama.cpp-tag> [packaging-revision]" >&2
  exit 2
fi

tag=$1
revision=${2:-1}

if [[ ! $revision =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid packaging revision '$revision'; expected a positive integer" >&2
  exit 2
fi

if [[ $tag =~ ^b(0|[1-9][0-9]*)$ ]]; then
  version=0.0.${BASH_REMATCH[1]}
elif [[ $tag =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  version=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}
else
  echo "Unsupported llama.cpp tag '$tag'; expected b<number> or v<major>.<minor>.<patch>" >&2
  exit 2
fi

printf '%s-%s\n' "$version" "$revision"
