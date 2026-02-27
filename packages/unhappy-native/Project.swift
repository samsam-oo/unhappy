import ProjectDescription
import Foundation

let projectBaseSettings: SettingsDictionary = {
    let defaultDevelopmentTeam = "Q23JLSJCCV"
    var base: SettingsDictionary = [
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "DEVELOPMENT_TEAM": .string(defaultDevelopmentTeam),
    ]

    if let developmentTeam = ProcessInfo.processInfo.environment["UNHAPPY_DEVELOPMENT_TEAM"],
       !developmentTeam.isEmpty {
        base["DEVELOPMENT_TEAM"] = .string(developmentTeam)
    }

    return base
}()

let project = Project(
    name: "UnhappyNative",
    settings: .settings(
        base: projectBaseSettings
    ),
    targets: [
        .target(
            name: "UnhappyNative",
            destinations: .iOS,
            product: .app,
            bundleId: "im.unhappy.app",
            infoPlist: .extendingDefault(with: [
                "NSCameraUsageDescription": .string("Scan terminal QR codes to approve secure device connections."),
                "UILaunchStoryboardName": .string("LaunchScreen"),
                "NSSupportsLiveActivities": .boolean(true),
            ]),
            buildableFolders: [
                "App/Sources",
                "App/Resources",
            ],
            dependencies: [
                .target(name: "FeatureHome"),
                .target(name: "FeatureInbox"),
                .target(name: "FeatureMachine"),
                .target(name: "FeatureNewSession"),
                .target(name: "UnhappyLiveActivitiesExtension"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:native-bootstrap",
                "tag:layer:app",
            ])
        ),
        .target(
            name: "UnhappyLiveActivitiesExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "im.unhappy.app.live-activities",
            infoPlist: .extendingDefault(with: [
                "NSExtension": .dictionary([
                    "NSExtensionPointIdentifier": .string("com.apple.widgetkit-extension")
                ])
            ]),
            buildableFolders: [
                "App/LiveActivities/Sources",
                "App/LiveActivities/Resources",
            ],
            dependencies: [
                .target(name: "CoreKit"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:live-activity",
                "tag:layer:app",
            ])
        ),
        .target(
            name: "FeatureHome",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "im.unhappy.app.feature.home",
            buildableFolders: [
                "Modules/FeatureHome/Sources",
            ],
            dependencies: [
                .target(name: "CoreKit"),
                .target(name: "FeatureInbox"),
                .target(name: "FeatureMachine"),
                .target(name: "FeatureNewSession"),
                .target(name: "FeatureSessions"),
                .target(name: "FeatureSessionTools"),
                .target(name: "FeatureSettings"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:home",
                "tag:layer:feature",
            ])
        ),
        .target(
            name: "FeatureSessions",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "im.unhappy.app.feature.sessions",
            buildableFolders: [
                "Modules/FeatureSessions/Sources",
            ],
            dependencies: [
                .target(name: "CoreKit"),
                .target(name: "FeatureNewSession"),
                .target(name: "FeatureSessionTools"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:sessions",
                "tag:layer:feature",
            ])
        ),
        .target(
            name: "FeatureSessionTools",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "im.unhappy.app.feature.session-tools",
            buildableFolders: [
                "Modules/FeatureSessionTools/Sources",
            ],
            dependencies: [
                .target(name: "CoreKit"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:session-tools",
                "tag:layer:feature",
            ])
        ),
        .target(
            name: "FeatureSettings",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "im.unhappy.app.feature.settings",
            buildableFolders: [
                "Modules/FeatureSettings/Sources",
            ],
            dependencies: [
                .target(name: "CoreKit"),
                .target(name: "FeatureMachine"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:settings",
                "tag:layer:feature",
            ])
        ),
        .target(
            name: "FeatureInbox",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "im.unhappy.app.feature.inbox",
            buildableFolders: [
                "Modules/FeatureInbox/Sources",
            ],
            dependencies: [
                .target(name: "CoreKit"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:inbox",
                "tag:layer:feature",
            ])
        ),
        .target(
            name: "FeatureMachine",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "im.unhappy.app.feature.machine",
            buildableFolders: [
                "Modules/FeatureMachine/Sources",
            ],
            dependencies: [
                .target(name: "CoreKit"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:machine",
                "tag:layer:feature",
            ])
        ),
        .target(
            name: "FeatureNewSession",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "im.unhappy.app.feature.new-session",
            buildableFolders: [
                "Modules/FeatureNewSession/Sources",
            ],
            dependencies: [
                .target(name: "CoreKit"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:new-session",
                "tag:layer:feature",
            ])
        ),
        .target(
            name: "CoreKit",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "im.unhappy.app.core",
            buildableFolders: [
                "Modules/CoreKit/Sources",
            ],
            dependencies: [
                .external(name: "SocketIO"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:core",
                "tag:layer:core",
            ])
        ),
        .target(
            name: "FeatureHomeTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "im.unhappy.app.feature.home.tests",
            infoPlist: .default,
            buildableFolders: [
                "Modules/FeatureHome/Tests",
            ],
            dependencies: [
                .target(name: "FeatureHome"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:home",
                "tag:layer:test",
            ])
        ),
        .target(
            name: "FeatureSessionsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "im.unhappy.app.feature.sessions.tests",
            infoPlist: .default,
            buildableFolders: [
                "Modules/FeatureSessions/Tests",
            ],
            dependencies: [
                .target(name: "FeatureSessions"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:sessions",
                "tag:layer:test",
            ])
        ),
        .target(
            name: "FeatureSessionToolsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "im.unhappy.app.feature.session-tools.tests",
            infoPlist: .default,
            buildableFolders: [
                "Modules/FeatureSessionTools/Tests",
            ],
            dependencies: [
                .target(name: "FeatureSessionTools"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:session-tools",
                "tag:layer:test",
            ])
        ),
        .target(
            name: "FeatureSettingsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "im.unhappy.app.feature.settings.tests",
            infoPlist: .default,
            buildableFolders: [
                "Modules/FeatureSettings/Tests",
            ],
            dependencies: [
                .target(name: "FeatureSettings"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:settings",
                "tag:layer:test",
            ])
        ),
        .target(
            name: "FeatureInboxTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "im.unhappy.app.feature.inbox.tests",
            infoPlist: .default,
            buildableFolders: [
                "Modules/FeatureInbox/Tests",
            ],
            dependencies: [
                .target(name: "FeatureInbox"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:inbox",
                "tag:layer:test",
            ])
        ),
        .target(
            name: "FeatureMachineTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "im.unhappy.app.feature.machine.tests",
            infoPlist: .default,
            buildableFolders: [
                "Modules/FeatureMachine/Tests",
            ],
            dependencies: [
                .target(name: "FeatureMachine"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:machine",
                "tag:layer:test",
            ])
        ),
        .target(
            name: "FeatureNewSessionTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "im.unhappy.app.feature.new-session.tests",
            infoPlist: .default,
            buildableFolders: [
                "Modules/FeatureNewSession/Tests",
            ],
            dependencies: [
                .target(name: "FeatureNewSession"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:new-session",
                "tag:layer:test",
            ])
        ),
        .target(
            name: "CoreKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "im.unhappy.app.core.tests",
            infoPlist: .default,
            buildableFolders: [
                "Modules/CoreKit/Tests",
            ],
            dependencies: [
                .target(name: "CoreKit"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:core",
                "tag:layer:test",
            ])
        ),
    ]
)
