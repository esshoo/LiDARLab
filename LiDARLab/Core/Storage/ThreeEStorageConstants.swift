import Foundation

enum ThreeEStorageConstants {
    static let displayName = "3ELiDAR"
    static let bundleIdentifier = "com.essam.3E.LiDARLab"
    static let appKey = "lidar"
    static let urlScheme = "lidar"
    static let appRelativePath = "Apps/LiDARLab"
    static let futureAppGroupIdentifier = "group.com.essam.3e"

    static let bookmarkDefaultsKey = "com.essam.3E.LiDARLab.threeEFolderBookmark"
    static let registryRelativePath = "System/registry.json"
    static let registrySchemaVersion = 1

    static let appSubdirectories = [
        "Captures",
        "Rooms",
        "Recordings",
        "Exports",
        "Projects"
    ]

    static let sharedSubdirectories = [
        "Shared/Inbox",
        "Shared/Outbox",
        "Shared/Projects",
        "Shared/Media",
        "System"
    ]

    static let registryEntry: [String: String] = [
        "appKey": appKey,
        "displayName": displayName,
        "bundleIdentifier": bundleIdentifier,
        "urlScheme": urlScheme,
        "folder": appRelativePath
    ]
}
