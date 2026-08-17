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

export SOURCE_DATE_EPOCH=1786942800
for architecture in amd64 arm64; do
  source_root=$temporary_directory/source-$architecture/llama-b10453
  mkdir -p "$source_root"
  printf '%s\n' 'upstream license fixture' >"$source_root/LICENSE"
  for executable in llama-cli llama-server rpc-server llama-bench; do
    cp /bin/true "$source_root/$executable"
  done
  cp /bin/true "$source_root/libggml-vulkan.so"
  cp /bin/true "$source_root/libggml-cuda.so"

  if [[ $architecture == arm64 ]]; then
    while IFS= read -r -d '' executable; do
      printf '\267\000' | dd of="$executable" bs=1 seek=18 conv=notrunc status=none
    done < <(find "$source_root" -type f ! -name LICENSE -print0)
  fi

  source_archive=$temporary_directory/llama-b10453-$architecture-test.tar.gz
  tar -czf "$source_archive" \
    -C "$temporary_directory/source-$architecture" llama-b10453

  for flavor in vulkan cuda; do
    output_directory=$temporary_directory/dist-$architecture-$flavor
    "$repository_root/scripts/build-deb.sh" \
      --tag b10453 \
      --architecture "$architecture" \
      --flavor "$flavor" \
      --archive "$source_archive" \
      --output-dir "$output_directory" \
      --revision 2

    case $flavor in
      vulkan) package_name=llama-cpp ;;
      cuda) package_name=llama-cpp-cuda ;;
    esac
    deb=$output_directory/${package_name}_0.0.10453-2_${architecture}.deb
    test -s "$deb"
    assert_equal "$package_name" "$(dpkg-deb -f "$deb" Package)" "$architecture $flavor package name"
    assert_equal '0.0.10453-2' "$(dpkg-deb -f "$deb" Version)" "$architecture $flavor version"
    assert_equal "$architecture" "$(dpkg-deb -f "$deb" Architecture)" "$architecture $flavor architecture"
    assert_equal 'b10453' "$(dpkg-deb -f "$deb" X-Upstream-Tag)" "$architecture $flavor upstream tag"

    unpacked=$temporary_directory/unpacked-$architecture-$flavor
    dpkg-deb -x "$deb" "$unpacked"
    assert_equal '../lib/llama-cpp/llama-cli' \
      "$(readlink "$unpacked/usr/bin/llama-cli")" \
      "$architecture $flavor executable link"
    cmp "$source_root/LICENSE" "$unpacked/usr/lib/llama-cpp/LICENSE"
    cmp "$source_root/LICENSE" "$unpacked/usr/share/doc/$package_name/copyright"
    cmp "$repository_root/LICENSE" \
      "$unpacked/usr/share/doc/$package_name/copyright.packaging"
    if [[ $architecture == amd64 ]]; then
      "$unpacked/usr/bin/llama-cli"
    fi
  done
done

echo 'All packaging tests passed.'
