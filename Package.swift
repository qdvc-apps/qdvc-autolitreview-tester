// swift-tools-version: 5.10
//
// QDVC Auto Lit Review Tester for macOS — a native SwiftUI app for testers of
// an automated literature review tool. It opens a workspace folder of test
// runs (one folder per test, named like ABCD-123; see docs/FILE_FORMAT.md),
// checks that every run has all its artifacts and that each BibTeX file holds
// as many references as its file name says, lists the research questions and
// reference counts, exports them as CSV or HTML, and sets up new test folders.
//
// Build:   swift build            (or open this folder in Xcode)
// Test:    swift test
// Bundle:  scripts/build-app.sh   (ad-hoc signed .app, no Apple account needed)

import PackageDescription

var products: [Product] = [
    .library(name: "AutoLitReviewCore", targets: ["AutoLitReviewCore"]),
]
var targets: [Target] = [
    // Pure model layer: Foundation only, no AppKit/SwiftUI, unit-testable.
    .target(name: "AutoLitReviewCore"),
    .testTarget(
        name: "AutoLitReviewCoreTests",
        dependencies: ["AutoLitReviewCore"]
    ),
]

#if os(macOS)
// The SwiftUI/AppKit front-end. Declared on macOS only, so the core and its
// tests also build with a Linux Swift toolchain (docs/MAINTENANCE.md §4).
products.insert(.executable(name: "QDVCAutoLitReviewTester", targets: ["QDVCAutoLitReviewTester"]), at: 0)
targets.insert(.executableTarget(name: "QDVCAutoLitReviewTester", dependencies: ["AutoLitReviewCore"]), at: 1)
#endif

let package = Package(
    name: "QDVCAutoLitReviewTester",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
