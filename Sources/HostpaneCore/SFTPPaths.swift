import Foundation
import Traversio

public enum SFTPEntryKind: Equatable, Sendable {
    case directory
    case file
    case symbolicLink
    case other

    public var systemImage: String {
        switch self {
        case .directory: return "folder.fill"
        case .file: return "doc"
        case .symbolicLink: return "link"
        case .other: return "questionmark.square"
        }
    }
}

public struct SFTPListingItem: Identifiable, Equatable, Sendable {
    public var name: String
    public var path: String
    public var kind: SFTPEntryKind
    public var size: UInt64?
    public var modified: Date?
    public var permissions: UInt32?

    public var id: String { path }

    public init(
        name: String,
        path: String,
        kind: SFTPEntryKind,
        size: UInt64? = nil,
        modified: Date? = nil,
        permissions: UInt32? = nil
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.modified = modified
        self.permissions = permissions
    }
}

public enum SFTPPaths {
    public static func join(_ base: String, _ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName == "." {
            return normalize(base)
        }
        if trimmedName == ".." {
            return parent(base)
        }
        if trimmedName.hasPrefix("/") {
            return normalize(trimmedName)
        }
        let root = normalize(base)
        if root == "/" {
            return "/" + trimmedName
        }
        return root + "/" + trimmedName
    }

    public static func parent(_ path: String) -> String {
        let normalized = normalize(path)
        if normalized == "/" { return "/" }
        guard let slash = normalized.lastIndex(of: "/") else { return "/" }
        if slash == normalized.startIndex {
            return "/"
        }
        return String(normalized[..<slash])
    }

    public static func normalize(_ path: String) -> String {
        var parts: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".":
                continue
            case "..":
                if !parts.isEmpty { parts.removeLast() }
            default:
                parts.append(String(part))
            }
        }
        if parts.isEmpty { return "/" }
        return "/" + parts.joined(separator: "/")
    }

    public static func components(_ path: String) -> [String] {
        Array(normalize(path).split(separator: "/").map(String.init))
    }

    public static func kind(permissions: UInt32?, longName: String) -> SFTPEntryKind {
        if let permissions {
            switch permissions & 0o170000 {
            case 0o040000: return .directory
            case 0o100000: return .file
            case 0o120000: return .symbolicLink
            default: break
            }
        }
        switch longName.first {
        case "d": return .directory
        case "l": return .symbolicLink
        case "-": return .file
        default: return .other
        }
    }

    public static func item(
        from entry: SSHSFTPNameEntry,
        directory: String,
        includeHidden: Bool
    ) -> SFTPListingItem? {
        let name = entry.filename
        if name == "." || name == ".." {
            guard includeHidden else { return nil }
            let path = name == ".." ? parent(directory) : normalize(directory)
            return SFTPListingItem(
                name: name,
                path: path,
                kind: .directory,
                size: entry.attributes.size,
                modified: date(from: entry.attributes.modificationTime),
                permissions: entry.attributes.permissions
            )
        }
        if !includeHidden, name.hasPrefix(".") {
            return nil
        }
        return SFTPListingItem(
            name: name,
            path: join(directory, name),
            kind: kind(permissions: entry.attributes.permissions, longName: entry.longName),
            size: entry.attributes.size,
            modified: date(from: entry.attributes.modificationTime),
            permissions: entry.attributes.permissions
        )
    }

    public static func isHiddenName(_ name: String) -> Bool {
        name.hasPrefix(".")
    }

    private static func date(from seconds: UInt32?) -> Date? {
        guard let seconds else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    public static func isProbablyText(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        let text: Set<String> = [
            "txt", "md", "markdown", "json", "yml", "yaml", "xml", "plist",
            "csv", "log", "conf", "cfg", "ini", "env", "sh", "bash", "zsh",
            "py", "rb", "js", "ts", "swift", "c", "h", "cc", "cpp", "go",
            "rs", "toml", "html", "css", "sql", "service", "timer"
        ]
        return text.contains(ext) || ext.isEmpty
    }
}
