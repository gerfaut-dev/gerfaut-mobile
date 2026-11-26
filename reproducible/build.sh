#!/usr/bin/env bash
# Builds the unsigned Gerfaut APKs in the pinned container, the way the
# Release workflow builds them.
#
#   reproducible/build.sh                  into reproducible/out
#
# The script exports both source trees from git at a fixed path, so the
# working tree, the checkout location and the host toolchain have no say
# in the result. It needs git and docker, nothing else. The container
# runs twice on one volume of downloads: once with the network to fill
# it, once with none to build (see entrypoint.sh).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

image=gerfaut-mobile-rb:latest
core="${GERFAUT_CORE_DIR:-$repo/../gerfaut-core}"
out="$here/out"
ref=HEAD
version=""
build_image=1
any_core=0
write_verification=0

usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<'USAGE'

Options:
  --core DIR      gerfaut-core checkout (default: ../gerfaut-core)
  --image NAME    tag to build and run (default: gerfaut-mobile-rb:latest)
  --out DIR       output directory (default: reproducible/out)
  --ref REF       commit to build (default: HEAD)
  --version TAG   version used in the artifact names (default: from pubspec.yaml)
  --skip-image    reuse the image already built
  --any-core      accept a gerfaut-core checkout other than the pinned one
  --write-verification
                  build without reproducible/verification-metadata.xml, have
                  Gradle write it, build again against it, and leave it in
                  the output directory (to commit after reading it)

Environment:
  GERFAUT_RUN_ARGS  extra arguments for both containers, for example
                    "--cpus 6 -e CARGO_BUILD_JOBS=6"
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --core) core="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --ref) ref="$2"; shift 2 ;;
        --version) version="$2"; shift 2 ;;
        --image) image="$2"; shift 2 ;;
        --skip-image) build_image=0; shift ;;
        --any-core) any_core=1; shift ;;
        --write-verification) write_verification=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# Docker Desktop wants a Windows path even when the shell hands it a
# POSIX one.
hostpath() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}
docker() { MSYS_NO_PATHCONV=1 command docker "$@"; }

pinned="$(tr -d ' \t\r\n' < "$here/gerfaut-core.rev")"
[ -d "$core/.git" ] || [ -f "$core/.git" ] || {
    echo "not a gerfaut-core checkout: $core" >&2
    echo "clone https://github.com/gerfaut-dev/gerfaut-core at $pinned" >&2
    exit 1
}
core_rev="$(git -C "$core" rev-parse HEAD)"
if [ "$core_rev" != "$pinned" ] && [ "$any_core" -eq 0 ]; then
    echo "gerfaut-core is at $core_rev, this release pins $pinned" >&2
    echo "check it out, or pass --any-core to build anyway" >&2
    exit 1
fi

# The commit date of what is being built, not the wall clock.
epoch="$(git -C "$repo" log -1 --format=%ct "$ref")"
[ -z "$(git -C "$repo" status --porcelain)" ] || \
    echo "warning: uncommitted changes are not part of the build ($ref is)" >&2

if [ "$build_image" -eq 1 ]; then
    echo "==> building $image"
    docker build -t "$image" "$(hostpath "$here")"
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/gerfaut-mobile" "$stage/gerfaut-core"
# Blob bytes, never the working-tree representation: a Windows checkout
# with core.autocrlf on would otherwise hand the container CRLF sources
# and a different APK.
archive() { git -C "$1" -c core.autocrlf=false -c core.eol=lf archive --format=tar "$2"; }
archive "$repo" "$ref" | tar -x -C "$stage/gerfaut-mobile"
archive "$core" "$core_rev" | tar -x -C "$stage/gerfaut-core"

# The volume the two phases share: what the first downloads, and the
# objects it compiled into the plugins' folders of the pub cache, which
# the second phase links as they are. It is made for this build and
# removed with it, so nothing a build left behind reaches the next one.
cache_volume="$(docker volume create)"
trap 'rm -rf "$stage"; docker volume rm "$cache_volume" > /dev/null || echo "remove the volume of downloads by hand: docker volume rm $cache_volume" >&2' EXIT

run_phase() {
    local phase="$1"
    shift
    echo "==> $phase phase"
    # shellcheck disable=SC2086  # GERFAUT_RUN_ARGS is a list of words
    docker run --rm "$@" ${GERFAUT_RUN_ARGS:-} \
        -e GERFAUT_PHASE="$phase" \
        -e SOURCE_DATE_EPOCH="$epoch" \
        -e GERFAUT_VERSION="$version" \
        -e GERFAUT_WRITE_VERIFICATION="$write_verification" \
        -v "$cache_volume:/cache" \
        -v "$(hostpath "$stage"):/src:ro" \
        "$image"
}

rm -rf "$out"
mkdir -p "$out"
# The output folder reaches the phase with the network only to take the
# Gradle hashes it writes.
if [ "$write_verification" -eq 1 ]; then
    run_phase fetch -v "$(hostpath "$out"):/out"
else
    run_phase fetch
fi
run_phase build --network none -v "$(hostpath "$out"):/out"
echo
echo "==> artifacts in $out"
