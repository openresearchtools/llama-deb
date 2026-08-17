# llama-deb

Debian repackaging for the ordinary amd64 releases produced by
[`openresearchtools/llama-cpp-arm64-builds`](https://github.com/openresearchtools/llama-cpp-arm64-builds).
TurboQuant releases are deliberately excluded.

## Packages

| Package | Source asset | Backends |
| --- | --- | --- |
| `llama-cpp-amd64` | `llama-bNNNN-bin-ubuntu-vulkan-x64.tar.gz` | All bundled CPU variants and Vulkan |
| `llama-cpp-cuda-amd64` | `llama-bNNNN-bin-ubuntu-cuda13-x64.tar.gz` | All bundled CPU variants and CUDA 13.2 |

The packages conflict with and replace one another because they provide the
same commands. Both provide the virtual package `llama-cpp`. Executables are
available in `/usr/bin`; the unmodified upstream release contents live together
in `/usr/lib/llama-cpp` so their `$ORIGIN` runtime paths continue to work.

These are Ubuntu 24.04 amd64 binary repackages, not source builds. The Vulkan
package declares its Vulkan loader dependency. The CUDA package declares the
CUDA 13.2 runtime packages from NVIDIA's Ubuntu 24.04 repository; a compatible
NVIDIA driver that provides `libcuda.so.1` is also required.

## APT-safe versions

An ordinary llama.cpp tag `bNNNN` becomes `0.0.NNNN-R`, where `R` is this
repository's packaging revision:

| llama.cpp tag | Packaging revision | Debian version |
| --- | ---: | --- |
| `b10453` | 1 | `0.0.10453-1` |
| `b10453` | 2 | `0.0.10453-2` |
| `b10470` | 1 | `0.0.10470-1` |

This ordering gives APT the intended behavior: a larger upstream build always
upgrades a smaller build, and a larger packaging revision upgrades a previous
repackage of the same build. The current packaging revision is stored in
[`packaging/revision`](packaging/revision). Increment it when the package layout
or metadata changes and existing upstream builds need to be republished.

APT uses the package's `Version` field, not its GitHub release tag. An APT
repository can therefore ingest the `.deb` assets from this repository's GitHub
releases and normal `apt update` plus `apt upgrade` will select newer builds.

## Automation

[`repackage.yml`](.github/workflows/repackage.yml) runs every Monday at 05:23
UTC and can also be run manually. It:

1. Selects the numerically largest published, non-prerelease `b<number>` release.
2. Verifies both ordinary amd64 source assets exist and skips work when both
   expected `.deb` assets are already published.
3. Builds and validates the Vulkan and CUDA packages independently.
4. Publishes both packages and `SHA256SUMS` on a release with the upstream tag.

Manual runs can select a source tag, override the packaging revision, or force
replacement of same-named assets. Only `b<number>` tags are accepted, so a
`turbo-*` release cannot be packaged accidentally.

## Build locally

On an amd64 Debian-family system with `dpkg-deb`, `file`, `gzip`, and `tar`:

```bash
scripts/build-deb.sh \
  --tag b10453 \
  --flavor vulkan \
  --archive llama-b10453-bin-ubuntu-vulkan-x64.tar.gz
```

Run `tests/test-packaging.sh` to test tag conversion, Debian version ordering,
package metadata, executable links, and license preservation.

## Licenses

The packaging automation in this repository is MIT-licensed; see
[`LICENSE`](LICENSE). Every generated package keeps the upstream llama.cpp
`LICENSE` byte-for-byte in `/usr/lib/llama-cpp/LICENSE` and installs the same
text at `/usr/share/doc/<package>/copyright`. The repository's packaging license
is included separately as `copyright.packaging`.
