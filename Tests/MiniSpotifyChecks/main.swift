import MiniSpotifyCore

func expectEqual(_ actual: String, _ expected: String, file: StaticString = #file, line: UInt = #line) {
    guard actual == expected else {
        fatalError("Expected \(expected), got \(actual)", file: file, line: line)
    }
}

expectEqual(AppleScriptLiteral.string("spotify:track:abc123"), "\"spotify:track:abc123\"")
expectEqual(AppleScriptLiteral.string("a \"quoted\" \\ value"), "\"a \\\"quoted\\\" \\\\ value\"")

let argumentOptions = LaunchOptions.parse(
    arguments: ["MiniSpotify", "--track-uri", "spotify:track:abc123", "--context-uri", "spotify:album:def456", "--start-paused"],
    environment: [:]
)
precondition(argumentOptions == LaunchOptions(trackURI: "spotify:track:abc123", contextURI: "spotify:album:def456", startPaused: true))

let environmentOptions = LaunchOptions.parse(
    arguments: ["MiniSpotify"],
    environment: ["SPOTIFY_TRACK_URI": "spotify:track:env123", "SPOTIFY_START_PAUSED": "yes"]
)
precondition(environmentOptions == LaunchOptions(trackURI: "spotify:track:env123", contextURI: nil, startPaused: true))

let defaultOptions = LaunchOptions.parse(
    arguments: ["MiniSpotify"],
    environment: ["SPOTIFY_START_PAUSED": "no"]
)
precondition(defaultOptions == LaunchOptions(trackURI: nil, contextURI: nil, startPaused: false))

print("MiniSpotify checks passed")
