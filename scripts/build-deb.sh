#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: build-deb.sh --tag TAG --architecture amd64|arm64 --flavor vulkan|cuda --archive FILE [options]

Options:
  --output-dir DIR       Output directory (default: dist)
  --revision NUMBER      Debian packaging revision (default: packaging/revision)
EOF
}

tag=
architecture=
flavor=
archive=
output_dir=dist
revision=

while (( $# > 0 )); do
  case $1 in
    --tag)
      tag=${2:-}
      shift 2
      ;;
    --flavor)
      flavor=${2:-}
      shift 2
      ;;
    --architecture)
      architecture=${2:-}
      shift 2
      ;;
    --archive)
      archive=${2:-}
      shift 2
      ;;
    --output-dir)
      output_dir=${2:-}
      shift 2
      ;;
    --revision)
      revision=${2:-}
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z $tag || -z $architecture || -z $flavor || -z $archive ]]; then
  usage
  exit 2
fi

for command_name in dpkg-deb file gzip tar; do
  if ! command -v "$command_name" >/dev/null; then
    echo "Required command is unavailable: $command_name" >&2
    exit 1
  fi
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "$script_dir/.." && pwd)

if [[ -z $revision ]]; then
  revision=$(<"$repository_root/packaging/revision")
fi
version=$("$script_dir/debian-version.sh" "$tag" "$revision")

case $architecture in
  amd64)
    executable_format='ELF 64-bit LSB.*x86-64'
    source_platform='Ubuntu 24.04 amd64'
    ;;
  arm64)
    executable_format='ELF 64-bit LSB.*ARM aarch64'
    source_platform='Debian Trixie arm64'
    ;;
  *)
    echo "Unsupported architecture '$architecture'; expected amd64 or arm64" >&2
    exit 2
    ;;
esac

case $flavor in
  vulkan)
    package_name=llama-cpp
    conflicting_package='llama-cpp-cuda, llama-cpp-amd64, llama-cpp-arm64'
    provides_field='Provides: llama-cpp-vulkan'
    backend_library=libggml-vulkan.so
    runtime_field='Depends: libc6 (>= 2.38), libgcc-s1 (>= 3.4), libgomp1 (>= 6), libstdc++6 (>= 13.1), libvulkan1 (>= 1.2.131.2)'
    package_summary='llama.cpp command-line tools with CPU and Vulkan backends'
    package_detail="This package contains the ordinary $source_platform llama.cpp build with all bundled CPU variants, the Vulkan backend, tools, server, and RPC server."
    ;;
  cuda)
    package_name=llama-cpp-cuda
    conflicting_package='llama-cpp, llama-cpp-cuda-amd64, llama-cpp-cuda-arm64'
    provides_field='Provides: llama-cpp'
    backend_library=libggml-cuda.so
    runtime_field='Depends: libc6 (>= 2.38), libgcc-s1 (>= 3.4), libgomp1 (>= 6), libstdc++6 (>= 13.1), cuda-cudart-13-2, libcublas-13-2'
    package_summary='llama.cpp command-line tools with CPU and CUDA 13 backends'
    package_detail="This package contains the ordinary $source_platform llama.cpp CUDA 13 build with all bundled CPU variants, tools, server, and RPC server. An NVIDIA driver providing libcuda.so.1 is also required at runtime."
    ;;
  *)
    echo "Unsupported flavor '$flavor'; expected vulkan or cuda" >&2
    exit 2
    ;;
esac

if [[ ! -f $archive ]]; then
  echo "Source archive does not exist: $archive" >&2
  exit 1
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/llama-deb.XXXXXXXX")
trap 'rm -rf -- "$temporary_directory"' EXIT
extract_directory=$temporary_directory/extract
package_root=$temporary_directory/package
mkdir -p "$extract_directory" "$package_root"

expected_root=llama-$tag
mapfile -t archive_members < <(tar -tzf "$archive")
if (( ${#archive_members[@]} == 0 )); then
  echo "Source archive is empty: $archive" >&2
  exit 1
fi

for member in "${archive_members[@]}"; do
  normalized_member=${member%/}
  if [[ $normalized_member != "$expected_root" && $normalized_member != "$expected_root/"* ]]; then
    echo "Unsafe or unexpected archive member: $member" >&2
    exit 1
  fi
done

tar -xzf "$archive" --no-same-owner -C "$extract_directory"
source_directory=$extract_directory/$expected_root

for required_file in LICENSE llama-cli llama-server rpc-server "$backend_library"; do
  if [[ ! -e $source_directory/$required_file ]]; then
    echo "Required upstream file is missing: $required_file" >&2
    exit 1
  fi
done

if ! file "$source_directory/llama-cli" | grep -q "$executable_format"; then
  echo "The source archive does not contain $architecture Linux binaries" >&2
  exit 1
fi

install -d \
  "$package_root/DEBIAN" \
  "$package_root/usr/bin" \
  "$package_root/usr/lib/llama-cpp" \
  "$package_root/usr/share/doc/$package_name"
cp -a "$source_directory/." "$package_root/usr/lib/llama-cpp/"

# Keep byte-for-byte copies of both relevant licenses. The upstream license is
# retained beside the binaries and installed at Debian's conventional path.
install -m 0644 "$source_directory/LICENSE" \
  "$package_root/usr/share/doc/$package_name/copyright"
install -m 0644 "$repository_root/LICENSE" \
  "$package_root/usr/share/doc/$package_name/copyright.packaging"

link_count=0
while IFS= read -r -d '' executable; do
  executable_name=$(basename -- "$executable")
  case $executable_name in
    *.so|*.so.*)
      continue
      ;;
  esac
  ln -s "../lib/llama-cpp/$executable_name" \
    "$package_root/usr/bin/$executable_name"
  ((link_count += 1))
done < <(find "$package_root/usr/lib/llama-cpp" -maxdepth 1 -type f -perm /111 -print0 | sort -z)

if (( link_count == 0 )); then
  echo "No executable tools were found in the source archive" >&2
  exit 1
fi

installed_size=$(du -sk "$package_root/usr" | awk '{print $1}')
cat >"$package_root/DEBIAN/control" <<EOF
Package: $package_name
Version: $version
Section: utils
Priority: optional
Architecture: $architecture
Maintainer: OpenResearchTools <openresearchtools@users.noreply.github.com>
Homepage: https://github.com/ggml-org/llama.cpp
$runtime_field
Conflicts: $conflicting_package
Replaces: $conflicting_package
$provides_field
Installed-Size: $installed_size
X-Upstream-Repository: https://github.com/ggml-org/llama.cpp
X-Upstream-Tag: $tag
Description: $package_summary
 $package_detail
EOF

build_epoch=${SOURCE_DATE_EPOCH:-$(date +%s)}
if [[ ! $build_epoch =~ ^[0-9]+$ ]]; then
  echo "SOURCE_DATE_EPOCH must be an integer" >&2
  exit 2
fi
changelog_date=$(date -u -d "@$build_epoch" -R)
cat >"$temporary_directory/changelog.Debian" <<EOF
$package_name ($version) unstable; urgency=medium

  * Repackage the ordinary upstream llama.cpp $tag $architecture $flavor build.

 -- OpenResearchTools <openresearchtools@users.noreply.github.com>  $changelog_date
EOF
gzip -n -9 -c "$temporary_directory/changelog.Debian" \
  >"$package_root/usr/share/doc/$package_name/changelog.Debian.gz"

# A fixed epoch makes reruns from the same upstream release reproducible.
find "$package_root" -print0 \
  | xargs -0 touch --no-dereference --date="@$build_epoch"

mkdir -p "$output_dir"
output_path=$output_dir/${package_name}_${version}_${architecture}.deb
dpkg-deb --root-owner-group --build "$package_root" "$output_path"

echo "Built $output_path"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    echo "package_name=$package_name"
    echo "version=$version"
    echo "deb_path=$output_path"
  } >>"$GITHUB_OUTPUT"
fi
