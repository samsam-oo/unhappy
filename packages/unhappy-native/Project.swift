import ProjectDescription

let project = Project(
    name: "UnhappyNative",
    targets: [
        .target(
            name: "UnhappyNative",
            destinations: .iOS,
            product: .app,
            bundleId: "im.unhappy.app",
            buildableFolders: [
                "App/Sources",
                "App/Resources",
            ],
            dependencies: [
                .target(name: "FeatureHome"),
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:native-bootstrap",
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
                .target(name: "FeatureSessions"),
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
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:sessions",
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
            ],
            metadata: .metadata(tags: [
                "tag:team:mobile",
                "tag:feature:settings",
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
            dependencies: [],
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
