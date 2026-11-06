import Foundation
import os
import OtterKeepDomain

/// Metadata describing a file or directory item returned by a WebDAV PROPFIND operation.
public struct WebDAVItem: Sendable, Equatable {
    /// Relative or absolute path of the WebDAV item.
    public let path: String
    /// Whether the item is a collection (directory).
    public let isDirectory: Bool
    /// Content length in bytes.
    public let contentLength: Int64
    /// Last modified date if provided by the server.
    public let lastModified: Date?

    public init(path: String, isDirectory: Bool, contentLength: Int64, lastModified: Date? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.contentLength = contentLength
        self.lastModified = lastModified
    }
}

/// Errors specific to WebDAV (RFC 4918) operations.
public enum WebDAVError: Error, Sendable, LocalizedError, Equatable {
    case invalidURL(String)
    case unauthorized
    case httpError(statusCode: Int, message: String)
    case itemNotFound(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid WebDAV URL: \(url)"
        case .unauthorized:
            return "WebDAV authentication failed: Invalid username or password (HTTP 401 Unauthorized)."
        case .httpError(let statusCode, let message):
            return "WebDAV HTTP error (\(statusCode)): \(message)"
        case .itemNotFound(let path):
            return "WebDAV item not found: \(path) (HTTP 404)"
        case .networkError(let details):
            return "WebDAV network connection error: \(details)"
        }
    }
}

/// Actor managing RFC 4918 WebDAV communications with Nextcloud, ownCloud, Synology, and generic WebDAV servers.
public actor WebDAVStorageProvider {
    public let config: WebDAVConfiguration
    public let password: String?
    private let session: URLSession
    private let logger = Logger(subsystem: "com.otterkeep", category: "WebDAV")

    public init(
        config: WebDAVConfiguration,
        password: String? = nil,
        session: URLSession = .shared
    ) {
        self.config = config
        self.password = password
        self.session = session
    }

    /// Resolves the full target URL for an optional subpath relative to `config.destinationPath`.
    public func resolveURL(for relativePath: String = "") throws -> URL {
        var baseStr = config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseStr.hasSuffix("/") {
            baseStr.removeLast()
        }

        var dest = config.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dest.isEmpty && !dest.hasPrefix("/") {
            dest = "/" + dest
        }
        while dest.hasSuffix("/") {
            dest.removeLast()
        }

        var rel = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rel.isEmpty && !rel.hasPrefix("/") {
            rel = "/" + rel
        }

        let fullString = "\(baseStr)\(dest)\(rel)"
        guard let url = URL(string: fullString) else {
            throw WebDAVError.invalidURL(fullString)
        }
        return url
    }

    /// Prepares an authenticated `URLRequest` with HTTP Basic Authorization.
    private func makeRequest(url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("OtterKeep-WebDAV/1.0", forHTTPHeaderField: "User-Agent")

        if !config.username.isEmpty, let pwd = password {
            let authString = "\(config.username):\(pwd)"
            if let authData = authString.data(using: .utf8) {
                let base64 = authData.base64EncodedString()
                req.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        return req
    }

    /// Verifies server reachability and credentials via PROPFIND or OPTIONS.
    public func testConnection() async throws -> Bool {
        let targetURL = try resolveURL()
        var req = makeRequest(url: targetURL, method: "PROPFIND")
        req.setValue("0", forHTTPHeaderField: "Depth")
        req.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw WebDAVError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.networkError("Invalid non-HTTP response")
        }

        if httpResponse.statusCode == 401 {
            throw WebDAVError.unauthorized
        }

        // Accept 207 Multi-Status, 200 OK, or even 404 (if parent server is alive but dest folder not created yet)
        if (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 207 || httpResponse.statusCode == 404 {
            logger.info("WebDAV connection verified for \(self.config.serverURL) (HTTP \(httpResponse.statusCode))")
            return true
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""
        throw WebDAVError.httpError(statusCode: httpResponse.statusCode, message: responseBody)
    }

    /// Creates a directory collection using the WebDAV `MKCOL` method.
    public func createDirectory(path: String) async throws {
        let targetURL = try resolveURL(for: path)
        let req = makeRequest(url: targetURL, method: "MKCOL")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw WebDAVError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.networkError("Invalid response")
        }

        // 201 Created is standard success; 405 Method Not Allowed typically means the collection already exists
        if http.statusCode == 201 || http.statusCode == 405 || (200...299).contains(http.statusCode) {
            return
        }

        if http.statusCode == 401 {
            throw WebDAVError.unauthorized
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        throw WebDAVError.httpError(statusCode: http.statusCode, message: "MKCOL failed: \(body)")
    }

    /// Uploads file data using the WebDAV `PUT` method.
    public func uploadFile(path: String, data: Data) async throws {
        let targetURL = try resolveURL(for: path)
        var req = makeRequest(url: targetURL, method: "PUT")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue(String(data.count), forHTTPHeaderField: "Content-Length")

        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await session.upload(for: req, from: data)
        } catch {
            throw WebDAVError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.networkError("Invalid response")
        }

        if http.statusCode == 200 || http.statusCode == 201 || http.statusCode == 204 {
            return
        }

        if http.statusCode == 401 {
            throw WebDAVError.unauthorized
        }

        let body = String(data: responseData, encoding: .utf8) ?? ""
        throw WebDAVError.httpError(statusCode: http.statusCode, message: "PUT failed: \(body)")
    }

    /// Downloads file content using the WebDAV `GET` method.
    public func downloadFile(path: String) async throws -> Data {
        let targetURL = try resolveURL(for: path)
        let req = makeRequest(url: targetURL, method: "GET")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw WebDAVError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.networkError("Invalid response")
        }

        if http.statusCode == 404 {
            throw WebDAVError.itemNotFound(path)
        }

        if http.statusCode == 401 {
            throw WebDAVError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WebDAVError.httpError(statusCode: http.statusCode, message: "GET failed: \(body)")
        }

        return data
    }

    /// Deletes an item or directory collection using the WebDAV `DELETE` method.
    public func deleteItem(path: String) async throws {
        let targetURL = try resolveURL(for: path)
        let req = makeRequest(url: targetURL, method: "DELETE")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw WebDAVError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.networkError("Invalid response")
        }

        if (200...299).contains(http.statusCode) || http.statusCode == 404 {
            return
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        throw WebDAVError.httpError(statusCode: http.statusCode, message: "DELETE failed: \(body)")
    }

    /// Checks whether an item exists via `HEAD` or `PROPFIND`.
    public func exists(path: String) async throws -> Bool {
        let targetURL = try resolveURL(for: path)
        let req = makeRequest(url: targetURL, method: "HEAD")

        do {
            let (_, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    /// Lists directory contents using the WebDAV `PROPFIND` method (Depth: 1).
    public func listItems(path: String = "") async throws -> [WebDAVItem] {
        let targetURL = try resolveURL(for: path)
        var req = makeRequest(url: targetURL, method: "PROPFIND")
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw WebDAVError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.networkError("Invalid response")
        }

        guard http.statusCode == 207 || (200...299).contains(http.statusCode) else {
            if http.statusCode == 404 { return [] }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WebDAVError.httpError(statusCode: http.statusCode, message: "PROPFIND failed: \(body)")
        }

        return parseMultiStatus(data: data)
    }

    /// Simple lightweight XML parsing of WebDAV 207 Multi-Status response.
    private func parseMultiStatus(data: Data) -> [WebDAVItem] {
        guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
        var items: [WebDAVItem] = []

        // Break by response blocks
        let responseBlocks = xmlString.components(separatedBy: "<d:response").dropFirst()
        let fallbackBlocks = responseBlocks.isEmpty ? xmlString.components(separatedBy: "<D:response").dropFirst() : responseBlocks

        for block in fallbackBlocks {
            let isDir = block.contains("<d:collection") || block.contains("<D:collection")
            var href = ""
            if let start = block.range(of: "<d:href>")?.upperBound ?? block.range(of: "<D:href>")?.upperBound,
               let end = block.range(of: "</d:href>", range: start..<block.endIndex)?.lowerBound ?? block.range(of: "</D:href>", range: start..<block.endIndex)?.lowerBound {
                href = String(block[start..<end])
            }

            var size: Int64 = 0
            if let start = block.range(of: "<d:getcontentlength>")?.upperBound ?? block.range(of: "<D:getcontentlength>")?.upperBound,
               let end = block.range(of: "</d:getcontentlength>", range: start..<block.endIndex)?.lowerBound ?? block.range(of: "</D:getcontentlength>", range: start..<block.endIndex)?.lowerBound {
                size = Int64(block[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }

            if !href.isEmpty {
                items.append(WebDAVItem(path: href, isDirectory: isDir, contentLength: size))
            }
        }

        return items
    }
}
