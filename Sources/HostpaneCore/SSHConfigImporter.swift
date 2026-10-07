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
    /// An empty 经由 field takes ProxyJump from the matching config Host.
    /// `none` stays a direct connection. Username, port, and auth stay as saved.
    public func resolved(
        _ host: HostRecord,
        configURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh/config")
    ) -> HostRecord {
        var resolved = host
        if host.suppressesProxyJump {
            resolved.proxyJump = nil
        }
        let aliases = [host.name, host.hostname]
        for alias in aliases {
            guard let match = try? lookup(alias: alias, configURL: configURL) else { continue }
            let savedIsAlias = host.hostname.caseInsensitiveCompare(match.name) == .orderedSame
            let configHasDistinctHostName = match.hostname.caseInsensitiveCompare(match.name) != .orderedSame
            if savedIsAlias && configHasDistinctHostName {
                resolved.hostname = match.hostname
            }
            if !host.suppressesProxyJump, HostRecord.normalizedProxyJump(host.proxyJump) == nil {
                resolved.proxyJump = match.proxyJump
            }
            return resolved
        }
        return resolved
    }

    /// Expand a ProxyJump value into TCP hops, first hop first.
    /// Each hop's Host alias is replaced with that Host's HostName, User, Port, and IdentityFile.
    /// A hop that itself has ProxyJump is inserted in front of it. `none` yields an empty chain.
    public func resolveProxyJumpChain(
        _ raw: String?,
        configURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh/config")
    ) -> [ResolvedProxyHop] {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("none") == .orderedSame {
            return []
        }
        let hosts = (try? importHosts(configURL: configURL)) ?? []
        var visited = Set<String>()
        return expandProxyJump(trimmed, hosts: hosts, visited: &visited)
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
                    privateKeyPath: identity,
                    proxyJump: storedProxyJump(keywords["proxyjump"])
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
            if keyword == "proxyjump" {
                guard current != nil, current?.keywords[keyword] == nil else { continue }
                let value = args.joined(separator: " ")
                if !value.isEmpty {
                    current?.keywords[keyword] = value
                }
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

    /// One hop after alias expansion. `host` is the TCP address, not the Host alias.
    public struct ResolvedProxyHop: Equatable, Sendable {
        public var host: String
        public var port: Int
        public var username: String
        public var identityFile: String?

        public init(host: String, port: Int, username: String, identityFile: String? = nil) {
            self.host = host
            self.port = port
            self.username = username
            self.identityFile = identityFile
        }
    }

    private struct ProxyJumpToken {
        var username: String?
        var host: String
        var port: Int?
    }

    private func storedProxyJump(_ raw: String?) -> String? {
        guard let trimmed = HostRecord.normalizedProxyJump(raw) else { return nil }
        if trimmed.caseInsensitiveCompare("none") == .orderedSame { return nil }
        return trimmed
    }

    private func expandProxyJump(
        _ raw: String,
        hosts: [HostRecord],
        visited: inout Set<String>
    ) -> [ResolvedProxyHop] {
        var chain: [ResolvedProxyHop] = []
        for token in parseProxyJump(raw) {
            chain.append(contentsOf: expandProxyHop(token, hosts: hosts, visited: &visited))
        }
        return chain
    }

    private func expandProxyHop(
        _ token: ProxyJumpToken,
        hosts: [HostRecord],
        visited: inout Set<String>
    ) -> [ResolvedProxyHop] {
        let aliasKey = token.host.lowercased()
        if visited.contains(aliasKey) { return [] }
        visited.insert(aliasKey)

        guard let match = hosts.first(where: { $0.name.caseInsensitiveCompare(token.host) == .orderedSame }) else {
            return [
                ResolvedProxyHop(
                    host: token.host,
                    port: token.port ?? 22,
                    username: token.username ?? NSUserName(),
                    identityFile: nil
                )
            ]
        }
        visited.insert(match.name.lowercased())

        var prefix: [ResolvedProxyHop] = []
        if let nested = match.proxyJump {
            prefix = expandProxyJump(nested, hosts: hosts, visited: &visited)
        }
        let hop = ResolvedProxyHop(
            host: match.hostname,
            port: token.port ?? match.port,
            username: token.username ?? match.username,
            identityFile: match.privateKeyPath
        )
        return prefix + [hop]
    }

    private func parseProxyJump(_ raw: String) -> [ProxyJumpToken] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("none") == .orderedSame {
            return []
        }
        return splitProxyJumpHops(trimmed).compactMap(parseProxyJumpToken)
    }

    private func splitProxyJumpHops(_ raw: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var brackets = 0
        for character in raw {
            if character == "[" { brackets += 1 }
            if character == "]" { brackets = max(0, brackets - 1) }
            if character == "," && brackets == 0 {
                let token = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty { parts.append(token) }
                current = ""
                continue
            }
            current.append(character)
        }
        let token = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty { parts.append(token) }
        return parts
    }

    private func parseProxyJumpToken(_ raw: String) -> ProxyJumpToken? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("ssh://") {
            token = String(token.dropFirst("ssh://".count))
        }
        var username: String?
        var hostPart = token
        if let at = token.firstIndex(of: "@") {
            let user = String(token[..<at]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = String(token[token.index(after: at)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !user.isEmpty, !rest.isEmpty {
                username = user
                hostPart = rest
            }
        }
        let (host, port) = splitHostAndPort(hostPart)
        guard let host, !host.isEmpty else { return nil }
        return ProxyJumpToken(username: username, host: host, port: port)
    }

    private func splitHostAndPort(_ raw: String) -> (String?, Int?) {
        if raw.hasPrefix("[") {
            guard let end = raw.firstIndex(of: "]") else { return (nil, nil) }
            let host = String(raw[raw.index(after: raw.startIndex)..<end])
            let rest = raw[raw.index(after: end)...]
            if rest.isEmpty { return (host.isEmpty ? nil : host, nil) }
            guard rest.first == ":" else { return (nil, nil) }
            guard let port = Int(rest.dropFirst()), (1...65_535).contains(port) else { return (nil, nil) }
            return (host, port)
        }
        let pieces = raw.split(separator: ":", omittingEmptySubsequences: false)
        if pieces.count == 2, let port = Int(pieces[1]), (1...65_535).contains(port), !pieces[0].isEmpty {
            return (String(pieces[0]), port)
        }
        if raw.isEmpty { return (nil, nil) }
        return (raw, nil)
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
