#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/magnum-saved-form-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources/FormLibrary" "$test_dir/Tests/FormLibraryTests"
cp "$repo_dir/MagnumFieldTraining/Models/SavedFormStore.swift" "$test_dir/Sources/FormLibrary/"
cp "$repo_dir/MagnumFieldTraining/Models/FormFieldSupport.swift" "$test_dir/Sources/FormLibrary/"
cp "$repo_dir/MagnumFieldTraining/Models/PDFContentSearch.swift" "$test_dir/Sources/FormLibrary/"
cp "$repo_dir/MagnumFieldTraining/Models/AppLanguage.swift" "$test_dir/Sources/FormLibrary/"
cp "$repo_dir/MagnumFieldTraining/Models/Program.swift" "$test_dir/Sources/FormLibrary/"
cp "$repo_dir/MagnumFieldTraining/Sync/DropboxModels.swift" "$test_dir/Sources/FormLibrary/"
cp "$repo_dir/Tests/SavedFormTests.swift" "$test_dir/Tests/FormLibraryTests/"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "FormLibrary",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FormLibrary"),
        .testTarget(name: "FormLibraryTests", dependencies: ["FormLibrary"])
    ],
    swiftLanguageModes: [.v5]
)
SWIFT
export CLANG_MODULE_CACHE_PATH="$test_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$test_dir/module-cache"
swift test --disable-sandbox --cache-path "$test_dir/cache" --package-path "$test_dir"
