import AppKit
import MiniSpotifyCore
import SwiftUI

@main
enum MiniSpotifyApplication {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)

        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let windowController = MiniSpotifyWindowController()
    private let player = SpotifyPlayer(options: LaunchOptions.parse(arguments: CommandLine.arguments))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        let view = PlayerView(player: player, windowController: windowController)
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: MiniSpotifyWindowController.normalSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        windowController.window = window
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.minSize = NSSize(width: 260, height: 260)
        window.contentAspectRatio = NSSize(width: 1, height: 1)
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)

        player.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit MiniSpotify",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        return menu
    }
}

@MainActor
final class MiniSpotifyWindowController: ObservableObject {
    static let normalSize = NSSize(width: 420, height: 420)
    static let expandedSize = NSSize(width: 546, height: 546)

    weak var window: NSWindow?

    @Published private(set) var isExpanded = false
    private var resizeStartFrame: NSRect?

    func close() {
        window?.close()
    }

    func minimize() {
        window?.miniaturize(nil)
    }

    func toggleExpanded() {
        guard let window else { return }

        isExpanded.toggle()
        let targetSize = isExpanded ? Self.expandedSize : Self.normalSize
        let frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let targetFrame = NSRect(
            x: center.x - targetSize.width / 2,
            y: center.y - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )

        window.setFrame(targetFrame, display: true, animate: true)
    }

    func beginResize() {
        resizeStartFrame = window?.frame
    }

    func resizeBottomRightCorner(translation: CGSize) {
        guard let window,
              let startFrame = resizeStartFrame else {
            return
        }

        let dominantTranslation = abs(translation.width) > abs(translation.height)
            ? translation.width
            : translation.height
        let targetSide = min(
            max(startFrame.width + dominantTranslation, Self.normalSize.width),
            Self.expandedSize.width
        )
        let targetFrame = NSRect(
            x: startFrame.minX,
            y: startFrame.maxY - targetSide,
            width: targetSide,
            height: targetSide
        )

        isExpanded = targetSide >= Self.expandedSize.width - 0.5
        window.setFrame(targetFrame, display: true, animate: false)
    }

    func endResize() {
        resizeStartFrame = nil
    }
}

@MainActor
final class SpotifyPlayer: ObservableObject {
    @Published var artwork: NSImage?
    @Published var isPlaying = false
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var durationSeconds: TimeInterval = 0

    private let options: LaunchOptions
    private var pollTask: Task<Void, Never>?
    private var lastArtworkURL: String?
    private var initialTrackWasStarted = false

    init(options: LaunchOptions) {
        self.options = options
    }

    deinit {
        pollTask?.cancel()
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }

            await self.startInitialTrackIfNeeded()
            await self.refresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self.refresh()
            }
        }
    }

    func togglePlayPause() {
        Task {
            if isPlaying {
                _ = try? SpotifyAppleScript.run("""
                tell application id "\(SpotifyApplication.bundleIdentifier)"
                    pause
                end tell
                """)
            } else {
                await SpotifyApplication.launchHiddenIfNeeded()
                _ = try? SpotifyAppleScript.run("""
                tell application id "\(SpotifyApplication.bundleIdentifier)"
                    play
                end tell
                """)
            }

            SpotifyApplication.keepInBackground()
            try? await Task.sleep(for: .milliseconds(250))
            await refresh()
        }
    }

    private func startInitialTrackIfNeeded() async {
        guard !initialTrackWasStarted else { return }
        initialTrackWasStarted = true

        guard let uri = options.trackURI else {
            return
        }

        let contextClause: String
        if let context = options.contextURI {
            contextClause = " in context \(AppleScriptLiteral.string(context))"
        } else {
            contextClause = ""
        }

        await SpotifyApplication.launchHiddenIfNeeded()
        SpotifyApplication.keepInBackground()
        _ = try? SpotifyAppleScript.run("""
        tell application id "\(SpotifyApplication.bundleIdentifier)"
            play track \(AppleScriptLiteral.string(uri))\(contextClause)
        end tell
        """)
        SpotifyApplication.keepInBackground()
    }

    private func refresh() async {
        guard let snapshot = try? SpotifyAppleScript.currentTrack() else {
            return
        }

        isPlaying = snapshot.state == "playing"
        elapsedSeconds = snapshot.elapsedSeconds
        durationSeconds = snapshot.durationSeconds

        guard !snapshot.artworkURL.isEmpty,
              snapshot.artworkURL != lastArtworkURL,
              let url = URL(string: snapshot.artworkURL) else {
            return
        }

        lastArtworkURL = snapshot.artworkURL

        guard let image = await ImageLoader.loadImage(from: url) else {
            return
        }

        artwork = image
        NSApp.applicationIconImage = DockIconRenderer.icon(for: image)
    }
}

struct PlayerView: View {
    @ObservedObject var player: SpotifyPlayer
    @ObservedObject var windowController: MiniSpotifyWindowController
    @State private var isHoveringWindowControls = false
    @State private var isHoveringWindow = false

    var body: some View {
        ZStack {
            ArtworkView(image: player.artwork)
            BottomControlBand(player: player, isVisible: isHoveringWindow)

            VStack {
                HStack(spacing: 10) {
                    WindowControlButton(
                        color: Color(red: 1.0, green: 0.36, blue: 0.32),
                        symbolName: "xmark",
                        isShowingSymbol: isHoveringWindowControls,
                        accessibilityLabel: "Close",
                        onHoverChanged: setWindowControlsHover,
                        action: windowController.close
                    )
                    WindowControlButton(
                        color: Color(red: 1.0, green: 0.75, blue: 0.22),
                        symbolName: "minus",
                        isShowingSymbol: isHoveringWindowControls,
                        accessibilityLabel: "Minimize",
                        onHoverChanged: setWindowControlsHover,
                        action: windowController.minimize
                    )
                    WindowControlButton(
                        color: Color(red: 0.25, green: 0.80, blue: 0.35),
                        symbolName: "plus",
                        isShowingSymbol: isHoveringWindowControls,
                        accessibilityLabel: windowController.isExpanded ? "Restore" : "Maximize",
                        onHoverChanged: setWindowControlsHover,
                        action: windowController.toggleExpanded
                    )
                }
                .padding(.top, 14)
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    setWindowControlsHover(isHovering)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack {
                Spacer()
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }

            ResizeCornerHandle(windowController: windowController)
        }
        .frame(minWidth: 260, minHeight: 260)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .compositingGroup()
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHoveringWindow = isHovering
            }
        }
        .ignoresSafeArea()
    }

    private func setWindowControlsHover(_ isHovering: Bool) {
        withAnimation(.easeOut(duration: 0.08)) {
            isHoveringWindowControls = isHovering
        }
    }
}

struct ResizeCornerHandle: View {
    @ObservedObject var windowController: MiniSpotifyWindowController
    @State private var isHovering = false
    @State private var isDragging = false
    @State private var isCursorPushed = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Color.clear
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHovering = hovering

                        if hovering {
                            setResizeCursorActive(true)
                        } else if !isDragging {
                            setResizeCursorActive(false)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    setResizeCursorActive(true)
                                    windowController.beginResize()
                                }

                                windowController.resizeBottomRightCorner(translation: value.translation)
                            }
                            .onEnded { _ in
                                isDragging = false
                                windowController.endResize()

                                if !isHovering {
                                    setResizeCursorActive(false)
                                }
                            }
                    )
                    .help("Resize")
                    .onDisappear {
                        setResizeCursorActive(false)
                    }
            }
        }
    }

    private func setResizeCursorActive(_ isActive: Bool) {
        if isActive, !isCursorPushed {
            DiagonalResizeCursor.cursor.push()
            isCursorPushed = true
        } else if !isActive, isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
    }
}

@MainActor
enum DiagonalResizeCursor {
    static let cursor: NSCursor = {
        guard let symbol = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: "Resize"
        )?.withSymbolConfiguration(.init(pointSize: 17, weight: .bold)) else {
            return .resizeLeftRight
        }

        let size = NSSize(width: 28, height: 28)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        symbol.draw(
            in: NSRect(x: 4, y: 4, width: 20, height: 20),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()

        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()
}

struct BottomControlBand: View {
    @ObservedObject var player: SpotifyPlayer
    let isVisible: Bool

    private var progress: CGFloat {
        guard player.durationSeconds > 0 else { return 0 }
        return min(max(player.elapsedSeconds / player.durationSeconds, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let bandHeight = max(138, proxy.size.height * 0.35)

            ZStack(alignment: .bottom) {
                if let artwork = player.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 34)
                        .mask(
                            VStack {
                                Spacer()
                                Rectangle()
                                    .fill(.white)
                                    .frame(height: bandHeight)
                            }
                        )
                        .clipped()
                }

                VStack {
                    Spacer()

                    VStack(spacing: 10) {
                        ProgressRail(progress: progress)

                        HStack {
                            Text(PlaybackTimeFormatter.elapsed(player.elapsedSeconds))
                            Spacer()
                            Text(PlaybackTimeFormatter.remaining(
                                elapsed: player.elapsedSeconds,
                                duration: player.durationSeconds
                            ))
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.93))
                        .monospacedDigit()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 82)
                }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
    }
}

struct ProgressRail: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.32))
                Capsule()
                    .fill(.white.opacity(0.88))
                    .frame(width: max(4, width * progress))
            }
        }
        .frame(height: 5)
    }
}

enum PlaybackTimeFormatter {
    static func elapsed(_ seconds: TimeInterval) -> String {
        format(max(seconds, 0))
    }

    static func remaining(elapsed: TimeInterval, duration: TimeInterval) -> String {
        guard duration > 0 else { return "-0:00" }
        return "-\(format(max(duration - elapsed, 0)))"
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

struct WindowControlButton: View {
    let color: Color
    let symbolName: String
    let isShowingSymbol: Bool
    let accessibilityLabel: String
    let onHoverChanged: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 15, height: 15)
                .overlay(
                    Circle()
                        .stroke(.black.opacity(0.18), lineWidth: 0.6)
                )
                .overlay(
                    Image(systemName: symbolName)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.70))
                        .opacity(isShowingSymbol ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .onHover(perform: onHoverChanged)
    }
}

struct ArtworkView: View {
    let image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.05, blue: 0.055), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

struct TrackSnapshot {
    let state: String
    let artworkURL: String
    let elapsedSeconds: TimeInterval
    let durationSeconds: TimeInterval
}

enum SpotifyAppleScript {
    @MainActor
    static func currentTrack() throws -> TrackSnapshot {
        guard SpotifyApplication.isRunning else {
            return TrackSnapshot(state: "stopped", artworkURL: "", elapsedSeconds: 0, durationSeconds: 0)
        }

        let descriptor = try run("""
        tell application id "\(SpotifyApplication.bundleIdentifier)"
            set stateText to player state as string
            if stateText is "stopped" then
                return {stateText, "", 0, 0}
            end if

            set trackArtworkURL to artwork url of current track
            set trackPosition to player position
            set trackDuration to duration of current track
            return {stateText, trackArtworkURL, trackPosition, trackDuration}
        end tell
        """)

        return TrackSnapshot(
            state: descriptor.atIndex(1)?.stringValue ?? "stopped",
            artworkURL: descriptor.atIndex(2)?.stringValue ?? "",
            elapsedSeconds: descriptor.atIndex(3)?.doubleValue ?? 0,
            durationSeconds: TimeInterval(descriptor.atIndex(4)?.int32Value ?? 0) / 1000
        )
    }

    @MainActor
    static func run(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SpotifyScriptError.invalidSource
        }

        let result = script.executeAndReturnError(&error)

        if let error {
            throw SpotifyScriptError.execution(error.description)
        }

        return result
    }
}

enum SpotifyScriptError: Error {
    case invalidSource
    case execution(String)
}

enum SpotifyApplication {
    static let bundleIdentifier = "com.spotify.client"

    @MainActor
    static var isRunning: Bool {
        runningApplication != nil
    }

    @MainActor
    static func launchHiddenIfNeeded() async {
        guard !isRunning else {
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false

        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
                continuation.resume()
            }
        }

        keepInBackground()
        try? await Task.sleep(for: .milliseconds(1500))
    }

    @MainActor
    static func keepInBackground() {
        _ = runningApplication?.hide()
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            _ = runningApplication?.hide()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    private static var runningApplication: NSRunningApplication? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
    }
}

enum ImageLoader {
    static func loadImage(from url: URL) async -> NSImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}

enum DockIconRenderer {
    static func icon(for artwork: NSImage) -> NSImage {
        let canvasSize = NSSize(width: 1024, height: 1024)
        let padding: CGFloat = 112
        let artworkRect = NSRect(
            x: padding,
            y: padding,
            width: canvasSize.width - padding * 2,
            height: canvasSize.height - padding * 2
        )

        let icon = NSImage(size: canvasSize)
        icon.lockFocus()
        defer { icon.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let path = NSBezierPath(roundedRect: artworkRect, xRadius: 120, yRadius: 120)
        path.addClip()

        NSGraphicsContext.current?.imageInterpolation = .high
        artwork.draw(
            in: artworkRect,
            from: sourceRect(for: artwork),
            operation: .sourceOver,
            fraction: 1
        )

        return icon
    }

    private static func sourceRect(for image: NSImage) -> NSRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return .zero
        }

        if size.width > size.height {
            let side = size.height
            return NSRect(x: (size.width - side) / 2, y: 0, width: side, height: side)
        }

        let side = size.width
        return NSRect(x: 0, y: (size.height - side) / 2, width: side, height: side)
    }
}
