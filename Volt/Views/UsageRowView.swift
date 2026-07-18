import SwiftUI

struct UsageRowView: View {
    let window: UsageWindow
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(window.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(window.percentageDescription)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(metricColor)
                        .monospacedDigit()
                        .fixedSize()
                }

                MetricBar(value: window.barFraction, tint: metricColor)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let reset = window.resetsAt {
                        Image(systemName: "clock")
                            .font(.system(size: 9.5, weight: .medium))
                        Text(resetDescription(reset, now: timeline.date))
                    } else if let detail = window.detail {
                        Text(detail)
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(window.isLimitReached == true ? Color.orange : Color.secondary)

                if let detail = window.detail, window.resetsAt != nil {
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(window.isLimitReached == true ? Color.orange : Color.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(window.title)
            .accessibilityValue(window.percentageDescription)
        }
    }

    private var metricColor: Color {
        if window.isLimitReached == true || window.isAllowed == false {
            return .orange
        }
        switch window.displayMode {
        case .used where window.displayPercent >= 90:
            return .orange
        case .remaining where window.displayPercent <= 10:
            return .orange
        default:
            return tint
        }
    }

    private func resetDescription(_ date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Resetting now" }

        let totalMinutes = max(Int(interval / 60), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours >= 24 {
            return "Resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
        if hours > 0 {
            return "Resets in \(hours) hr \(minutes) min"
        }
        return "Resets in \(totalMinutes) min"
    }
}

private struct MetricBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(VoltTheme.track)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}
