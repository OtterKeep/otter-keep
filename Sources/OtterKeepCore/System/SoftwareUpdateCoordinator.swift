import Foundation
import os

/// Metadata representation of an available application update.
public struct SoftwareUpdateInfo: Sendable, Equatable {
    /// Semantic version string (e.g. "1.1.0").
    public let version: String
    /// Build sequence number (e.g. "1100").
    public let buildNumber: String
    /// Release notes or changelog summary.
    public let releaseNotes: String
    /// Direct download or release page URL.
    public let downloadURL: URL
    /// Release publication timestamp.
    public let publicationDate: Date
    /// Whether this update addresses critical security flaws or breaking bugs.
    public let isCritical: Bool

    public init(
        version: String,
        buildNumber: String,
        releaseNotes: String,
        downloadURL: URL,
        publicationDate: Date = Date(),
        isCritical: Bool = false
    ) {
        self.version = version
        self.buildNumber = buildNumber
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.publicationDate = publicationDate
        self.isCritical = isCritical
    }
}

/// Lifecycle state of the software update checker.
public enum UpdateCheckStatus: Sendable, Equatable {
    case idle
    case checking
    case updateAvailable(SoftwareUpdateInfo)
    case upToDate
    case failed(String)

    public var statusDescription: String {
        switch self {
        case .idle:
            return "Idle"
        case .checking:
            return "Checking for updates..."
        case .updateAvailable(let info):
            return "Update available: v\(info.version)"
        case .upToDate:
            return "OtterKeep is up to date"
        case .failed(let err):
            return "Check failed: \(err)"
        }
    }
}

/// Coordinator managing in-app software update discovery, semantic version evaluation, Sparkle appcast integration, and GitHub Releases fallback.
public actor SoftwareUpdateCoordinator {
    public static let shared = SoftwareUpdateCoordinator()
    private let logger = Logger(subsystem: "com.otterkeep", category: "UpdateCoordinator")

    private static let autoCheckKey = "OtterKeep.AutoCheckForUpdates"
    private static let lastCheckKey = "OtterKeep.LastUpdateCheckDate"

    /// Default public appcast feed URL pointing to the raw GitHub distribution XML.
    public static let defaultAppcastURL = URL(string: "https://raw.githubusercontent.com/OtterKeep/otter-keep/main/Distribution/appcast.xml")!

    /// Default fallback web releases page.
    public static let defaultReleasesURL = URL(string: "https://github.com/OtterKeep/otter-keep/releases")!

    /// Official GitHub REST API endpoint for the latest release.
    public static let defaultGitHubReleasesAPIURL = URL(string: "https://api.github.com/repos/OtterKeep/otter-keep/releases/latest")!

    public private(set) var latestStatus: UpdateCheckStatus = .idle
    public private(set) var lastCheckDate: Date?
    private var mockUpdateInfo: SoftwareUpdateInfo?

    public init() {
        let ts = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        if ts > 0 {
            self.lastCheckDate = Date(timeIntervalSince1970: ts)
        }
    }

    /// Whether automatic background checking for updates is enabled.
    public var automaticallyChecksForUpdates: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.autoCheckKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey)
        }
    }

    /// Current running application version.
    public nonisolated var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? CoreEngine.version
    }

    /// Current running application build number.
    public nonisolated var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? CoreEngine.buildNumber
    }

    /// Injects mock update info for automated testing without network access.
    public func setMockUpdateInfo(_ info: SoftwareUpdateInfo?) {
        self.mockUpdateInfo = info
    }

    /// Compares two semantic version strings (e.g. "1.1.0" vs "1.1.1").
    /// Returns `.orderedAscending` if v1 < v2, `.orderedSame` if equal, `.orderedDescending` if v1 > v2.
    public static func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))

        // Extract base numeric parts before any hyphen or plus (e.g., 1.1.0-beta1 -> 1.1.0)
        let sem1 = clean1.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let sem2 = clean2.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)

        let base1 = String(sem1.first ?? "")
        let base2 = String(sem2.first ?? "")

        let parts1 = base1.split(separator: ".").compactMap { Int($0) }
        let parts2 = base2.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }

        // If numeric parts are identical, a version without prerelease is newer than one with prerelease (SemVer spec: 1.0.0 > 1.0.0-rc1)
        let hasPrerelease1 = sem1.count > 1
        let hasPrerelease2 = sem2.count > 1
        if hasPrerelease1 && !hasPrerelease2 {
            return .orderedAscending
        } else if !hasPrerelease1 && hasPrerelease2 {
            return .orderedDescending
        } else if hasPrerelease1 && hasPrerelease2 {
            return sem1[1].compare(sem2[1])
        }

        return .orderedSame
    }

    /// Returns `true` if `candidate` version is strictly newer than `current` version.
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        compareVersions(current, candidate) == .orderedAscending
    }

    /// Checks for available updates by querying the Sparkle appcast feed, with automatic fallback to GitHub Releases API.
    public func checkForUpdates(appcastURL: URL? = nil) async -> UpdateCheckStatus {
        latestStatus = .checking
        let now = Date()
        self.lastCheckDate = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastCheckKey)

        if let mock = mockUpdateInfo {
            if Self.isVersion(mock.version, newerThan: currentVersion) {
                let status = UpdateCheckStatus.updateAvailable(mock)
                self.latestStatus = status
                return status
            } else {
                let status = UpdateCheckStatus.upToDate
                self.latestStatus = status
                return status
            }
        }

        let feedURL = appcastURL ?? Self.defaultAppcastURL
        var req = URLRequest(url: feedURL)
        req.timeoutInterval = 10
        req.setValue("OtterKeep-Sparkle/2.0", forHTTPHeaderField: "User-Agent")

        var appcastError: String? = nil

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                if let update = parseAppcastXML(data: data) {
                    if Self.isVersion(update.version, newerThan: currentVersion) {
                        let status = UpdateCheckStatus.updateAvailable(update)
                        self.latestStatus = status
                        return status
                    } else {
                        let status = UpdateCheckStatus.upToDate
                        self.latestStatus = status
                        return status
                    }
                } else {
                    appcastError = "Unable to parse appcast XML feed"
                }
            } else if let http = response as? HTTPURLResponse {
                appcastError = "Appcast server returned HTTP \(http.statusCode)"
            }
        } catch {
            appcastError = error.localizedDescription
        }

        // Fallback: If Appcast feed is unavailable and default feed was requested, query GitHub Releases API directly
        if appcastURL == nil {
            logger.info("Sparkle appcast query yielded (\(appcastError ?? "nil")), attempting GitHub Releases API fallback...")
            do {
                if let ghUpdate = try await fetchFromGitHubReleasesAPI() {
                    if Self.isVersion(ghUpdate.version, newerThan: currentVersion) {
                        let status = UpdateCheckStatus.updateAvailable(ghUpdate)
                        self.latestStatus = status
                        return status
                    } else {
                        let status = UpdateCheckStatus.upToDate
                        self.latestStatus = status
                        return status
                    }
                }
            } catch {
                logger.warning("GitHub Releases API fallback also encountered error: \(error.localizedDescription)")
            }
        }

        let failureReason = appcastError ?? "Unable to verify software updates at this time."
        let status = UpdateCheckStatus.failed(failureReason)
        self.latestStatus = status
        return status
    }

    /// Queries the official GitHub Releases API for the latest published release.
    private func fetchFromGitHubReleasesAPI() async throws -> SoftwareUpdateInfo? {
        var req = URLRequest(url: Self.defaultGitHubReleasesAPIURL)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("OtterKeep-Updater/1.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        struct GHAsset: Decodable {
            let name: String
            let browser_download_url: String
        }
        struct GHRelease: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: String
            let published_at: String?
            let assets: [GHAsset]
        }

        let release = try JSONDecoder().decode(GHRelease.self, from: data)
        let cleanVer = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        guard !cleanVer.isEmpty else { return nil }

        // Prefer .zip archive, then .dmg disk image, then release HTML page
        let zipAsset = release.assets.first(where: { $0.name.hasSuffix(".zip") })
        let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
        let assetURL = zipAsset?.browser_download_url ?? dmgAsset?.browser_download_url
        let downloadURL = assetURL.flatMap { URL(string: $0) } ?? URL(string: release.html_url) ?? Self.defaultReleasesURL

        let pubDate: Date
        if let pubStr = release.published_at, let d = ISO8601DateFormatter().date(from: pubStr) {
            pubDate = d
        } else {
            pubDate = Date()
        }

        return SoftwareUpdateInfo(
            version: cleanVer,
            buildNumber: cleanVer,
            releaseNotes: release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? (release.name ?? ""),
            downloadURL: downloadURL,
            publicationDate: pubDate,
            isCritical: false
        )
    }

    /// Parses Sparkle Appcast XML feed data into `SoftwareUpdateInfo`.
    /// Evaluates multiple items if present, selecting the highest candidate version.
    public func parseAppcastXML(data: Data) -> SoftwareUpdateInfo? {
        // 1. First attempt structured SAX XMLParser
        let items = AppcastFeedParser.parse(data: data)
        if let best = items.max(by: { Self.compareVersions($0.version, $1.version) == .orderedAscending }) {
            return best
        }

        // 2. Fallback regex extraction for resilient tolerance of non-standard XML formats
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }

        var version = ""
        var build = ""
        var downloadURL: URL?
        var releaseNotes = ""

        if let range = xmlString.range(of: "sparkle:shortVersionString=\"") {
            let rest = xmlString[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                version = String(rest[..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
            }
        }

        if let range = xmlString.range(of: "sparkle:version=\"") {
            let rest = xmlString[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                build = String(rest[..<end])
            }
        }

        if let range = xmlString.range(of: "url=\"") {
            let rest = xmlString[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                downloadURL = URL(string: String(rest[..<end]))
            }
        }

        if let range = xmlString.range(of: "<description><![CDATA[") {
            let rest = xmlString[range.upperBound...]
            if let end = rest.range(of: "]]></description>") {
                releaseNotes = String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let range = xmlString.range(of: "<description>") {
            let rest = xmlString[range.upperBound...]
            if let end = rest.range(of: "</description>") {
                releaseNotes = String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !version.isEmpty, let dURL = downloadURL ?? Self.defaultReleasesURL as URL? else {
            return nil
        }

        return SoftwareUpdateInfo(
            version: version,
            buildNumber: build.isEmpty ? version : build,
            releaseNotes: releaseNotes,
            downloadURL: dURL,
            publicationDate: Date(),
            isCritical: false
        )
    }
}

// MARK: - Appcast SAX Feed Parser

/// SAX XMLParser implementation compliant with Sparkle RSS 2.0 appcast format.
private final class AppcastFeedParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private struct ItemBuilder {
        var version: String = ""
        var buildNumber: String = ""
        var title: String = ""
        var releaseNotes: String = ""
        var downloadURL: URL?
        var publicationDate: Date?
        var isCritical: Bool = false
    }

    private var items: [SoftwareUpdateInfo] = []
    private var currentItem: ItemBuilder?
    private var currentElementText: String = ""

    static func parse(data: Data) -> [SoftwareUpdateInfo] {
        let parser = AppcastFeedParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.shouldProcessNamespaces = false
        xmlParser.shouldResolveExternalEntities = false
        if xmlParser.parse() {
            return parser.items
        }
        return parser.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElementText = ""
        let lowerName = elementName.lowercased()

        if lowerName == "item" {
            currentItem = ItemBuilder()
        } else if lowerName == "enclosure" && currentItem != nil {
            if let urlStr = attributeDict["url"] ?? attributeDict["sparkle:url"], let url = URL(string: urlStr) {
                currentItem?.downloadURL = url
            }
            if let shortVer = attributeDict["sparkle:shortVersionString"] ?? attributeDict["shortVersionString"] {
                currentItem?.version = shortVer
            }
            if let buildVer = attributeDict["sparkle:version"] ?? attributeDict["version"] {
                currentItem?.buildNumber = buildVer
            }
        } else if (lowerName == "criticalupdate" || lowerName == "sparkle:criticalupdate") && currentItem != nil {
            currentItem?.isCritical = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentElementText.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let cdataStr = String(data: CDATABlock, encoding: .utf8) {
            currentElementText.append(cdataStr)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard var item = currentItem else { return }
        let lowerName = elementName.lowercased()
        let trimmedText = currentElementText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch lowerName {
        case "title":
            if item.title.isEmpty {
                item.title = trimmedText
            }
        case "description":
            if item.releaseNotes.isEmpty {
                item.releaseNotes = trimmedText
            }
        case "pubdate":
            if let date = Self.parseRFC822Date(trimmedText) {
                item.publicationDate = date
            }
        case "sparkle:shortversionstring", "shortversionstring":
            if item.version.isEmpty {
                item.version = trimmedText
            }
        case "sparkle:version":
            if item.buildNumber.isEmpty {
                item.buildNumber = trimmedText
            }
        case "item":
            var ver = item.version
            if ver.isEmpty {
                ver = item.title.replacingOccurrences(of: "Version", with: "", options: .caseInsensitive)
            }
            ver = ver.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
            let build = item.buildNumber.isEmpty ? ver : item.buildNumber
            let dURL = item.downloadURL ?? SoftwareUpdateCoordinator.defaultReleasesURL

            if !ver.isEmpty {
                let info = SoftwareUpdateInfo(
                    version: ver,
                    buildNumber: build,
                    releaseNotes: item.releaseNotes,
                    downloadURL: dURL,
                    publicationDate: item.publicationDate ?? Date(),
                    isCritical: item.isCritical
                )
                items.append(info)
            }
            currentItem = nil
            return
        default:
            break
        }
        currentItem = item
    }

    private static func parseRFC822Date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let d = formatter.date(from: string) { return d }
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let d = formatter.date(from: string) { return d }
        let isoFormatter = ISO8601DateFormatter()
        return isoFormatter.date(from: string)
    }
}
