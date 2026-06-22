import MiniSpotifyCore

func expectEqual(_ actual: String, _ expected: String, file: StaticString = #file, line: UInt = #line) {
    guard actual == expected else {
        fatalError("Expected \(expected), got \(actual)", file: file, line: line)
    }
}

expectEqual(AppleScriptLiteral.string("spotify:track:abc123"), "\"spotify:track:abc123\"")
expectEqual(AppleScriptLiteral.string("a \"quoted\" \\ value"), "\"a \\\"quoted\\\" \\\\ value\"")

let argumentOptions = LaunchOptions.parse(
    arguments: ["MiniSpotify", "--track-uri", "spotify:track:abc123", "--context-uri", "spotify:album:def456"],
    environment: [:]
)
precondition(argumentOptions == LaunchOptions(trackURI: "spotify:track:abc123", contextURI: "spotify:album:def456"))

let environmentOptions = LaunchOptions.parse(
    arguments: ["MiniSpotify"],
    environment: ["SPOTIFY_TRACK_URI": "spotify:track:env123"]
)
precondition(environmentOptions == LaunchOptions(trackURI: "spotify:track:env123", contextURI: nil))

print("MiniSpotify checks passed")
