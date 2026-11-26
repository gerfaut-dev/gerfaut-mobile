# Pinned toolchain the Gerfaut Android releases are built with.
#
# Everything this image downloads is checked against a hash written in
# this file, before anything downloaded runs:
#   - the base image and its JDK by digest;
#   - the Ubuntu packages by a dated snapshot of the archive, whose
#     signed index apt checks against the keyring of that image;
#   - cmdline-tools, rustup, the Dart SDK of Flutter and the Rust
#     release manifest by the hash of their download; the manifest gives
#     the hash of every Rust package;
#   - Flutter by commit, and the packages of its own tool by the hashes
#     of the pubspec.lock that commit carries;
#   - what sdkmanager and `flutter precache` unpack by the hash of each
#     tree, and nothing else may come with them (tree-pins.sh).
# The Gradle modules are checked against
# reproducible/verification-metadata.xml, the Rust crates against
# Cargo.lock and the Dart packages against the pubspec.lock files, at
# build time (entrypoint.sh), and the build itself runs with no network.
#
# What is left to trust: each hash was taken on first use, from one
# download or two (the trees of the SDK and of the Flutter cache came out
# the same from two builds of this image, and the NDK, CMake, the Dart
# SDK and seven Flutter trees from an earlier one too), so a file that
# was already bad on those days is pinned as it is. Gradle's hashes are
# those Gradle read when it wrote reproducible/verification-metadata.xml,
# and those reproducible/gradle-pins.py added. sdkmanager unpacks its
# archives before their trees are checked, under an account that can
# write nowhere else.
#
# The image builds *unsigned* APKs; signing happens later, on the release
# machine, with a key this image never sees.
#
# Build and run it through reproducible/build.sh, which also exports the
# sources at a fixed path so no host path reaches the artifacts.

# eclipse-temurin 17.0.20+8 on Ubuntu 22.04.5.
FROM eclipse-temurin:17.0.20_8-jdk-jammy@sha256:400014962ad7224461f945bb1cc3d7d5a1927ce15b8245b72d9cedcda554cd2a

# cmdline-tools 23.0. The checksum is the one Google publishes in
# https://dl.google.com/android/repository/repository2-3.xml, as sha256.
ARG ANDROID_CMDLINE_TOOLS=commandlinetools-linux-16111833_latest.zip
ARG ANDROID_CMDLINE_TOOLS_SHA256=0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8
# The tree that zip unpacks to, which sdkmanager must leave as it was.
ARG ANDROID_CMDLINE_TOOLS_TREE_SHA256=c038ecb3136df23157c41f36c3a57fa139a3ee69777a8e27bc683c1597e5f625
# android-36 is the app's compileSdk and targetSdk; 35 and 34 are what
# some of the Flutter plugins compile against, and Gradle needs each one.
# Each comes with the hash of the tree sdkmanager unpacks (see the NDK
# below for how they are taken).
ARG ANDROID_PLATFORM_TREES="\
9ae14fa9b77c6cd829204fcf9e70c06675691d7738921cb438db95a0f2ab2814:android-36 \
78a54bb99ad298d93583ac4f737ec45f1a2ffe2e9febf9aa22843fc2d007efc6:android-35 \
517bab411cdc660897ecf7ddf477d40776d0c4805455ed10edd468dbaf026f31:android-34"
# The default build-tools revision of Android Gradle Plugin 9.4.1.
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_BUILD_TOOLS_TREE_SHA256=a61f05da6235095132c642176c3b2d0bd9ca9fcb8ff17d6974bd5cf81b94ed0f
# The NDK Flutter 3.47.7 defaults to, which every native part builds
# with since flutter_zxing 3 stopped pinning an older one.
ARG ANDROID_NDK=28.2.13676358
# flutter_zxing and jni build their native code through CMake.
ARG ANDROID_CMAKE=3.22.1
# The NDK and CMake compile the native code the APK carries. sdkmanager
# checks what it downloads against a SHA-1 from a catalogue it fetches
# the same way, so the tree it unpacks is checked again here, path and
# content of every file and link (tree-pins.sh). Both hashes were
# taken from the archives the catalogue names, android-ndk-r28c-linux.zip
# and cmake-3.22.1-linux.zip, whose SHA-1 matched it, and they equal the
# trees an earlier sdkmanager install had made. To change a version:
# install it with sdkmanager, read `tree-pins --sdkmanager "$ANDROID_HOME" --print
# <its folder>`, and check the archive it came from against the
# catalogue the same way. platform-tools is not installed: adb is for
# devices, and a release build never runs it.
ARG ANDROID_NDK_TREE_SHA256=23ae06352d74473cfc6d89ce88fec61ddbb097817e92030dfdd838873d0b7e6b
ARG ANDROID_CMAKE_TREE_SHA256=62b120bf4f6a00d14fad5ad549bfb653c929788b53d787529d5922ff1ab591a1
ARG FLUTTER_VERSION=3.47.7
ARG FLUTTER_COMMIT=abaf9c523780a608bd46686fd5e53740a07077f8
# The Dart SDK of the engine that commit names (bin/internal/
# engine.version), which runs the Flutter tool: dart-sdk-linux-x64.zip
# from https://storage.googleapis.com/flutter_infra_release/flutter/
# <engine>/. Its tree is also the dart-sdk one below, taken on another
# machine.
ARG FLUTTER_DART_SDK_SHA256=37968cb9f0c2705e623dd0a39a1e753e8e8cbdf4876dd38f20f4ada4eb71127c
# Every tree `flutter precache` fills, each hashed like the NDK. A
# release build reads gen_snapshot and the engine of each ABI (the engine
# itself reaches the APK from Maven, and Gradle checks it), the patched
# SDK the app's Dart compiles against, sky_engine, the Dart SDK whose
# front end compiles it, and the host tools that write into the APK, such
# as font-subset; the other trees are pinned all the same, so that
# nothing in the cache is unchecked: the debug and profile engines, the
# Gradle wrapper Flutter writes into new projects, the Material fonts,
# flutter_gpu, and the iOS device tools `--universal` brings (never run
# here). The engine revision names these files but nothing checks them
# on the way in. Beside them, Flutter's stamps and lock, the licence
# notices of two archives, and the snapshot of the tool it compiled
# itself from the checked sources, with the checked Dart SDK. The first
# seven were taken from a cache filled for the same release on another
# machine, which gave the same trees; the others from one fill, which a
# second build of this image gave again. To read them again: `tree-pins
# /opt/flutter/bin/cache --print <tree>...` in the image.
ARG FLUTTER_CACHE_TREES="\
a1dfe4083a1f17b70639f0fa3b57582483ceabf3caac86b0556e88cf9781182b:artifacts/engine/android-arm-release \
36a69fdce37f668ba65310f49e9aeee25b84a2f634ca6075e247a2252a567511:artifacts/engine/android-arm64-release \
0c487f1fe96e50241391836f252dc449abe38faae94008ddece15a0e7820469d:artifacts/engine/android-x64-release \
572852b710a9841c2de6668bf17f8041a2e3acfccd466bc41902369ca73668bf:artifacts/engine/common \
501978274592653e555dd4ccb0bfafe6652ce2acb9dbdbbf23a8a160ac7e483c:pkg/sky_engine \
496af49affa74eda470838e60d62cf40e23a5638b9fd686e96129ae634667874:dart-sdk \
d9ec0f47dcb832cde4e06b555eab83f22068ddf95976e399311f9d0328094853:artifacts/engine/linux-x64 \
95a22f609e7d3630ec8cd964e4b1e9dd3b4eb164abf57a914bd095021d7b03fc:artifacts/engine/android-arm \
9ee92ec0b8ab208b461d794b427d72d38e1a7226bdf3ffcbaf164a723df4f0ad:artifacts/engine/android-arm-profile \
5c558c24a34099ff27faa5ebadcdf0f940bc5b9f343e96720f8ffd4897baef2d:artifacts/engine/android-arm64 \
3935c750e3a97a48ae6c2e57bd3eecdcd52134306dd9d7cb6fdd869768174541:artifacts/engine/android-arm64-profile \
1f63c2e019a4aa595d0bf210f5e25d1fd5451dca43a1b22400330ac7d3d19b91:artifacts/engine/android-x64 \
5651ff27eec76664c3f2f0fd9d118d357d2455ff1f21b72677e2457db7d72b0f:artifacts/engine/android-x64-profile \
8be94ff6b9c84021fc4983e0cb5fad54b0a98a3058485999634fa7110b499fd9:artifacts/engine/android-x86 \
82969c72ea8423e9ad88e8d72b0b4148a4489466696a1868adeeea838fd5731a:artifacts/gradle_wrapper \
e5730cd893dec89922691caa9d5b960fbb8750a592b68855e9f34e6faa50e849:artifacts/material_fonts \
6338d1bce06e54abc3101af3d8b57daf039dfd9dfc43c22f03d1765df2fb895c:pkg/flutter_gpu \
6edddf20f5a640cf800637ff53b3d788fb0073ce32c91cc4f27d6e6adce40109:artifacts/ios-deploy \
c03cf7884aefa7cb3b6f9936903fb86d14b6b41864b9c35fa4e126382b9ac5fd:artifacts/libimobiledevice \
517545973f6ed18a80231fabcd2e94bb4e2a76fafb87d4e825b131448a4f5ec4:artifacts/libimobiledeviceglue \
1e5467c0277d5a6ab68c37e02204c98011a01262be42789d983169c3808ec943:artifacts/libplist \
e4e771beff622101ce4f13dee4d0143d552d11c493a6afa4a773dbe4c407565f:artifacts/libusbmuxd \
8c27d90013f8a011d6f4470f16e89e8881f2f4bff60b40e18725ce3d01b5538a:artifacts/openssl"
# The manifest hash has to follow the version:
#   curl -fsSL https://static.rust-lang.org/dist/channel-rust-<version>.toml | sha256sum
ARG RUST_VERSION=1.99.1
ARG RUST_MANIFEST_SHA256=fb152be80975c194aa5fc684b2aec3a6e14e2b855efe2faa4e5f8ae6e590f463
# rustup-init 1.29.1, the installer of the toolchain above, fetched as a
# binary and checked against the checksum rustup publishes beside it
# (rustup-init.sha256), never piped from a script into a shell.
ARG RUSTUP_VERSION=1.29.1
ARG RUSTUP_INIT_SHA256=dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    FLUTTER_ROOT=/opt/flutter \
    RUSTUP_HOME=/opt/rustup \
    PATH=/opt/cargo/bin:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:$JAVA_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# The day the Ubuntu archive is frozen at, the one the desktop build
# uses. It must not be older than the base image (21 August 2026), or
# apt would have to downgrade what the image already has.
ARG APT_SNAPSHOT=20260905T000000Z

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Host tools: they fetch, unpack and link. They come from the dated
# snapshot only, so the same versions install next year; apt checks the
# snapshot's signed index against the keyring of the pinned base image,
# and every package against that index. The base image already trusts
# the certificate of the snapshot service.
#
# The snapshot service has bad minutes. apt retries each download, but
# its pauses stop at 30 seconds in all; `update --error-on=any` stops on
# an index it could not fetch, instead of carrying on with none. Both
# steps are tried again after 90 seconds, three times at most, and the
# install itself runs once, with downloads forbidden.
RUN printf '%s\n' \
      '#!/bin/bash' \
      'set -euo pipefail' \
      'retry() {' \
      '    for try in 1 2 3; do' \
      '        "$@" && return 0' \
      '        [ "$try" -lt 3 ] || break' \
      '        echo "apt-install: try $try of 3 failed: $*; next in 90 s" >&2' \
      '        sleep 90' \
      '    done' \
      '    echo "apt-install: try 3 of 3 failed: $*" >&2' \
      '    return 1' \
      '}' \
      'retry apt-get update --error-on=any' \
      'retry apt-get install -y --no-install-recommends --download-only "$@"' \
      'apt-get install -y --no-install-recommends --no-download "$@"' \
      > /usr/local/bin/apt-install \
 && chmod 0755 /usr/local/bin/apt-install \
 && echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80retries \
 && for pocket in jammy jammy-updates jammy-security; do \
      echo "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT} ${pocket} main universe"; \
    done > /etc/apt/sources.list \
 && apt-install build-essential ca-certificates curl file git python3 unzip xz-utils zip \
 && rm -rf /var/lib/apt/lists/* \
 && dpkg-query -W -f '${Package} ${Version} ${Architecture}\n' | sort > /etc/gerfaut-image-packages

# `tree-pins`: the hash of a tree of files, and the check that a folder
# holds nothing but pinned trees.
COPY --chmod=0755 tree-pins.sh /usr/local/bin/tree-pins

# Android SDK. cmdline-tools is checked by the hash of its zip, then by
# its tree. sdkmanager checks the archives it fetches against nothing but
# a SHA-1 from a catalogue served by the same host, and unpacks them
# before tree-pins can look, following any `../` in their paths. So it
# runs as an account of its own, which can write under $ANDROID_HOME and
# its own home only, and nowhere else: cmdline-tools stays root's, and
# any file it left outside those two folders stops the build (its JVM
# keeps no performance data in /tmp, for that reason). Then the
# SDK goes back to root and is checked tree by tree; the licences and
# the catalogue in .sdk/ are text sdkmanager writes for itself.
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
 && curl --proto '=https' --tlsv1.2 --retry 5 -fsSL -o /tmp/cmdline-tools.zip \
      "https://dl.google.com/android/repository/${ANDROID_CMDLINE_TOOLS}" \
 && echo "${ANDROID_CMDLINE_TOOLS_SHA256}  /tmp/cmdline-tools.zip" | sha256sum -c - \
 && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools \
 && mv /tmp/cmdline-tools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
 && rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools \
 && useradd --system --user-group --home-dir /opt/sdkmanager-home --create-home sdkmanager \
 && chown sdkmanager:sdkmanager "$ANDROID_HOME" \
 && as_sdkmanager() { runuser -u sdkmanager -- env HOME=/opt/sdkmanager-home JAVA_TOOL_OPTIONS=-XX:-UsePerfData "$@"; } \
 && (yes || true) | as_sdkmanager sdkmanager --licenses > /dev/null \
 && as_sdkmanager sdkmanager --install \
      "build-tools;${ANDROID_BUILD_TOOLS}" \
      "cmake;${ANDROID_CMAKE}" \
      $(for pin in $ANDROID_PLATFORM_TREES; do echo "platforms;${pin#*:}"; done) \
      "ndk;${ANDROID_NDK}" > /dev/null \
 && stray="$(find / -xdev -user sdkmanager ! -path "$ANDROID_HOME" ! -path "$ANDROID_HOME/*" \
      ! -path /opt/sdkmanager-home ! -path '/opt/sdkmanager-home/*' -print)" \
 && { [ -z "$stray" ] || { echo "sdkmanager wrote outside the SDK: $stray" >&2; exit 1; }; } \
 && chown -R root:root "$ANDROID_HOME" \
 && userdel --remove sdkmanager \
 && rm -rf "$ANDROID_HOME/.downloadIntermediates" "$ANDROID_HOME/.temp" \
 && tree-pins --sdkmanager "$ANDROID_HOME" \
      "${ANDROID_CMDLINE_TOOLS_TREE_SHA256}:cmdline-tools/latest" \
      "${ANDROID_NDK_TREE_SHA256}:ndk/${ANDROID_NDK}" \
      "${ANDROID_CMAKE_TREE_SHA256}:cmake/${ANDROID_CMAKE}" \
      "${ANDROID_BUILD_TOOLS_TREE_SHA256}:build-tools/${ANDROID_BUILD_TOOLS}" \
      $(for pin in $ANDROID_PLATFORM_TREES; do echo "${pin%%:*}:platforms/${pin#*:}"; done) \
      --except licenses --except .sdk

# Flutter, at the exact commit the tag points to. Left alone, the first
# `flutter` command downloads the Dart SDK and runs it, then fetches the
# packages of its own tool with `pub upgrade`, which reads no lock file,
# compiles the tool and runs it: flutter_tools names the version of each
# package but no hash, and Flutter commits no pubspec.lock for it. So
# this step does what Flutter's script would do (bin/internal/shared.sh
# and update_dart_sdk.sh), with a check before each run. The Dart SDK is
# fetched, checked against its hash, and put where the script puts it,
# with the stamp that says it is there. `pub get --enforce-lockfile`
# fetches the tool's packages against reproducible/flutter_tools.lock,
# which pins the hash of each, and the Dart SDK compiles the tool into
# the snapshot the script would write, with the stamp that says it is
# built. The first `flutter` command must then find both stamps and
# rebuild nothing, and the Flutter checkout must be as git has it. Last,
# `flutter precache` fills the cache, checked tree by tree.
#
# flutter_tools.lock follows FLUTTER_VERSION: `dart pub get` in
# packages/flutter_tools of the new release writes it.
COPY flutter_tools.lock /usr/local/share/gerfaut/flutter_tools.lock
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_ROOT" \
 && test "$(git -C "$FLUTTER_ROOT" rev-parse HEAD)" = "$FLUTTER_COMMIT" \
 && git config --global --add safe.directory "$FLUTTER_ROOT" \
 && "$FLUTTER_ROOT/bin/internal/update_engine_version.sh" \
 && engine="$(cat "$FLUTTER_ROOT/bin/cache/engine.stamp")" \
 && test "$engine" = "$(cat "$FLUTTER_ROOT/bin/internal/engine.version")" \
 && test -z "$(tr -d '[:space:]' < "$FLUTTER_ROOT/bin/cache/engine.realm")" \
 && curl --proto '=https' --tlsv1.2 --retry 5 -fsSL -o /tmp/dart-sdk.zip \
      "https://storage.googleapis.com/flutter_infra_release/flutter/${engine}/dart-sdk-linux-x64.zip" \
 && echo "${FLUTTER_DART_SDK_SHA256}  /tmp/dart-sdk.zip" | sha256sum -c - \
 && unzip -q /tmp/dart-sdk.zip -d "$FLUTTER_ROOT/bin/cache" \
 && rm /tmp/dart-sdk.zip \
 && find "$FLUTTER_ROOT/bin/cache/dart-sdk" -type d -exec chmod 755 {} + \
 && find "$FLUTTER_ROOT/bin/cache/dart-sdk" -type f -perm -u+x -exec chmod a+x,a+r {} + \
 && echo "$engine" > "$FLUTTER_ROOT/bin/cache/engine-dart-sdk.stamp" \
 && tools="$FLUTTER_ROOT/packages/flutter_tools" \
 && dart="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
 && cp /usr/local/share/gerfaut/flutter_tools.lock "$tools/pubspec.lock" \
 && (cd "$tools" && "$dart" pub get --enforce-lockfile --suppress-analytics) \
 && cmp /usr/local/share/gerfaut/flutter_tools.lock "$tools/pubspec.lock" \
 && touch "$FLUTTER_ROOT/bin/cache/.dartignore" \
 && "$dart" --verbosity=error --snapshot="$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" \
      --snapshot-kind=app-jit --packages="$tools/.dart_tool/package_config.json" \
      --no-enable-mirrors "$tools/bin/flutter_tools.dart" > /dev/null \
 && echo "${FLUTTER_COMMIT}:" > "$FLUTTER_ROOT/bin/cache/flutter_tools.stamp" \
 && built="$(stat -c '%y %i' "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" "$FLUTTER_ROOT/bin/cache/flutter_tools.stamp")" \
 && flutter config --no-analytics > /dev/null \
 && test "$(stat -c '%y %i' "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" "$FLUTTER_ROOT/bin/cache/flutter_tools.stamp")" = "$built" \
 && cmp /usr/local/share/gerfaut/flutter_tools.lock "$tools/pubspec.lock" \
 && test -z "$(git -C "$FLUTTER_ROOT" status --porcelain)" \
 && flutter precache --android --no-ios --universal \
 && flutter --version \
 && [ -n "$FLUTTER_CACHE_TREES" ] \
 && tree-pins "$FLUTTER_ROOT/bin/cache" $FLUTTER_CACHE_TREES \
      --except pkg/LICENSE.zip_old_location.md --except LICENSE.dart_sdk_archive.md \
      --except '*.stamp' --except engine.realm --except engine_stamp.json \
      --except flutter.version.json --except lockfile --except .dartignore \
      --except flutter_tools.snapshot

# Rust, without letting rustup download it. Left alone, rustup fetches
# the release manifest again after any check made here, and trusts
# whatever it gets the second time. So the manifest is fetched once,
# into /opt/rust-dist, and checked against the hash above. `rust-dist
# <target> <package>...` then fetches each package from the address that
# manifest gives and checks it against the hash it gives, and rustup
# installs from that local copy, through a file:// address. Its proxy
# points at a closed port, so it could not reach the network if it
# tried. The packages are deleted once installed.
#
# Cargokit invokes `rustup run stable cargo`, which sets
# RUSTUP_TOOLCHAIN and therefore ignores rust/rust-toolchain.toml; the
# symlink below makes `stable` resolve to the pinned toolchain so the
# two agree.
RUN printf '%s\n' \
      '#!/bin/bash' \
      'set -euo pipefail' \
      'manifest=(/opt/rust-dist/dist/channel-rust-*.toml)' \
      '[ "${#manifest[@]}" -eq 1 ] && [ -f "${manifest[0]}" ] || { echo "rust-dist: no checked manifest" >&2; exit 1; }' \
      'target="$1"' \
      'shift' \
      'for package in "$@"; do' \
      '    url=""; hash=""; inside=0' \
      '    while read -r key _ value; do' \
      '        case "$key" in' \
      '            "[pkg.$package.target.$target]") inside=1 ;;' \
      '            "["*) inside=0 ;;' \
      '            xz_url) [ "$inside" -eq 0 ] || url="${value//\"/}" ;;' \
      '            xz_hash) [ "$inside" -eq 0 ] || hash="${value//\"/}" ;;' \
      '        esac' \
      '    done < "${manifest[0]}"' \
      '    case "$url" in' \
      '        https://static.rust-lang.org/dist/*) ;;' \
      '        *) echo "rust-dist: no $package for $target in the manifest" >&2; exit 1 ;;' \
      '    esac' \
      '    [ "${#hash}" -eq 64 ] || { echo "rust-dist: no hash for $package" >&2; exit 1; }' \
      '    file="/opt/rust-dist/dist/${url#https://static.rust-lang.org/dist/}"' \
      '    mkdir -p "$(dirname "$file")"' \
      '    curl --proto =https --tlsv1.2 --retry 5 -fsSL -o "$file" "$url"' \
      '    echo "$hash  $file" | sha256sum -c -' \
      'done' \
      > /usr/local/bin/rust-dist \
 && chmod 0755 /usr/local/bin/rust-dist \
 && curl --proto '=https' --tlsv1.2 --retry 5 -fsSL -o /tmp/rustup-init \
      "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init" \
 && echo "${RUSTUP_INIT_SHA256}  /tmp/rustup-init" | sha256sum -c - \
 && mkdir -p /opt/rust-dist/dist \
 && curl --proto '=https' --tlsv1.2 --retry 5 -fsSL -o "/opt/rust-dist/dist/channel-rust-${RUST_VERSION}.toml" \
      "https://static.rust-lang.org/dist/channel-rust-${RUST_VERSION}.toml" \
 && echo "${RUST_MANIFEST_SHA256}  /opt/rust-dist/dist/channel-rust-${RUST_VERSION}.toml" | sha256sum -c - \
 && echo "${RUST_MANIFEST_SHA256}  channel-rust-${RUST_VERSION}.toml" \
      > "/opt/rust-dist/dist/channel-rust-${RUST_VERSION}.toml.sha256" \
 && rust-dist x86_64-unknown-linux-gnu rustc rust-std cargo \
 && for target in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android; do \
      rust-dist "$target" rust-std || exit 1; \
    done \
 && chmod +x /tmp/rustup-init \
 && CARGO_HOME=/opt/cargo RUSTUP_DIST_SERVER=file:///opt/rust-dist \
    all_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain "$RUST_VERSION" \
 && rm /tmp/rustup-init \
 && ln -s "$RUSTUP_HOME/toolchains/${RUST_VERSION}-x86_64-unknown-linux-gnu" \
          "$RUSTUP_HOME/toolchains/stable-x86_64-unknown-linux-gnu" \
 && CARGO_HOME=/opt/cargo RUSTUP_DIST_SERVER=file:///opt/rust-dist \
    all_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 \
    rustup target add --toolchain "$RUST_VERSION" \
      aarch64-linux-android armv7-linux-androideabi x86_64-linux-android \
 && find /opt/rust-dist/dist -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + \
 && rustup run stable rustc --version | grep -q "$RUST_VERSION"

# Where the two phases of one build keep what the first one fetched:
# reproducible/build.sh mounts a volume made for that build here, and
# removes it after (see entrypoint.sh).
ENV CARGO_HOME=/cache/cargo \
    GRADLE_USER_HOME=/cache/gradle \
    PUB_CACHE=/cache/pub \
    CARGO_INCREMENTAL=0 \
    CI=true \
    FLUTTER_SUPPRESS_ANALYTICS=true

# The recipe travels with the sources rather than with the image: what
# runs below is reproducible/entrypoint.sh of the very commit being
# built, mounted read-only under /src. The image is nothing but the
# toolchain.
WORKDIR /build
ENTRYPOINT ["bash", "/src/gerfaut-mobile/reproducible/entrypoint.sh"]
