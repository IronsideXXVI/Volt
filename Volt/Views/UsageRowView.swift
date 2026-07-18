import Foundation
import SwiftUI

struct UsageRowView: View {
    let window: UsageWindow
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(window.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(window.percentageDescription)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(metricColor)
                        .monospacedDigit()
                        .fixedSize()
                }

                MetricBar(
                    value: window.barFraction,
                    tint: metricColor,
                    animatesChanges: !reduceMotion
                )

                metadata(now: timeline.date)
            }
            .opacity(window.quotaState == .inactive ? 0.68 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(window.title)
            .accessibilityValue(accessibilityValue(now: timeline.date))
        }
    }

    private func metadata(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let status = window.statusDescription {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(status)
                        .fontWeight(.medium)
                } else if let reset = window.resetsAt {
                    Image(systemName: "clock")
                        .font(.system(size: 9.5, weight: .medium))
                    Text(resetDescription(reset, now: now))
                } else if let detail = window.detail {
                    Text(detail)
                }

                Spacer(minLength: 4)

                if window.statusDescription != nil, let reset = window.resetsAt {
                    Text(resetDescription(reset, now: now))
                        .multilineTextAlignment(.trailing)
                }
            }

            if let detail = window.detail,
               detail.caseInsensitiveCompare(window.statusDescription ?? "") != .orderedSame,
               window.resetsAt != nil || window.statusDescription != nil {
                Text(detail)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(metadataColor)
    }

    private var metricColor: Color {
        switch window.quotaState {
        case .normal:
            return tint
        case .warning:
            return .orange
        case .critical, .exhausted:
            return .red
        case .unavailable:
            return .orange
        case .inactive:
            return .secondary
        }
    }

    private var metadataColor: Color {
        switch window.quotaState {
        case .critical, .exhausted:
            return .red
        case .warning, .unavailable:
            return .orange
        case .normal, .inactive:
            return .secondary
        }
    }

    private var statusSymbol: String {
        switch window.quotaState {
        case .inactive:
            return "pause.circle.fill"
        case .unavailable:
            return "exclamationmark.circle.fill"
        case .exhausted:
            return "xmark.circle.fill"
        case .normal, .warning, .critical:
            return "info.circle.fill"
        }
    }

    private func accessibilityValue(now: Date) -> String {
        var parts = [window.accessibilityDescription]
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

private struct MetricBar: View {
    let value: Double
    let tint: Color
    let animatesChanges: Bool

    private var clampedValue: Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(VoltTheme.track)

                Rectangle()
                    .fill(tint)
                    .frame(width: geometry.size.width * clampedValue)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(VoltTheme.hairline, lineWidth: 0.5)
            }
        }
        .frame(height: 8)
        .animation(animatesChanges ? .easeOut(duration: 0.28) : nil, value: clampedValue)
        .accessibilityHidden(true)
    }
}
