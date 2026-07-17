import Foundation
import SwiftUI

enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Claude"
        case .openAI: "OpenAI"
        }
    }

    var companyName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        }
    }

    var systemImage: String {
        switch self {
        case .anthropic: "sparkles"
        case .openAI: "brain.head.profile"
        }
    }

    var tint: Color {
        switch self {
        case .anthropic: Color(hex: "F97316")
        case .openAI: Color(hex: "168BFF")
        }
    }
}

struct UsageWindow: Identifiable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    let duration: TimeInterval?

    var clampedUsedPercent: Double {
        min(max(usedPercent, 0), 100)
    }

    func elapsedPercent(at date: Date = Date()) -> Double? {
        guard let resetsAt, let duration, duration > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(date)
        if remaining <= 0 { return 100 }
        return min(max((duration - remaining) / duration * 100, 0), 100)
    }
}

struct CreditSummary: Sendable {
    let title: String
    let value: String
    let detail: String?
}

struct ProviderUsageSnapshot: Sendable {
    let provider: AIProvider
    let account: String?
    let plan: String?
    let windows: [UsageWindow]
    let credits: [CreditSummary]
    let updatedAt: Date

    var subtitle: String? {
        let values = [account, plan].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

enum UsageServiceError: LocalizedError, Sendable {
    case notConfigured(AIProvider)
    case invalidCredentials(AIProvider)
    case invalidResponse(AIProvider)
    case server(AIProvider, Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(provider):
            "Configure \(provider.displayName) in Settings to view usage."
        case let .invalidCredentials(provider):
            "\(provider.displayName) rejected the saved credentials. Update them in Settings."
        case let .invalidResponse(provider):
            "Volt could not read the usage response returned by \(provider.displayName)."
        case let .server(provider, status):
            "\(provider.displayName) returned HTTP \(status). Try again in a moment."
        case let .message(message):
            message
        }
    }
}
