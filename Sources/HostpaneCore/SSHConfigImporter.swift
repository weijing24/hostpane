import Foundation

public struct SSHConfigImporter: Sendable {
    public init() {}

    public func lookup(
        alias: String,
        configURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh/config")
    ) throws -> HostRecord? {
        let needle = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return try importHosts(configURL: configURL).first {
            $0.name.caseInsensitiveCompare(needle) == .orderedSame
                || $0.hostname.caseInsensitiveCompare(needle) == .orderedSame
        }
    }

    /// Username to copy from `~/.ssh/config` when the editor still has a placeholder.
    /// Does not replace a username the user already typed.
    public static func usernameToApply(
        current: String,
        fromConfig: String,
        macUsername: String,
        lastAutoFilled: String? = nil
    ) -> String? {
        let current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromConfig = fromConfig.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fromConfig.isEmpty, fromConfig != current else { return nil }
        let currentIsPlaceholder = current.isEmpty
            || current == macUsername
            || current == lastAutoFilled
        return currentIsPlaceholder ? fromConfig : nil
    }

    /// Resolve an SSH config Host alias to its HostName for the TCP connection.
    /// Username, port, and auth stay as saved in the host book.
    public func resolved(_ host: HostRecord) -> HostRecord {
        var resolved = host
        let aliases = [host.name, host.hostname]
        for alias in aliases {
            guard let match = try? lookup(alias: alias) else { continue }
            let savedIsAlias = host.hostname.caseInsensitiveCompare(match.name) == .orderedSame
            let configHasDistinctHostName = match.hostname.caseInsensitiveCompare(match.name) != .orderedSame
            if savedIsAlias && configHasDistinctHostName {
                resolved.hostname = match.hostname
            }
            return resolved
        }
        return resolved
    }

    public func importHosts(
        configURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh/config")
    ) throws -> [HostRecord] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var visited = Set<String>()
        let blocks = try parseFile(configURL, home: home, visited: &visited)
        let defaults = mergedKeywords(blocks.filter { $0.patterns == ["*"] })
        var hosts: [HostRecord] = []
        var seen = Set<String>()

        for block in blocks {
            guard block.patterns.count == 1, let pattern = block.patterns.first else { continue }
            if pattern.contains("*") || pattern.contains("?") { continue }
            let key = "\(pattern)|\(block.keywords["user"] ?? defaults["user"] ?? "")"
            if seen.contains(key) { continue }
            seen.insert(key)

            var keywords = defaults
            for (name, value) in block.keywords {
                keywords[name] = value
            }

            let hostname = keywords["hostname"] ?? pattern
            let username = keywords["user"] ?? NSUserName()
            let port = Int(keywords["port"] ?? "22") ?? 22
            let identity = keywords["identityfile"].map { expandPath($0, home: home) }
            let auth: AuthKind = identity == nil ? .agent : .privateKey
            hosts.append(
                HostRecord(
                    name: pattern,
                    hostname: hostname,
                    port: port,
                    username: username,
                    authKind: auth,
                    privateKeyPath: identity
                )
            )
        }
        return hosts
    }

    private struct Block {
        var patterns: [String]
        var keywords: [String: String]
    }

    private func parseFile(
        _ url: URL,
        home: URL,
        visited: inout Set<String>
    ) throws -> [Block] {
        let path = url.standardizedFileURL.path
        if visited.contains(path) { return [] }
        visited.insert(path)
        guard FileManager.default.isReadableFile(atPath: path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseText(text, relativeTo: url.deletingLastPathComponent(), home: home, visited: &visited)
    }

    private func parseText(
        _ text: String,
        relativeTo directory: URL,
        home: URL,
        visited: inout Set<String>
    ) throws -> [Block] {
        var blocks: [Block] = []
        var current: Block?

        func flush() {
            if let current {
                blocks.append(current)
            }
            current = nil
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash])
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let parts = splitConfigTokens(line)
            guard let keyword = parts.first?.lowercased() else { continue }
            let args = Array(parts.dropFirst())
            if keyword == "include" {
                for pattern in args {
                    let expanded = expandPath(pattern, home: home, relativeTo: directory)
                    for url in globFiles(expanded) {
                        blocks.append(contentsOf: try parseFile(url, home: home, visited: &visited))
                    }
                }
                continue
            }
            if keyword == "host" {
                flush()
                current = Block(patterns: args, keywords: [:])
                continue
            }
            guard current != nil, let value = args.first else { continue }
            if current?.keywords[keyword] == nil {
                current?.keywords[keyword] = value
            }
        }
        flush()
        return blocks
    }

    private func mergedKeywords(_ blocks: [Block]) -> [String: String] {
        var result: [String: String] = [:]
        for block in blocks {
            for (key, value) in block.keywords where result[key] == nil {
                result[key] = value
            }
        }
        return result
    }

    private func expandPath(_ path: String, home: URL, relativeTo: URL? = nil) -> String {
        var expanded = path
        if expanded.hasPrefix("~/") {
            expanded = home.appendingPathComponent(String(expanded.dropFirst(2))).path
        } else if expanded == "~" {
            expanded = home.path
        } else if expanded.hasPrefix("/") == false, let relativeTo {
            expanded = relativeTo.appendingPathComponent(expanded).path
        }
        return (expanded as NSString).standardizingPath
    }

    private func globFiles(_ pattern: String) -> [URL] {
        let url = URL(fileURLWithPath: pattern)
        if pattern.contains("*") || pattern.contains("?") {
            let directory = url.deletingLastPathComponent()
            let namePattern = url.lastPathComponent
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
                return []
            }
            return items.compactMap { item in
                guard fnmatch(namePattern, item) else { return nil }
                return directory.appendingPathComponent(item)
            }.sorted { $0.path < $1.path }
        }
        if FileManager.default.fileExists(atPath: pattern) {
            return [url]
        }
        return []
    }

    private func fnmatch(_ pattern: String, _ name: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return name.range(of: "^\(escaped)$", options: .regularExpression) != nil
    }

    private func splitConfigTokens(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for character in line {
            if let quoteCharacter = quote {
                if character == quoteCharacter {
                    tokens.append(current)
                    current = ""
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
