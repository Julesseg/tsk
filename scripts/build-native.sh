#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$repo_root/Native/Bridge/Cargo.toml"
if [[ "${1:-host}" == host ]]; then
    cargo build --locked --release --manifest-path "$manifest"
    exit
fi
if [[ "${1:-}" == simulator ]]; then
    rustup target add aarch64-apple-ios-sim
    cargo build --locked --release --manifest-path "$manifest" --target aarch64-apple-ios-sim
    mkdir -p "$repo_root/Native/Artifacts/iphonesimulator"
    cp "$repo_root/Native/Bridge/target/aarch64-apple-ios-sim/release/libtsk_taskchampion.a" "$repo_root/Native/Artifacts/iphonesimulator/"
    exit
fi
if [[ "${1:-}" != apple ]]; then
    echo 'Usage: build-native.sh [host|apple|simulator]' >&2
    exit 2
fi
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    cargo build --locked --release --manifest-path "$manifest" --target "$target"
done
mkdir -p "$repo_root/Native/Artifacts/iphoneos" "$repo_root/Native/Artifacts/iphonesimulator"
cp "$repo_root/Native/Bridge/target/aarch64-apple-ios/release/libtsk_taskchampion.a" "$repo_root/Native/Artifacts/iphoneos/"
lipo -create "$repo_root/Native/Bridge/target/aarch64-apple-ios-sim/release/libtsk_taskchampion.a" "$repo_root/Native/Bridge/target/x86_64-apple-ios/release/libtsk_taskchampion.a" -output "$repo_root/Native/Artifacts/iphonesimulator/libtsk_taskchampion.a"
