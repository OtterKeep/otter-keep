import Foundation
import OtterKeepStorage

/// Supported webhook integration providers.
public enum WebhookServiceType: String, Codable, Sendable, CaseIterable {
    case slack = "slack"
    case discord = "discord"
    case pushover = "pushover"
    case genericJson = "genericJson"

    public var displayName: String {
        switch self {
        case .slack: return "Slack"
        case .discord: return "Discord"
        case .pushover: return "Pushover"
        case .genericJson: return "Custom HTTP POST (JSON)"
        }
    }

    public var iconName: String {
        switch self {
        case .slack: return "bubble.left.and.bubble.right.fill"
        case .discord: return "message.badge.filled.fill"
        case .pushover: return "bell.badge.fill"
        case .genericJson: return "network"
        }
    }
}

/// Webhook notification configuration for a backup profile or system-wide monitoring.
public struct WebhookConfiguration: Codable, Sendable, Equatable {
    /// Whether outbound webhook notifications are enabled.
    public var isEnabled: Bool
    /// Selected destination service.
    public var serviceType: WebhookServiceType
    /// Webhook URL (for Slack, Discord, or generic HTTP POST) or API endpoint.
    public var url: String
    /// Optional authorization token (e.g. Pushover application API token or HTTP Bearer token).
    public var authToken: String?
    /// Optional target user or channel (e.g. Pushover user key or Discord username).
    public var targetUserOrChannel: String?
    /// Send notification on successful backup completion.
    public var notifyOnSuccess: Bool
    /// Send notification when completed with warnings (e.g. unreadable locked files).
    public var notifyOnWarning: Bool
    /// Send notification on backup abortion or error.
    public var notifyOnFailure: Bool

    public init(
        isEnabled: Bool = false,
        serviceType: WebhookServiceType = .slack,
        url: String = "",
        authToken: String? = nil,
        targetUserOrChannel: String? = nil,
        notifyOnSuccess: Bool = true,
        notifyOnWarning: Bool = true,
        notifyOnFailure: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.serviceType = serviceType
        self.url = url
        self.authToken = authToken
        self.targetUserOrChannel = targetUserOrChannel
        self.notifyOnSuccess = notifyOnSuccess
        self.notifyOnWarning = notifyOnWarning
        self.notifyOnFailure = notifyOnFailure
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled, serviceType, url, authToken, targetUserOrChannel
        case notifyOnSuccess, notifyOnWarning, notifyOnFailure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.serviceType = try container.decodeIfPresent(WebhookServiceType.self, forKey: .serviceType) ?? .slack
        self.url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        self.authToken = try container.decodeIfPresent(String.self, forKey: .authToken)
        self.targetUserOrChannel = try container.decodeIfPresent(String.self, forKey: .targetUserOrChannel)
        self.notifyOnSuccess = try container.decodeIfPresent(Bool.self, forKey: .notifyOnSuccess) ?? true
        self.notifyOnWarning = try container.decodeIfPresent(Bool.self, forKey: .notifyOnWarning) ?? true
        self.notifyOnFailure = try container.decodeIfPresent(Bool.self, forKey: .notifyOnFailure) ?? true
    }
}

/// Payload parameters describing a completed or failed backup lifecycle event.
public struct WebhookBackupPayload: Sendable {
    public let profileId: String
    public let profileName: String
    public let status: String // "success", "completed_with_warnings", "failed"
    public let snapshotPath: String?
    public let filesScanned: Int64
    public let filesCopied: Int64
    public let bytesWritten: Int64
    public let durationSeconds: Double
    public let timestamp: Date
    public let errorMessage: String?

    public init(
        profileId: String,
        profileName: String,
        status: String,
        snapshotPath: String? = nil,
        filesScanned: Int64 = 0,
        filesCopied: Int64 = 0,
        bytesWritten: Int64 = 0,
        durationSeconds: Double = 0,
        timestamp: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.profileId = profileId
        self.profileName = profileName
        self.status = status
        self.snapshotPath = snapshotPath
        self.filesScanned = filesScanned
        self.filesCopied = filesCopied
        self.bytesWritten = bytesWritten
        self.durationSeconds = durationSeconds
        self.timestamp = timestamp
        self.errorMessage = errorMessage
    }
}

/// Actor managing asynchronous webhook construction, formatting, and delivery.
public actor WebhookDispatcher {
    public static let shared = WebhookDispatcher()

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Dispatches a backup notification event if the configuration permits it.
    public func dispatch(config: WebhookConfiguration, payload: WebhookBackupPayload) async throws {
        guard config.isEnabled, !config.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let shouldSend: Bool
        switch payload.status {
        case "success", "completed":
            shouldSend = config.notifyOnSuccess
        case "completed_with_warnings":
            shouldSend = config.notifyOnWarning
        default:
            shouldSend = config.notifyOnFailure
        }

        guard shouldSend else { return }

        _ = try await send(config: config, payload: payload)
    }


    /// Sends a diagnostic test webhook with dummy data to verify network endpoint connectivity.
    public func sendTestWebhook(config: WebhookConfiguration) async throws -> String {
        guard !config.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "OtterKeep.Webhook", code: 400, userInfo: [NSLocalizedDescriptionKey: "Webhook URL cannot be empty."])
        }

        let testPayload = WebhookBackupPayload(
            profileId: UUID().uuidString,
            profileName: "Test Backup Profile",
            status: "success",
            snapshotPath: "/Volumes/OtterBackup/2026-10-02_200000",
            filesScanned: 1420,
            filesCopied: 42,
            bytesWritten: 15_728_640,
            durationSeconds: 3.45,
            timestamp: Date(),
            errorMessage: nil
        )

        return try await send(config: config, payload: testPayload, isTest: true)
    }

    /// Constructs a fully prepared `URLRequest` ready for transmission to the configured webhook endpoint.
    public func buildRequest(config: WebhookConfiguration, payload: WebhookBackupPayload, isTest: Bool = false) throws -> URLRequest {
        let endpointString: String
        if config.serviceType == .pushover && (config.url.isEmpty || !config.url.hasPrefix("http")) {
            endpointString = "https://api.pushover.net/1/messages.json"
        } else {
            endpointString = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let requestURL = URL(string: endpointString) else {
            throw NSError(domain: "OtterKeep.Webhook", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid webhook URL: \(endpointString)"])
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0

        let formattedBytes = ByteCountFormatter.string(fromByteCount: payload.bytesWritten, countStyle: .file)
        let formattedDuration = String(format: "%.1fs", payload.durationSeconds)

        let statusEmoji: String
        let statusTitle: String
        switch payload.status {
        case "success", "completed":
            statusEmoji = "✅"
            statusTitle = "Backup Completed"
        case "completed_with_warnings":
            statusEmoji = "⚠️"
            statusTitle = "Completed with Warnings"
        default:
            statusEmoji = "❌"
            statusTitle = "Backup Failed"
        }

        let testPrefix = isTest ? "[TEST] " : ""

        switch config.serviceType {
        case .slack:
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            let slackJson: [String: Any] = [
                "text": "\(statusEmoji) \(testPrefix)OtterKeep: \(statusTitle) for '\(payload.profileName)'",
                "blocks": [
                    [
                        "type": "header",
                        "text": [
                            "type": "plain_text",
                            "text": "🦦 OtterKeep: \(statusEmoji) \(testPrefix)\(statusTitle)"
                        ]
                    ],
                    [
                        "type": "section",
                        "fields": [
                            ["type": "mrkdwn", "text": "*Profile:*\n\(payload.profileName)"],
                            ["type": "mrkdwn", "text": "*Status:*\n\(payload.status.capitalized)"],
                            ["type": "mrkdwn", "text": "*Files Copied:*\n\(payload.filesCopied) / \(payload.filesScanned)"],
                            ["type": "mrkdwn", "text": "*Data Written:*\n\(formattedBytes) (\(formattedDuration))"]
                        ]
                    ]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: slackJson, options: [])

        case .discord:
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            let colorCode: Int
            switch payload.status {
            case "success": colorCode = 0x2ECC71 // Green
            case "completed_with_warnings": colorCode = 0xF39C12 // Amber
            default: colorCode = 0xE74C3C // Red
            }

            let discordJson: [String: Any] = [
                "username": "OtterKeep",
                "embeds": [
                    [
                        "title": "\(statusEmoji) \(testPrefix)OtterKeep: \(statusTitle)",
                        "description": "Backup finished for profile **\(payload.profileName)**",
                        "color": colorCode,
                        "fields": [
                            ["name": "Files Copied", "value": "\(payload.filesCopied) / \(payload.filesScanned)", "inline": true],
                            ["name": "Data Written", "value": formattedBytes, "inline": true],
                            ["name": "Duration", "value": formattedDuration, "inline": true]
                        ],
                        "footer": [
                            "text": "OtterKeep macOS Backup Engine"
                        ]
                    ]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: discordJson, options: [])

        case .pushover:
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let token = config.authToken ?? ""
            let user = config.targetUserOrChannel ?? ""
            let title = "🦦 OtterKeep: \(testPrefix)\(statusTitle)"
            let message = "Profile: \(payload.profileName)\nCopied: \(payload.filesCopied) files (\(formattedBytes))\nDuration: \(formattedDuration)"
            let priority = (payload.status == "failed") ? "1" : "0"

            let params: [String: String] = [
                "token": token,
                "user": user,
                "title": title,
                "message": message,
                "priority": priority
            ]

            let bodyString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
            request.httpBody = bodyString.data(using: .utf8)

        case .genericJson:
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            if let token = config.authToken, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let genericJson: [String: Any] = [
                "event": isTest ? "test_ping" : "backup_completed",
                "profileId": payload.profileId,
                "profileName": payload.profileName,
                "status": payload.status,
                "snapshotPath": payload.snapshotPath ?? "",
                "filesScanned": payload.filesScanned,
                "filesCopied": payload.filesCopied,
                "bytesWritten": payload.bytesWritten,
                "durationSeconds": payload.durationSeconds,
                "timestamp": ISO8601DateFormatter().string(from: payload.timestamp),
                "errorMessage": payload.errorMessage ?? ""
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: genericJson, options: [.prettyPrinted])
        }

        return request
    }

    private func send(config: WebhookConfiguration, payload: WebhookBackupPayload, isTest: Bool = false) async throws -> String {
        let request = try buildRequest(config: config, payload: payload, isTest: isTest)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OtterKeep.Webhook", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from webhook endpoint."])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "OtterKeep.Webhook", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Webhook error (HTTP \(httpResponse.statusCode)): \(errorBody)"])
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "OK"
        LogManager.shared.log("Webhook dispatched successfully (\(config.serviceType.displayName)): HTTP \(httpResponse.statusCode)", level: .info, category: "Webhook")
        return responseBody
    }
}
