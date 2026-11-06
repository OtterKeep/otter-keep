import Foundation
import os
import OtterKeepDomain

/// Metadata representation of an object stored in S3-compatible cloud storage.
public struct S3ObjectMetadata: Sendable, Equatable {
    /// Object key (path in bucket).
    public let key: String
    /// Object size in bytes.
    public let size: Int64
    /// Entity tag (ETag/MD5 hex).
    public let etag: String
    /// Last modified timestamp.
    public let lastModified: Date?

    public init(key: String, size: Int64, etag: String, lastModified: Date? = nil) {
        self.key = key
        self.size = size
        self.etag = etag
        self.lastModified = lastModified
    }
}

/// Errors occurring during S3 cloud storage operations.
public enum S3Error: Error, Sendable, LocalizedError, Equatable {
    case invalidEndpoint(String)
    case requestFailed(statusCode: Int, message: String)
    case networkError(String)
    case xmlParsingError(String)
    case objectNotFound(key: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let ep): return "Invalid S3 endpoint URL: \(ep)"
        case .requestFailed(let code, let msg): return "S3 Request Failed [HTTP \(code)]: \(msg)"
        case .networkError(let msg): return "S3 Network Error: \(msg)"
        case .xmlParsingError(let msg): return "S3 XML Response Parse Error: \(msg)"
        case .objectNotFound(let key): return "S3 Object not found: \(key)"
        }
    }
}

/// Pure Swift S3-Compatible Cloud Storage Engine (AWS S3, Backblaze B2, Cloudflare R2, MinIO).
public actor S3StorageProvider {
    private let config: S3Configuration
    private let secretAccessKey: String
    private let session: URLSession
    private let logger = Logger(subsystem: "com.otterkeep", category: "S3Storage")

    public init(config: S3Configuration, secretAccessKey: String, session: URLSession = .shared) {
        self.config = config
        self.secretAccessKey = secretAccessKey
        self.session = session
    }

    /// Constructs the final target S3 URL for a given relative key.
    public func targetURL(for key: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var baseStr = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseStr.hasSuffix("/") {
            baseStr.removeLast()
        }

        let fullKey: String
        let cleanPrefix = config.pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let cleanKey = key.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if cleanPrefix.isEmpty {
            fullKey = cleanKey
        } else if cleanKey.isEmpty {
            fullKey = cleanPrefix
        } else {
            fullKey = "\(cleanPrefix)/\(cleanKey)"
        }

        let urlString: String
        if config.forcePathStyle || baseStr.contains("127.0.0.1") || baseStr.contains("localhost") {
            if config.bucket.isEmpty {
                urlString = "\(baseStr)/\(fullKey)"
            } else {
                urlString = "\(baseStr)/\(config.bucket)/\(fullKey)"
            }
        } else {
            guard let endpointURL = URL(string: baseStr), let host = endpointURL.host else {
                throw S3Error.invalidEndpoint(baseStr)
            }
            let scheme = endpointURL.scheme ?? "https"
            let portStr = endpointURL.port != nil ? ":\(endpointURL.port!)" : ""
            urlString = "\(scheme)://\(config.bucket).\(host)\(portStr)/\(fullKey)"
        }

        guard var components = URLComponents(string: urlString) else {
            throw S3Error.invalidEndpoint(urlString)
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let finalURL = components.url else {
            throw S3Error.invalidEndpoint(urlString)
        }
        return finalURL
    }

    /// Puts an object directly into S3.
    public func putObject(key: String, data: Data, contentType: String = "application/octet-stream") async throws -> String {
        let url = try targetURL(for: key)
        var headers: [String: String] = [
            "Content-Type": contentType
        ]

        headers = S3Signer.signRequestHeaders(
            method: "PUT",
            url: url,
            headers: headers,
            payload: data,
            accessKey: config.accessKeyId,
            secretKey: secretAccessKey,
            region: config.region
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse else {
            throw S3Error.networkError("Invalid HTTP response")
        }

        guard (200...299).contains(httpRes.statusCode) else {
            let msg = String(data: responseData, encoding: .utf8) ?? "HTTP \(httpRes.statusCode)"
            logger.error("PUT Object '\(key)' failed: \(httpRes.statusCode) - \(msg)")
            throw S3Error.requestFailed(statusCode: httpRes.statusCode, message: msg)
        }

        let etag = httpRes.value(forHTTPHeaderField: "ETag")?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""
        return etag
    }

    /// Fetches an object from S3.
    public func getObject(key: String) async throws -> Data {
        let url = try targetURL(for: key)
        var headers: [String: String] = [:]

        headers = S3Signer.signRequestHeaders(
            method: "GET",
            url: url,
            headers: headers,
            payload: Data(),
            accessKey: config.accessKeyId,
            secretKey: secretAccessKey,
            region: config.region
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse else {
            throw S3Error.networkError("Invalid HTTP response")
        }

        if httpRes.statusCode == 404 {
            throw S3Error.objectNotFound(key: key)
        }

        guard (200...299).contains(httpRes.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpRes.statusCode)"
            throw S3Error.requestFailed(statusCode: httpRes.statusCode, message: msg)
        }

        return data
    }

    /// Inspects existence and metadata of an object via HEAD request.
    public func headObject(key: String) async throws -> (exists: Bool, size: Int64, etag: String?) {
        let url = try targetURL(for: key)
        var headers: [String: String] = [:]

        headers = S3Signer.signRequestHeaders(
            method: "HEAD",
            url: url,
            headers: headers,
            payload: Data(),
            accessKey: config.accessKeyId,
            secretKey: secretAccessKey,
            region: config.region
        )

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (_, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse else {
            return (false, 0, nil)
        }

        if httpRes.statusCode == 404 {
            return (false, 0, nil)
        }

        guard (200...299).contains(httpRes.statusCode) else {
            return (false, 0, nil)
        }

        let size = Int64(httpRes.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
        let etag = httpRes.value(forHTTPHeaderField: "ETag")?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (true, size, etag)
    }

    /// Deletes an object from S3.
    public func deleteObject(key: String) async throws {
        let url = try targetURL(for: key)
        var headers: [String: String] = [:]

        headers = S3Signer.signRequestHeaders(
            method: "DELETE",
            url: url,
            headers: headers,
            payload: Data(),
            accessKey: config.accessKeyId,
            secretKey: secretAccessKey,
            region: config.region
        )

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse else {
            throw S3Error.networkError("Invalid HTTP response")
        }

        guard (200...299).contains(httpRes.statusCode) || httpRes.statusCode == 404 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpRes.statusCode)"
            throw S3Error.requestFailed(statusCode: httpRes.statusCode, message: msg)
        }
    }

    /// Tests S3 connectivity by attempting a bucket listing or probe request.
    public func testConnection() async throws -> Bool {
        var baseStr = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseStr.hasSuffix("/") {
            baseStr.removeLast()
        }

        let queryItems = [URLQueryItem(name: "max-keys", value: "1")]
        let url: URL
        if config.forcePathStyle || baseStr.contains("127.0.0.1") || baseStr.contains("localhost") {
            let bucketPart = config.bucket.isEmpty ? "" : "/\(config.bucket)"
            guard var comps = URLComponents(string: "\(baseStr)\(bucketPart)") else {
                throw S3Error.invalidEndpoint(baseStr)
            }
            comps.queryItems = queryItems
            guard let u = comps.url else { throw S3Error.invalidEndpoint(baseStr) }
            url = u
        } else {
            guard let endpointURL = URL(string: baseStr), let host = endpointURL.host else {
                throw S3Error.invalidEndpoint(baseStr)
            }
            let scheme = endpointURL.scheme ?? "https"
            let portStr = endpointURL.port != nil ? ":\(endpointURL.port!)" : ""
            guard var comps = URLComponents(string: "\(scheme)://\(config.bucket).\(host)\(portStr)") else {
                throw S3Error.invalidEndpoint(baseStr)
            }
            comps.queryItems = queryItems
            guard let u = comps.url else { throw S3Error.invalidEndpoint(baseStr) }
            url = u
        }

        var headers: [String: String] = [:]
        headers = S3Signer.signRequestHeaders(
            method: "GET",
            url: url,
            headers: headers,
            payload: Data(),
            accessKey: config.accessKeyId,
            secretKey: secretAccessKey,
            region: config.region
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse else {
            throw S3Error.networkError("Invalid HTTP response")
        }

        guard (200...299).contains(httpRes.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpRes.statusCode)"
            throw S3Error.requestFailed(statusCode: httpRes.statusCode, message: msg)
        }

        return true
    }

    // MARK: - Multipart Upload Engine

    /// Initiates a multipart upload session.
    public func initiateMultipartUpload(key: String, contentType: String = "application/octet-stream") async throws -> String {
        let queryItems = [URLQueryItem(name: "uploads", value: "")]
        let url = try targetURL(for: key, queryItems: queryItems)

        var headers: [String: String] = [
            "Content-Type": contentType
        ]

        headers = S3Signer.signRequestHeaders(
            method: "POST",
            url: url,
            headers: headers,
            payload: Data(),
            accessKey: config.accessKeyId,
            secretKey: secretAccessKey,
            region: config.region
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to initiate multipart"
            throw S3Error.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: msg)
        }

        guard let str = String(data: data, encoding: .utf8),
              let uploadId = extractXMLTag(str, tag: "UploadId") else {
            throw S3Error.xmlParsingError("UploadId tag not found in initiate response")
        }

        return uploadId
    }

    /// Uploads a single part within a multipart upload session.
    public func uploadPart(key: String, uploadId: String, partNumber: Int, data: Data) async throws -> String {
        let queryItems = [
            URLQueryItem(name: "partNumber", value: "\(partNumber)"),
            URLQueryItem(name: "uploadId", value: uploadId)
        ]
        let url = try targetURL(for: key, queryItems: queryItems)

        var headers: [String: String] = [:]
        headers = S3Signer.signRequestHeaders(
            method: "PUT",
            url: url,
            headers: headers,
            payload: data,
            accessKey: config.accessKeyId,
            secretKey: secretAccessKey,
            region: config.region
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let msg = String(data: responseData, encoding: .utf8) ?? "Part \(partNumber) upload failed"
            throw S3Error.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: msg)
        }

        guard let etag = httpRes.value(forHTTPHeaderField: "ETag")?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) else {
            throw S3Error.networkError("Missing ETag in part upload response")
        }

        return etag
    }

    /// Completes a multipart upload by assembling parts.
    public func completeMultipartUpload(key: String, uploadId: String, parts: [(partNumber: Int, etag: String)]) async throws {
        let queryItems = [URLQueryItem(name: "uploadId", value: uploadId)]
        let url = try targetURL(for: key, queryItems: queryItems)

        var xml = "<CompleteMultipartUpload>\n"
        for part in parts.sorted(by: { $0.partNumber < $1.partNumber }) {
            xml += "  <Part>\n    <PartNumber>\(part.partNumber)</PartNumber>\n    <ETag>\"\(part.etag)\"</ETag>\n  </Part>\n"
        }
        xml += "</CompleteMultipartUpload>"

        let xmlData = Data(xml.utf8)
        var headers: [String: String] = [
            "Content-Type": "application/xml"
        ]

        headers = S3Signer.signRequestHeaders(
            method: "POST",
            url: url,
            headers: headers,
            payload: xmlData,
            accessKey: config.accessKeyId,
            secretKey: secretAccessKey,
            region: config.region
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = xmlData

        let (data, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Complete multipart upload failed"
            throw S3Error.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: msg)
        }
    }

    /// Aborts an in-flight multipart upload.
    public func abortMultipartUpload(key: String, uploadId: String) async throws {
        let queryItems = [URLQueryItem(name: "uploadId", value: uploadId)]
        let url = try targetURL(for: key, queryItems: queryItems)

        var headers: [String: String] = [:]
        headers = S3Signer.signRequestHeaders(
            method: "DELETE",
            url: url,
            headers: headers,
            payload: Data(),
            accessKey: config.accessKeyId,
            secretKey: secretAccessKey,
            region: config.region
        )

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) || httpRes.statusCode == 404 else {
            let msg = String(data: data, encoding: .utf8) ?? "Abort multipart upload failed"
            throw S3Error.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: msg)
        }
    }

    /// Helper to extract simple XML tag contents.
    private func extractXMLTag(_ xml: String, tag: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"
        guard let startRange = xml.range(of: openTag),
              let endRange = xml.range(of: closeTag, range: startRange.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[startRange.upperBound..<endRange.lowerBound])
    }
}
