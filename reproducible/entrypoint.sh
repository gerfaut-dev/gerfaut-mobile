#!/usr/bin/env bash
# Builds the unsigned Gerfaut APKs inside the pinned container.
#
# Sources arrive read-only under /src, are copied to a fixed path under
# /build so nothing outside the container can influence the artifacts,
# and the three per-ABI APKs land in /out next to a SHA256SUMS manifest.
#
# It runs twice, in two containers that share the /cache volume:
#   GERFAUT_PHASE=fetch  with the network: a whole build, which fills
#                        /cache with every package, crate and module
#                        the release needs, each checked against its
#                        lock or hash on the way in; its APKs stay in
#                        its container;
#   GERFAUT_PHASE=build  with no network at all: the build again, from
#                        a fresh copy of the sources and the cache alone,
#                        and the only one whose APKs leave.
# A build that would download something fails in the second phase,
# instead of taking it unchecked. What it reads from /cache was checked
# when the first phase put it there: crates against Cargo.lock (by hash,
# or by commit for a git dependency), Dart packages against the
# pubspec.lock files, and Gradle modules against
# verification-metadata.xml, which Gradle checks again at every use. A
# file some build step fetched into /cache on its own, outside those
# three, would not be checked; none does today.
#
# A whole build in the first phase costs a compilation, and spares a
# list of what to fetch that would have to follow every change of
# Flutter, Gradle and cargokit.
#
# Run it through reproducible/build.sh rather than by hand.
set -euo pipefail

PHASE="${GERFAUT_PHASE:-}"
case "$PHASE" in
    fetch|build) ;;
    *) echo "GERFAUT_PHASE must be fetch or build, not '$PHASE'" >&2; exit 2 ;;
esac

# The second phase proves it has no network rather than trusting the
# command line that started it: any interface but loopback, or an
# address that answers, stops it.
if [ "$PHASE" = build ]; then
    for iface in /sys/class/net/*; do
        [ "$(basename "$iface")" = lo ] || { echo "the build phase has a network interface: $(basename "$iface")" >&2; exit 1; }
    done
    if curl --max-time 5 -fsS -o /dev/null https://dl.google.com 2> /dev/null; then
        echo "the build phase reached the network" >&2
        exit 1
    fi
fi

SRC=/src
WORK=/build
OUT=/out

for dir in "$SRC/gerfaut-mobile" "$SRC/gerfaut-core"; do
    [ -d "$dir" ] || { echo "missing source tree: $dir" >&2; exit 1; }
done
mkdir -p "$OUT"

# A fixed build path, identical on every machine: the Rust core resolves
# its sibling through ../../gerfaut-core, and no absolute path from the
# host can reach a compiler.
rm -rf "$WORK"
mkdir -p "$WORK"
cp -a "$SRC/gerfaut-mobile" "$WORK/gerfaut-mobile"
cp -a "$SRC/gerfaut-core" "$WORK/gerfaut-core"

# The tagged commit's date, so nothing picks up the wall clock. Android
# Gradle Plugin already writes a constant timestamp on every zip entry,
# so this mostly matters to the toolchains underneath it.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
export TZ=UTC
export LC_ALL=C.UTF-8

# Rust: no incremental artifacts, and no path from this container in the
# shared objects. Cargokit appends its own -L flag to this variable, so
# the separator has to be the one Cargo expects.
US=$'\x1f'
export CARGO_INCREMENTAL=0
export CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=${WORK}=/gerfaut${US}--remap-path-prefix=${CARGO_HOME}=/cargo${US}--remap-path-prefix=${RUSTUP_HOME}=/rustup"

# Gradle: no daemon, so a build never inherits state from the one before
# it, and no SDK auto-download, so a component missing from the image
# stops the build instead of arriving unpinned from the network. These
# are properties of the container, not of the project, which is why they
# are written here and not in the repository.
mkdir -p "$GRADLE_USER_HOME"
cat > "$GRADLE_USER_HOME/gradle.properties" <<'PROPS'
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.caching=false
android.builder.sdkDownload=false
# The project asks for an 8 GB heap, which is more than a container
# usually gets; these two caps keep both JVMs inside 8 GB of RAM and
# change nothing in the output.
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g
kotlin.daemon.jvmargs=-Xmx1g
# Every module, plugin and tool Gradle downloads is checked against its
# hash in gradle/verification-metadata.xml, put in place below; one
# missing from the file, or another file under its name, stops the build.
org.gradle.dependency.verification=strict
PROPS

cd "$WORK/gerfaut-mobile"

# The hashes live in reproducible/, not in android/gradle/, where Gradle
# reads them: they cover what a release build resolves, on Linux, and
# nothing else, so a debug build or a test run elsewhere would fail on
# the first module the release does not use. They come from Gradle
# itself, in this container: `reproducible/build.sh --write-verification`
# builds without them, has Gradle write what it resolved, builds again
# against what it wrote, and leaves the file in the output folder, to be
# read and committed here.
VERIFICATION=reproducible/verification-metadata.xml
WRITE_VERIFICATION="${GERFAUT_WRITE_VERIFICATION:-0}"
if [ "$WRITE_VERIFICATION" = 1 ] && [ "$PHASE" = fetch ]; then
    rm -f android/gradle/verification-metadata.xml
elif [ "$WRITE_VERIFICATION" = 1 ]; then
    # The file the first phase wrote, which this build checks against.
    [ -f "$OUT/verification-metadata.xml" ] || { echo "the fetch phase wrote no verification-metadata.xml" >&2; exit 1; }
    cp "$OUT/verification-metadata.xml" android/gradle/verification-metadata.xml
else
    [ -f "$VERIFICATION" ] || { echo "missing $VERIFICATION" >&2; exit 1; }
    cp "$VERIFICATION" android/gradle/verification-metadata.xml
fi

VERSION="${GERFAUT_VERSION:-}"
if [ -z "$VERSION" ]; then
    VERSION="v$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' pubspec.yaml)"
fi

echo "==> flutter $(flutter --version | head -1)"
echo "==> rust $(rustup run stable rustc --version)"
echo "==> $PHASE phase, version $VERSION, SOURCE_DATE_EPOCH $SOURCE_DATE_EPOCH"

# `flutter build` runs pub again, without --enforce-lockfile or
# --offline, unless pubspec.yaml is older than pubspec.lock; `git
# archive` gives every file the same date, so pubspec.yaml goes one
# second back, and the only pub of the app is the one below. Its date
# reaches no artifact.
touch -d "@$((SOURCE_DATE_EPOCH - 1))" pubspec.yaml
if [ "$PHASE" = fetch ]; then
    flutter pub get --enforce-lockfile
else
    # Cargo, pub and the pub of cargokit's build tool from the cache
    # alone, each refusing a package missing from it. Without --offline,
    # pub also asks pub.dev for the security advisories of each package,
    # and fails.
    export CARGO_NET_OFFLINE=true CARGOKIT_PUB_OFFLINE=1
    flutter pub get --enforce-lockfile --offline
fi
# Unsigned: the release key never comes near the container. The APKs
# are signed on the release machine by scripts/sign-release.ps1.
build() {
    flutter build apk --release --split-per-abi --android-project-arg=gerfaut.unsigned=true
}
build

if [ "$PHASE" = fetch ]; then
    if [ "$WRITE_VERIFICATION" = 1 ]; then
        # Gradle writes the hash of everything this build resolves,
        # plugins and tools included, when it runs the same tasks with
        # the flag the Flutter tool cannot pass; the build phase then
        # runs with the file in force. It leaves out some parent POMs
        # and BOMs, which the next strict build names; see
        # reproducible/gradle-pins.py.
        (
            cd android
            ./gradlew --write-verification-metadata sha256 assembleRelease \
                -Ptarget-platform=android-arm,android-arm64,android-x64 \
                -Psplit-per-abi=true -Pgerfaut.unsigned=true
        )
        cp android/gradle/verification-metadata.xml "$OUT/verification-metadata.xml"
        owner="$(stat -c '%u:%g' "$OUT")"
        [ "$owner" = "0:0" ] || chown "$owner" "$OUT/verification-metadata.xml"
    fi
    echo "==> fetch phase done; its APKs stay in the container"
    exit 0
fi

for abi in armeabi-v7a arm64-v8a x86_64; do
    src="build/app/outputs/flutter-apk/app-${abi}-release.apk"
    [ -f "$src" ] || { echo "missing build output: $src" >&2; exit 1; }
    cp "$src" "$OUT/gerfaut-${VERSION}-android-${abi}-unsigned.apk"
done

cd "$OUT"
rm -f SHA256SUMS
sha256sum gerfaut-*.apk | sort -k2 > SHA256SUMS
cat SHA256SUMS

# Leave the output owned by whoever owns the mount, not by root.
owner="$(stat -c '%u:%g' "$OUT")"
[ "$owner" = "0:0" ] || chown -R "$owner" "$OUT"
