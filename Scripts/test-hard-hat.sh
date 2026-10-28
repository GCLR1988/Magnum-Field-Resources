#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/magnum-hard-hat-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources/HardHatHop" "$test_dir/Tests/HardHatHopTests"
cp "$repo_dir/MagnumFieldTraining/Models/HardHatGame.swift" "$test_dir/Sources/HardHatHop/"
cp "$repo_dir/MagnumFieldTraining/Models/HardHatScores.swift" "$test_dir/Sources/HardHatHop/"
cp "$repo_dir/Tests/HardHatGameTests.swift" "$test_dir/Tests/HardHatHopTests/"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "HardHatHop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HardHatHop"),
        .testTarget(name: "HardHatHopTests", dependencies: ["HardHatHop"])
    ],
    swiftLanguageModes: [.v5]
)
SWIFT
export CLANG_MODULE_CACHE_PATH="$test_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$test_dir/module-cache"
swift test --disable-sandbox --cache-path "$test_dir/cache" --package-path "$test_dir"
