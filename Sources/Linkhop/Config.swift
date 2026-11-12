import Foundation

/// A routing rule. Every field that is set must match; the first matching rule wins.
struct Rule: Codable {
    /// Host to match. A plain host ("github.com") also matches its subdomains;
    /// use "*" for globs ("*.zoom.us", "docs.*.com").
    var host: String?
    /// Bundle id of the app the link was clicked in (see ~/Library/Logs/Linkhop.log).
    var from: String?
    /// Regex matched against the full URL.
    var pattern: String?
    /// Bundle id of the app to open the link with.
    var open: String

    func matches(_ url: URL, source: String?) -> Bool {
        guard host != nil || from != nil || pattern != nil else { return false }
        if let host, !Self.hostMatches(host, url.host ?? "") { return false }
        if let from, from.caseInsensitiveCompare(source ?? "") != .orderedSame { return false }
        if let pattern,
           url.absoluteString.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil {
            return false
        }
        return true
    }

    static func hostMatches(_ pattern: String, _ host: String) -> Bool {
        let p = pattern.lowercased(), h = host.lowercased()
        if !p.contains("*") { return h == p || h.hasSuffix("." + p) }
        let re = "^" + NSRegularExpression.escapedPattern(for: p).replacingOccurrences(of: "\\*", with: ".*") + "$"
        return h.range(of: re, options: .regularExpression) != nil
    }
}

struct Config: Codable {
    /// Bundle ids to show in the picker, in order. Omit to show every installed browser.
    var browsers: [String]?
    var rules: [Rule]?
    /// Bundle id to use when no rule matches. Omit to show the picker instead.
    var fallback: String?
}

enum ConfigStore {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/linkhop/config.json")

    static func loadStrict() throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    /// Never fails: a broken config logs and behaves as empty (picker for everything).
    static func load() -> Config {
        do { return try loadStrict() } catch {
            Log.write("config error: \(error)")
            return Config()
        }
    }

    static func save(_ config: Config) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try enc.encode(config).write(to: url, options: .atomic)
        } catch {
            Log.write("config save failed: \(error)")
        }
    }

    static func ensureExists() {
        if !FileManager.default.fileExists(atPath: url.path) { save(Config(rules: [])) }
    }

    /// Appends "always open <host> with <app>". Refuses to touch a config it can't parse.
    static func remember(host: String, app: String) {
        guard var config = try? loadStrict() else {
            Log.write("not saving rule: config has errors")
            return
        }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        config.rules = (config.rules ?? []) + [Rule(host: h, open: app)]
        save(config)
        Log.write("saved rule \(h) → \(app)")
    }
}

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Linkhop.log")

    static func write(_ message: String) {
        let line = Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line)
            try? h.close()
        } else {
            try? line.write(to: url)
        }
    }
}
