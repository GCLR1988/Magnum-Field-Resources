#!/bin/sh
set -eu
# Optional arguments exercise the supplied workbooks without copying private data into the repository.
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/magnum-spreadsheet-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources/SpreadsheetReader" "$test_dir/Tests/SpreadsheetReaderTests"
cp "$repo_dir/MagnumFieldTraining/Sync/ExcelWorkbook.swift" "$test_dir/Sources/SpreadsheetReader/"
cp "$repo_dir/MagnumFieldTraining/Models/SpreadsheetResources.swift" "$test_dir/Sources/SpreadsheetReader/"
cp "$repo_dir/Tests/SpreadsheetResourcesTests.swift" "$test_dir/Tests/SpreadsheetReaderTests/"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SpreadsheetReader",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SpreadsheetReader"),
        .testTarget(name: "SpreadsheetReaderTests", dependencies: ["SpreadsheetReader"])
    ],
    swiftLanguageModes: [.v5]
)
SWIFT
if [ "$#" -ge 2 ]; then
    export MAGNUM_DIRECTORY_FIXTURE="$1"
    export MAGNUM_LINKS_FIXTURE="$2"
fi
swift test --package-path "$test_dir"
