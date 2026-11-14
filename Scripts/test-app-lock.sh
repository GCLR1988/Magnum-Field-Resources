#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/magnum-app-lock-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources/AppLock" "$test_dir/Tests/AppLockTests"
# Compile the production session without its iOS window bridge. Authentication
# is injected by the tests, so no real credentials or biometric prompts are used.
{
    printf '%s\n' 'import SwiftUI' 'import LocalAuthentication' 'import Observation'
    sed -n '/^@MainActor$/,/^private struct AppLockScreen/ { /^private struct AppLockScreen/d; p; }' \
        "$repo_dir/MagnumFieldTraining/Views/AppLockView.swift"
} > "$test_dir/Sources/AppLock/AppLockSession.swift"
cp "$repo_dir/MagnumFieldTraining/Models/AppLanguage.swift" "$test_dir/Sources/AppLock/"
cp "$repo_dir/Tests/AppLockTests.swift" "$test_dir/Tests/AppLockTests/"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "AppLock",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AppLock"),
        .testTarget(name: "AppLockTests", dependencies: ["AppLock"])
    ],
    swiftLanguageModes: [.v5]
)
SWIFT
export CLANG_MODULE_CACHE_PATH="$test_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$test_dir/module-cache"
swift test --disable-sandbox --cache-path "$test_dir/cache" --package-path "$test_dir"
