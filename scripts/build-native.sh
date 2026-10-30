#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$repo_root/Native/Bridge/Cargo.toml"
target_dir="${CARGO_TARGET_DIR:-$repo_root/Native/Bridge/target}"
if [[ "${1:-host}" == host ]]; then
    cargo build --locked --release --manifest-path "$manifest"
    exit
fi
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-26.0}"
if [[ "${1:-}" == device ]]; then
    rustup target add aarch64-apple-ios
    cargo build --locked --release --manifest-path "$manifest" --target aarch64-apple-ios
    mkdir -p "$repo_root/Native/Artifacts/iphoneos"
    cp "$target_dir/aarch64-apple-ios/release/libtsk_taskchampion.a" "$repo_root/Native/Artifacts/iphoneos/"
    exit
fi
if [[ "${1:-}" == simulator ]]; then
    rustup target add aarch64-apple-ios-sim
    cargo build --locked --release --manifest-path "$manifest" --target aarch64-apple-ios-sim
    mkdir -p "$repo_root/Native/Artifacts/iphonesimulator"
    cp "$target_dir/aarch64-apple-ios-sim/release/libtsk_taskchampion.a" "$repo_root/Native/Artifacts/iphonesimulator/"
    exit
fi
if [[ "${1:-}" != apple ]]; then
    echo 'Usage: build-native.sh [host|apple|simulator|device]' >&2
    exit 2
fi
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    cargo build --locked --release --manifest-path "$manifest" --target "$target"
done
mkdir -p "$repo_root/Native/Artifacts/iphoneos" "$repo_root/Native/Artifacts/iphonesimulator"
cp "$target_dir/aarch64-apple-ios/release/libtsk_taskchampion.a" "$repo_root/Native/Artifacts/iphoneos/"
lipo -create "$target_dir/aarch64-apple-ios-sim/release/libtsk_taskchampion.a" "$target_dir/x86_64-apple-ios/release/libtsk_taskchampion.a" -output "$repo_root/Native/Artifacts/iphonesimulator/libtsk_taskchampion.a"
