import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

/// Primary navigation sections within the modern sidebar.
public enum NavigationSection: Hashable, Sendable {
    /// A specific backup profile selected in the sidebar.
    case profile(UUID)
    /// Unified Apple Photos workspace.
    case photos
    /// Diagnostic system logs.
    case logs
    /// Preferences and system configuration.
    case settings
}

/// Tabs within the unified Profile Workspace.
public enum ProfileWorkspaceTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "overview"
    case timeMachine = "timeMachine"
    case rulesAndMaintenance = "rulesAndMaintenance"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .overview: return L10n.t(.tabOverview)
        case .timeMachine: return L10n.t(.tabTimeMachine)
        case .rulesAndMaintenance: return L10n.t(.tabRulesAndMaintenance)
        }
    }

    public var iconName: String {
        switch self {
        case .overview: return "gauge.with.needle"
        case .timeMachine: return "clock.arrow.circlepath"
        case .rulesAndMaintenance: return "slider.horizontal.3"
        }
    }
}

/// Subtabs within the Profile Rules and Maintenance workspace.
public enum ProfileMaintenanceSubTab: String, CaseIterable, Identifiable, Sendable {
    case rules = "rules"
    case automation = "automation"
    case maintenance = "maintenance"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .rules: return L10n.t(.profileSubTabRules)
        case .automation: return L10n.t(.profileSubTabAutomation)
        case .maintenance: return L10n.t(.profileSubTabMaintenance)
        }
    }

    public var iconName: String {
        switch self {
        case .rules: return "slider.horizontal.3"
        case .automation: return "clock.arrow.2.circlepath"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }
}

/// Tabs within the unified Photos Workspace.
public enum PhotosWorkspaceTab: String, CaseIterable, Identifiable, Sendable {
    case syncAndBackup = "syncAndBackup"
    case snapshots = "snapshots"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .syncAndBackup: return L10n.t(.tabPhotosSync)
        case .snapshots: return L10n.t(.tabPhotosSnapshots)
        }
    }

    public var iconName: String {
        switch self {
        case .syncAndBackup: return "photo.badge.arrow.down"
        case .snapshots: return "photo.stack"
        }
    }
}

/// Browsing mode selection for the restore explorer.
public enum RestoreBrowseMode: String, CaseIterable, Identifiable, Sendable {
    /// Browse files by individual snapshot directory tree.
    case snapshot = "snapshot"
    /// Vertical visual file timeline showing state changes across snapshots.
    case timeline = "timeline"
    /// Search files across all snapshots with complete version history.
    case globalSearch = "globalSearch"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .snapshot: return L10n.t(.restoreSnapshotMode)
        case .timeline: return L10n.t(.restoreTimelineMode)
        case .globalSearch: return L10n.t(.searchAcrossSnapshotsMode)
        }
    }

    public var iconName: String {
        switch self {
        case .snapshot: return "folder.fill"
        case .timeline: return "clock.arrow.circlepath"
        case .globalSearch: return "magnifyingglass"
        }
    }
}


/// Modal feedback payload presenting Ottie mascot illustrations and actionable guidance.
public struct OperationFeedback: Identifiable, Sendable {
    public enum FeedbackType: Sendable {
        case success
        case failure
    }

    public let id: UUID
    public let type: FeedbackType
    public let title: String
    public let message: String
    public let detailedReason: String?
    public let profileName: String?
    public let summary: BackupSessionSummary?
    public let restoreSummary: RestoreSessionSummary?

    public init(
        id: UUID = UUID(),
        type: FeedbackType,
        title: String,
        message: String,
        detailedReason: String? = nil,
        profileName: String? = nil,
        summary: BackupSessionSummary? = nil,
        restoreSummary: RestoreSessionSummary? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.detailedReason = detailedReason
        self.profileName = profileName
        self.summary = summary
        self.restoreSummary = restoreSummary
    }
}
