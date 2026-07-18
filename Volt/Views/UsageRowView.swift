import Foundation
import SwiftUI

struct UsageRowView: View {
    let window: UsageWindow
    let tint: Color
    var showsTitle = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(showsTitle ? window.title : "Quota used")
                        .font(.system(size: showsTitle ? 12.5 : 10.5, weight: showsTitle ? .semibold : .medium))
                        .foregroundStyle(showsTitle ? Color.primary : Color.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Text(window.percentageDescription)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(metricColor)
                        .monospacedDigit()
                        .fixedSize()
                }

                VStack(spacing: 5) {
                    MetricBar(
                        value: window.barFraction,
                        tint: metricColor,
                        height: 9,
                        animatesChanges: !reduceMotion
                    )

                    if let elapsedFraction = window.windowElapsedFraction(at: timeline.date) {
                        MetricBar(
                            value: elapsedFraction,
                            tint: VoltTheme.windowElapsed,
                            height: 6,
                            animatesChanges: !reduceMotion
                        )
                    }
                }

                metadata(now: timeline.date)
            }
            .opacity(window.quotaState == .inactive ? 0.68 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(window.title)
            .accessibilityValue(accessibilityValue(now: timeline.date))
        }
    }

    private func metadata(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let status = window.statusDescription {
                Label(status, systemImage: statusSymbol)
                    .fontWeight(.semibold)
                    .foregroundStyle(metadataColor)
            }

            if let reset = window.resetsAt {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(resetDescription(reset, now: now))

                    Spacer(minLength: 5)

                    if let elapsed = window.windowElapsedPercentageDescription(at: now) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(VoltTheme.windowElapsed)
                                .frame(width: 5, height: 5)
                            Text("\(elapsed) elapsed")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .foregroundStyle(VoltTheme.windowElapsed)
                        .fixedSize()
                    }
                }
                .foregroundStyle(.secondary)
            } else if window.statusDescription == nil, let detail = window.detail {
                Text(detail)
                    .foregroundStyle(metadataColor)
            }

            if let detail = window.detail,
               detail.caseInsensitiveCompare(window.statusDescription ?? "") != .orderedSame,
               window.resetsAt != nil || window.statusDescription != nil {
                Text(detail)
                    .fontWeight(.medium)
                    .foregroundStyle(metadataColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 10.5))
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

private struct MetricBar: View {
    let value: Double
    let tint: Color
    let height: CGFloat
    let animatesChanges: Bool

    private var clampedValue: Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(VoltTheme.track)

                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(tint)
                    .frame(width: geometry.size.width * clampedValue)
            }
            .overlay {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .strokeBorder(VoltTheme.hairline, lineWidth: 0.5)
            }
        }
        .frame(height: height)
        .animation(animatesChanges ? .easeOut(duration: 0.28) : nil, value: clampedValue)
        .accessibilityHidden(true)
    }
}
