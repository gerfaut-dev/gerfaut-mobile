#!/bin/bash
# Checks a tree of downloaded tools against the hashes the Dockerfile
# pins, then checks that nothing else came with it.
#
#   tree-pins [--sdkmanager] <root> <hash>:<path>... [--except <path>]...
#
# Each <path>, relative to <root>, must hash to <hash>: one sha256 over
# the path and content of every file, and the path and target of every
# link, under it; with --sdkmanager, leaving out the package.xml and
# .installer/ that sdkmanager writes itself into each package. Then
# every other file and link under <root> must be, or lie inside, a path
# given with --except. An --except is a shell pattern; one with no `/`
# names an entry of <root> itself, a file or a whole folder:
# `--except '*.stamp'` admits the stamps a tool writes next to its
# trees, and no stamp deeper down.
#
# Every problem is printed before it fails, so one run with a wrong pin
# gives every hash to write down. `tree-pins <root> --print <path>...`
# prints the hash of each path without checking anything.
set -euo pipefail

sdkmanager=0
if [ "${1:-}" = --sdkmanager ]; then
    sdkmanager=1
    shift
fi

tree_hash() {
    (
        cd "$1"
        {
            if [ "$sdkmanager" -eq 1 ]; then
                find . -type f ! -path ./package.xml ! -path "./.installer/*" -print0
            else
                find . -type f -print0
            fi \
                | LC_ALL=C sort -z | xargs -0 -r sha256sum
            find . -type l -printf "%p -> %l\n" | LC_ALL=C sort
        } | sha256sum | cut -d" " -f1
    )
}

root="${1:?usage: tree-pins <root> <hash>:<path>... [--except <path>]...}"
shift
cd "$root"

if [ "${1:-}" = --print ]; then
    shift
    for path in "$@"; do echo "$(tree_hash "$path"):$path"; done
    exit 0
fi

pinned=()
excepted=()
while [ $# -gt 0 ]; do
    case "$1" in
        --except) excepted+=("${2:?--except needs a path}"); shift 2 ;;
        *:*) pinned+=("$1"); shift ;;
        *) echo "tree-pins: not <hash>:<path>: $1" >&2; exit 2 ;;
    esac
done
[ "${#pinned[@]}" -gt 0 ] || { echo "tree-pins: nothing pinned under $root" >&2; exit 2; }

bad=0
covered=()
for pin in "${pinned[@]}"; do
    want="${pin%%:*}"
    path="${pin#*:}"
    covered+=("$path")
    if [ ! -d "$path" ]; then
        echo "tree-pins: $root/$path is missing" >&2
        bad=1
        continue
    fi
    have="$(tree_hash "$path")"
    if [ "$have" != "$want" ]; then
        echo "tree-pins: $root/$path is $have, pinned $want" >&2
        bad=1
    fi
done

# Everything outside the pinned and excepted paths: a download nothing
# checked. The patterns are left unquoted on purpose, to match as
# patterns.
unpinned="$(
    find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort | while IFS= read -r file; do
        inside=0
        for path in "${covered[@]}"; do
            case "$file" in "$path"/*) inside=1; break ;; esac
        done
        if [ "$inside" -eq 0 ]; then
            for path in "${excepted[@]}"; do
                # With no slash, the pattern names an entry of <root>
                # itself: a file, or a folder and all it holds.
                # shellcheck disable=SC2254
                case "$path" in
                    */*) case "$file" in $path|$path/*) inside=1; break ;; esac ;;
                    *) case "${file%%/*}" in $path) inside=1; break ;; esac ;;
                esac
            done
        fi
        [ "$inside" -eq 1 ] || echo "$file"
    done
)"
if [ -n "$unpinned" ]; then
    echo "tree-pins: $(echo "$unpinned" | wc -l) files under $root are in no pinned tree; they and their folders:" >&2
    echo "$unpinned" | awk -F/ '{ d = $1; if (NF > 1) d = d "/" $2; if (NF > 2) d = d "/" $3; print d }' | LC_ALL=C sort -u | sed 's/^/  /' >&2
    bad=1
fi

exit "$bad"
