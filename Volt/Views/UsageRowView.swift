import SwiftUI

struct UsageRowView: View {
    let window: UsageWindow
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(window.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(window.clampedUsedPercent.rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                }

                MetricBar(value: window.clampedUsedPercent / 100, tint: tint)

                if let elapsed = window.elapsedPercent(at: timeline.date) {
                    HStack(spacing: 8) {
                        Text("Time")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, alignment: .leading)
                        MetricBar(value: elapsed / 100, tint: Color.secondary.opacity(0.65), height: 5)
                    }
                }

                if let reset = window.resetsAt {
                    Label(resetDescription(reset, now: timeline.date), systemImage: "clock")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    private func resetDescription(_ date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Resetting now" }

        let minutes = max(Int(interval / 60), 1)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        let days = hours / 24

        if days > 1 {
            return "Resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
        if hours > 0 {
            return "Resets in \(hours) hr \(remainingMinutes) min"
        }
        return "Resets in \(minutes) min"
    }
}

private struct MetricBar: View {
    let value: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(VoltTheme.track)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
    }
}
