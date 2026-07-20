import Foundation
import SwiftUI

/// A single usage limit. The two stacked bars are the heart of the view: the
/// top bar is quota consumed, the bar directly beneath it is how much of the
/// reset window has elapsed. Aligning them makes it obvious at a glance whether
/// usage is running ahead of or behind the clock.
struct UsageRowView: View {
    let window: UsageWindow
    var showsTitle = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let elapsed = window.windowElapsedFraction(at: timeline.date)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(showsTitle ? window.title : "Quota consumed")
                        .voltRowText()
                        .foregroundStyle(showsTitle ? .primary : .secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(window.percentageDescription)
                        .voltRowText()
                        .fixedSize()
                }

                VStack(spacing: 4) {
                    // Usage bar always uses the Volt accent; the time bar always
                    // uses the neutral elapsed color. Neither changes with state.
                    UsageBar(fraction: window.barFraction, fill: VoltTheme.primary)
                    if let elapsed {
                        UsageBar(fraction: elapsed, fill: VoltTheme.windowElapsed)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: window.barFraction)

                metadata(elapsed: elapsed, now: timeline.date)
            }
            .opacity(window.quotaState == .inactive ? 0.6 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(window.title)
            .accessibilityValue(accessibilityValue(now: timeline.date))
        }
    }

    @ViewBuilder
    private func metadata(elapsed: Double?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // "Limit reached" is redundant with the "100% used" figure above and
            // is the last bit of state-driven color in a row, so it's omitted
            // visually (VoiceOver still reads it via the accessibility value).
            if let status = window.statusDescription, window.quotaState != .exhausted {
                Label(status, systemImage: statusSymbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(metadataColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let reset = window.resetsAt {
                    Label(resetDescription(reset, now: now), systemImage: "clock")
                        .voltRowText()
                }

                Spacer(minLength: 6)

                if let elapsed {
                    Text("\(percentString(elapsed)) elapsed")
                        .voltRowText()
                        .fixedSize()
                }
            }

            if let detail = window.detail,
               detail.caseInsensitiveCompare(window.statusDescription ?? "") != .orderedSame {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(metadataColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metadataColor: Color {
        switch window.quotaState {
        case .critical, .exhausted: return .red
        case .warning, .unavailable: return .orange
        case .normal, .inactive: return .secondary
        }
    }

    private var statusSymbol: String {
        switch window.quotaState {
        case .inactive: return "pause.circle.fill"
        case .unavailable: return "exclamationmark.circle.fill"
        case .exhausted: return "xmark.circle.fill"
        case .normal, .warning, .critical: return "info.circle.fill"
        }
    }

    private func percentString(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    private func accessibilityValue(now: Date) -> String {
        var parts = [window.accessibilityDescription]
        if let elapsed = window.windowElapsedPercentageDescription(at: now) {
            parts.append("\(elapsed) of quota window elapsed")
        }
        if let status = window.statusDescription { parts.append(status) }
        if let reset = window.resetsAt { parts.append(resetDescription(reset, now: now)) }
        if let detail = window.detail { parts.append(detail) }
        return parts.joined(separator: ". ")
    }

    private func resetDescription(_ date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Refresh due" }

        let totalMinutes = max(Int(ceil(interval / 60)), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours < 1 {
            return "Resets in \(totalMinutes) min"
        }
        if hours < 24 {
            return minutes == 0
                ? "Resets in \(hours) hr"
                : "Resets in \(hours) hr \(minutes) min"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Resets tomorrow at \(date.formatted(.dateTime.hour().minute()))"
        }
        if interval < 7 * 24 * 60 * 60 {
            return "Resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
        return "Resets \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }
}

/// A single rounded progress bar over a neutral track.
private struct UsageBar: View {
    let fraction: Double
    let fill: Color
    var height: CGFloat = 8

    private var clamped: Double {
        min(max(fraction.isFinite ? fraction : 0, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(VoltTheme.track)
                Capsule(style: .continuous)
                    .fill(fill)
                    .frame(width: geometry.size.width * clamped)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
