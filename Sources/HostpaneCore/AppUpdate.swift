import Foundation

public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(parsing raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0, String(value) == part else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 {
            numbers.append(0)
        }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public struct AppRelease: Equatable, Sendable {
    public var version: AppVersion
    public var tag: String
    public var notes: String
    public var downloadURL: URL
    public var fileName: String

    public init(version: AppVersion, tag: String, notes: String, downloadURL: URL, fileName: String) {
        self.version = version
        self.tag = tag
        self.notes = notes
        self.downloadURL = downloadURL
        self.fileName = fileName
    }
}

public enum AppUpdateOffer: Equatable, Sendable {
    case upToDate(current: AppVersion, latest: AppVersion)
    case available(AppRelease)
}

public enum AppUpdateParseError: Error, Equatable {
    case malformed
    case unreadableVersion(String)
    case noAppleSiliconDiskImage
    case insecureDownloadURL
}

public enum AppUpdateFeed {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/weijing24/hostpane/releases/latest")!

    public static func offer(current: AppVersion, release: AppRelease) -> AppUpdateOffer {
        if release.version > current {
            return .available(release)
        }
        return .upToDate(current: current, latest: release.version)
    }

    public static func release(from data: Data) throws -> AppRelease {
        let payload: GitHubRelease
        do {
            payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw AppUpdateParseError.malformed
        }
        guard let version = AppVersion(parsing: payload.tagName) else {
            throw AppUpdateParseError.unreadableVersion(payload.tagName)
        }
        guard let asset = appleSiliconDiskImage(in: payload.assets, version: version) else {
            throw AppUpdateParseError.noAppleSiliconDiskImage
        }
        guard let url = URL(string: asset.browserDownloadURL), url.scheme == "https" else {
            throw AppUpdateParseError.insecureDownloadURL
        }
        let notes = payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AppRelease(
            version: version,
            tag: payload.tagName,
            notes: notes,
            downloadURL: url,
            fileName: asset.name
        )
    }

    fileprivate static func appleSiliconDiskImage(in assets: [GitHubAsset], version: AppVersion) -> GitHubAsset? {
        let exact = "Hostpane-\(version.description)-arm64.dmg"
        if let match = assets.first(where: { $0.name == exact }) {
            return match
        }
        return assets.first { $0.name.hasSuffix("-arm64.dmg") }
    }
}

private struct GitHubRelease: Decodable {
    var tagName: String
    var body: String?
    var assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

private struct GitHubAsset: Decodable {
    var name: String
    var browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
