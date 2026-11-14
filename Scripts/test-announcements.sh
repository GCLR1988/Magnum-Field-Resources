#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/magnum-announcement-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources/Announcements" "$test_dir/Tests/AnnouncementsTests"
cp "$repo_dir/MagnumFieldTraining/Models/Announcement.swift" "$test_dir/Sources/Announcements/"
cp "$repo_dir/Tests/AnnouncementTests.swift" "$test_dir/Tests/AnnouncementsTests/"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Announcements",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Announcements"),
        .testTarget(name: "AnnouncementsTests", dependencies: ["Announcements"])
    ],
    swiftLanguageModes: [.v5]
)
SWIFT
export CLANG_MODULE_CACHE_PATH="$test_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$test_dir/module-cache"
swift test --disable-sandbox --cache-path "$test_dir/cache" --package-path "$test_dir"
