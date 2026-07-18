import ProjectDescription

// Somnia — Tuist manifest.
//
// The Xcode project is generated from this file (`tuist generate`) and is NOT
// committed, so no personal Team ID or signing config ever lands in the repo.
// Your own signing lives in Local.xcconfig (git-ignored); copy the .example to
// start. Run without one to build for the Simulator.

let settings: Settings = .settings(
    base: [
        "SWIFT_VERSION": "5.0",
        "IPHONEOS_DEPLOYMENT_TARGET": "26.4",
        "GENERATE_INFOPLIST_FILE": "YES",
        "CODE_SIGN_ENTITLEMENTS": "Somnia/Somnia.entitlements",
        "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "1.0",
        // Sensor + capability usage strings (merged into the generated Info.plist).
        "INFOPLIST_KEY_NSMicrophoneUsageDescription":
            "Scenes listen to the sound around you and react to it. Audio is processed live on device and never recorded or sent anywhere.",
        "INFOPLIST_KEY_NSMotionUsageDescription": "Used to sense movement and drive the dream.",
        "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": "Used to sense where you are and pick a fitting dream.",
        "INFOPLIST_KEY_NSHealthShareUsageDescription": "Optional: heart rate and HRV shape the dream's energy.",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone":
            "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    ],
    // Personal signing overrides live here, uncommitted. Missing file is fine.
    configurations: [
        .debug(name: "Debug", xcconfig: "Local.xcconfig"),
        .release(name: "Release", xcconfig: "Local.xcconfig"),
    ]
)

let project = Project(
    name: "Somnia",
    packages: [
        .remote(url: "https://github.com/weichsel/ZIPFoundation",
                requirement: .upToNextMajor(from: "0.9.0")),
    ],
    settings: settings,
    targets: [
        .target(
            name: "Somnia",
            destinations: .iOS,
            product: .app,
            bundleId: "$(PRODUCT_BUNDLE_IDENTIFIER)",
            infoPlist: .file(path: "Info.plist"),
            // Buildable folder: the whole source tree is referenced as a folder, so
            // new files are picked up without regenerating the project.
            sources: ["Somnia/**"],
            resources: ["Somnia/Resources/Assets.xcassets"],
            entitlements: "Somnia/Somnia.entitlements",
            dependencies: [
                .package(product: "ZIPFoundation"),
            ]
        ),
    ]
)
