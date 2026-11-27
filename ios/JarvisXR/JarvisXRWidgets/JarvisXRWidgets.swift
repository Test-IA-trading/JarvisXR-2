import ActivityKit
import SwiftUI
import WidgetKit

/// The Dynamic Island and the lock screen of Jarvis's background watch: what Jarvis is
/// doing (waiting for two claps, listening, thinking, answering) and its last answer.
/// A tap opens Jarvis (jarvis://listen), which also runs what needed the screen.
@main
struct JarvisXRWidgets: WidgetBundle {
    var body: some Widget {
        JarvisWatchActivityWidget()
    }
}

struct JarvisWatchActivityWidget: Widget {
    private static let accent = Color(red: 0.36, green: 0.85, blue: 1.0)
    private static let openURL = URL(string: "jarvis://listen")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JarvisActivityAttributes.self) { context in
            JarvisWatchLockScreenView(state: context.state, accent: Self.accent)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(Self.accent)
                .widgetURL(Self.openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbol)
                        .font(.title2)
                        .foregroundStyle(Self.accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("JARVIS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Self.accent)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        JarvisStopWatchButton(accent: Self.accent)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(Self.accent)
            } compactTrailing: {
                Text(context.state.short)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Self.accent)
            } minimal: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(Self.accent)
            }
            .widgetURL(Self.openURL)
            .keylineTint(Self.accent)
        }
    }
}

struct JarvisWatchLockScreenView: View {
    let state: JarvisActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.symbol)
                .font(.title2)
                .foregroundStyle(accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("JARVIS · \(state.title)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                JarvisStopWatchButton(accent: accent)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

/// Stops the background watch (microphone off) until Jarvis is opened again.
struct JarvisStopWatchButton: View {
    let accent: Color

    var body: some View {
        Button(intent: StopBackgroundWatchIntent()) {
            Label("Arrêter la veille", systemImage: "mic.slash")
                .font(.caption.weight(.semibold))
        }
        .tint(accent)
    }
}
