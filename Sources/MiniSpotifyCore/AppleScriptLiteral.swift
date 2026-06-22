import Foundation

public enum AppleScriptLiteral {
    public static func string(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return "\"\(escaped)\""
    }
}

public struct LaunchOptions: Equatable {
    public let trackURI: String?
    public let contextURI: String?

    public init(trackURI: String?, contextURI: String?) {
        self.trackURI = trackURI
        self.contextURI = contextURI
    }

    public static func parse(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchOptions {
        LaunchOptions(
            trackURI: value(named: "--track-uri", in: arguments) ?? nonEmpty(environment["SPOTIFY_TRACK_URI"]),
            contextURI: value(named: "--context-uri", in: arguments) ?? nonEmpty(environment["SPOTIFY_CONTEXT_URI"])
        )
    }

    private static func value(named name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }

        return nonEmpty(arguments[arguments.index(after: index)])
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}
