#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/llama-deb-test.XXXXXXXX")
trap 'rm -rf -- "$temporary_directory"' EXIT

assert_equal() {
  local expected=$1
  local actual=$2
  local context=$3
  if [[ $actual != "$expected" ]]; then
    printf 'Assertion failed (%s): expected %q, got %q\n' \
      "$context" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_equal '0.0.1-1' \
  "$("$repository_root/scripts/debian-version.sh" b1)" \
  'first upstream build'
assert_equal '0.0.10453-2' \
  "$("$repository_root/scripts/debian-version.sh" b10453 2)" \
  'packaging revision'

if "$repository_root/scripts/debian-version.sh" turbo-tqp-v0.3.0 >/dev/null 2>&1; then
  echo 'TurboQuant tags must be rejected' >&2
  exit 1
fi
if "$repository_root/scripts/debian-version.sh" b010 1 >/dev/null 2>&1; then
  echo 'Non-canonical build tags must be rejected' >&2
  exit 1
fi
if ! dpkg --compare-versions 0.0.10454-1 gt 0.0.10453-9; then
  echo 'A newer llama.cpp build must supersede every older packaging revision' >&2
  exit 1
fi
if ! dpkg --compare-versions 0.0.10453-2 gt 0.0.10453-1; then
  echo 'A newer packaging revision must be an APT upgrade' >&2
  exit 1
fi

source_root=$temporary_directory/source/llama-b10453
mkdir -p "$source_root"
printf '%s\n' 'upstream license fixture' >"$source_root/LICENSE"
for executable in llama-cli llama-server rpc-server llama-bench; do
  cp /bin/true "$source_root/$executable"
done
cp /bin/true "$source_root/libggml-vulkan.so"
cp /bin/true "$source_root/libggml-cuda.so"
tar -czf "$temporary_directory/llama-b10453-test.tar.gz" \
  -C "$temporary_directory/source" llama-b10453

export SOURCE_DATE_EPOCH=1786942800
for flavor in vulkan cuda; do
  output_directory=$temporary_directory/dist-$flavor
  "$repository_root/scripts/build-deb.sh" \
    --tag b10453 \
    --flavor "$flavor" \
    --archive "$temporary_directory/llama-b10453-test.tar.gz" \
    --output-dir "$output_directory" \
    --revision 2

  case $flavor in
    vulkan) package_name=llama-cpp-amd64 ;;
    cuda) package_name=llama-cpp-cuda-amd64 ;;
  esac
  deb=$output_directory/${package_name}_0.0.10453-2_amd64.deb
  test -s "$deb"
  assert_equal "$package_name" "$(dpkg-deb -f "$deb" Package)" "$flavor package name"
  assert_equal '0.0.10453-2' "$(dpkg-deb -f "$deb" Version)" "$flavor version"
  assert_equal 'amd64' "$(dpkg-deb -f "$deb" Architecture)" "$flavor architecture"
  assert_equal 'b10453' "$(dpkg-deb -f "$deb" X-Upstream-Tag)" "$flavor upstream tag"

  unpacked=$temporary_directory/unpacked-$flavor
  dpkg-deb -x "$deb" "$unpacked"
  assert_equal '../lib/llama-cpp/llama-cli' \
    "$(readlink "$unpacked/usr/bin/llama-cli")" \
    "$flavor executable link"
  cmp "$source_root/LICENSE" "$unpacked/usr/lib/llama-cpp/LICENSE"
  cmp "$source_root/LICENSE" "$unpacked/usr/share/doc/$package_name/copyright"
  cmp "$repository_root/LICENSE" \
    "$unpacked/usr/share/doc/$package_name/copyright.packaging"
  "$unpacked/usr/bin/llama-cli"
done

echo 'All packaging tests passed.'
