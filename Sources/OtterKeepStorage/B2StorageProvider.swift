import Foundation
import os
import OtterKeepDomain

/// Dedicated Backblaze B2 Storage Engine providing resilient cloud backup and object lifecycle management.
public actor B2StorageProvider {
    private let config: B2Configuration
    private let s3Provider: S3StorageProvider
    private let logger = Logger(subsystem: "com.otterkeep", category: "B2Storage")

    public init(config: B2Configuration, applicationKey: String) {
        self.config = config
        self.s3Provider = S3StorageProvider(
            config: config.toS3Configuration(),
            secretAccessKey: applicationKey
        )
    }

    /// Verifies connectivity and accessibility of the configured Backblaze B2 bucket.
    public func testConnection() async throws -> Bool {
        logger.info("Testing Backblaze B2 connection to bucket '\(self.config.bucketName)' at '\(self.config.resolvedEndpoint)'")
        return try await s3Provider.testConnection()
    }

    /// Uploads an object payload to Backblaze B2.
    public func putObject(key: String, data: Data, contentType: String = "application/octet-stream") async throws -> String {
        return try await s3Provider.putObject(key: key, data: data, contentType: contentType)
    }

    /// Fetches an object payload from Backblaze B2.
    public func getObject(key: String) async throws -> Data {
        return try await s3Provider.getObject(key: key)
    }

    /// Inspects existence and metadata of an object in Backblaze B2.
    public func headObject(key: String) async throws -> (exists: Bool, size: Int64, etag: String?) {
        return try await s3Provider.headObject(key: key)
    }

    /// Streams an upload to Backblaze B2 from a local file URL with real-time byte progress.
    public func uploadFile(key: String, fileURL: URL, progress: (@Sendable (Int64) -> Void)? = nil) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        progress?(Int64(data.count))
        return try await putObject(key: key, data: data)
    }

    /// Initiates a multi-part upload for large backup files or archives.
    public func initiateMultipartUpload(key: String, contentType: String = "application/octet-stream") async throws -> String {
        return try await s3Provider.initiateMultipartUpload(key: key, contentType: contentType)
    }

    /// Uploads an individual part in a multi-part upload.
    public func uploadPart(key: String, uploadId: String, partNumber: Int, data: Data) async throws -> String {
        return try await s3Provider.uploadPart(key: key, uploadId: uploadId, partNumber: partNumber, data: data)
    }

    /// Finalizes and commits a multi-part upload.
    public func completeMultipartUpload(key: String, uploadId: String, parts: [(partNumber: Int, etag: String)]) async throws {
        try await s3Provider.completeMultipartUpload(key: key, uploadId: uploadId, parts: parts)
    }

    /// Aborts an in-flight multi-part upload.
    public func abortMultipartUpload(key: String, uploadId: String) async throws {
        try await s3Provider.abortMultipartUpload(key: key, uploadId: uploadId)
    }

    /// Deletes an object from the Backblaze B2 bucket.
    public func deleteObject(key: String) async throws {
        try await s3Provider.deleteObject(key: key)
    }
}
