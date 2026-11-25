import Foundation
import CryptoKit

struct R2Credentials: Codable, Equatable {
    var accountId: String
    var accessKeyId: String
    var secretAccessKey: String
    var bucket: String
    var source: String = "manual" // "versely" or "manual"

    var host: String { "\(accountId).r2.cloudflarestorage.com" }
}

struct R2Object: Identifiable, Hashable {
    let key: String
    let size: Int64
    let lastModified: Date?
    let etag: String?
    var id: String { key }
    var name: String { key.split(separator: "/").last.map(String.init) ?? key }
    var ext: String { (name as NSString).pathExtension.lowercased() }
    var isFolderMarker: Bool { key.hasSuffix("/") }
}

struct R2Listing {
    var folders: [String] = []
    var objects: [R2Object] = []
}

enum R2Error: LocalizedError {
    case http(Int, String, String)
    case badResponse
    case verifyFailed(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .http(let status, let code, let message):
            return message.isEmpty ? "R2 returned \(status) \(code)" : "\(message) (\(code), HTTP \(status))"
        case .badResponse: return "R2 sent an unexpected response"
        case .verifyFailed(let why): return "Upload check failed: \(why)"
        case .notConfigured: return "Cloudflare R2 isn’t connected yet"
        }
    }
}

/// Minimal S3-compatible client for Cloudflare R2 with AWS Signature V4.
final class R2Client: @unchecked Sendable {
    let creds: R2Credentials
    private let session: URLSession
    static let singlePutLimit: Int64 = 64 * 1024 * 1024
    static let partSize: Int64 = 32 * 1024 * 1024

    init(_ creds: R2Credentials) {
        self.creds = creds
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 60 * 60 * 24
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)
    }

    // MARK: Buckets

    func listBuckets() async throws -> [String] {
        let (data, _) = try await send(method: "GET", bucket: nil, key: nil)
        let doc = try XMLDocument(data: data)
        return doc.rootElement()?.descendants(named: "Name").map(\.stringValueTrimmed) ?? []
    }

    func createBucket(_ name: String) async throws {
        _ = try await send(method: "PUT", bucket: name, key: nil)
    }

    func bucketExists(_ name: String) async -> Bool {
        (try? await send(method: "HEAD", bucket: name, key: nil)) != nil
    }

    // MARK: Listing

    func list(bucket: String? = nil, prefix: String, delimiter: String? = "/") async throws -> R2Listing {
        var listing = R2Listing()
        var token: String?
        repeat {
            var query: [(String, String)] = [("list-type", "2"), ("prefix", prefix), ("max-keys", "1000")]
            if let delimiter { query.append(("delimiter", delimiter)) }
            if let token { query.append(("continuation-token", token)) }
            let (data, _) = try await send(method: "GET", bucket: bucket ?? creds.bucket, key: nil, query: query)
            let doc = try XMLDocument(data: data)
            guard let root = doc.rootElement() else { throw R2Error.badResponse }
            for c in root.children(named: "Contents") {
                let key = c.child("Key")?.stringValueTrimmed ?? ""
                if key == prefix { continue }
                listing.objects.append(R2Object(
                    key: key,
                    size: Int64(c.child("Size")?.stringValueTrimmed ?? "0") ?? 0,
                    lastModified: R2Client.parseISO(c.child("LastModified")?.stringValueTrimmed),
                    etag: c.child("ETag")?.stringValueTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                ))
            }
            for p in root.children(named: "CommonPrefixes") {
                if let pre = p.child("Prefix")?.stringValueTrimmed { listing.folders.append(pre) }
            }
            let truncated = root.child("IsTruncated")?.stringValueTrimmed == "true"
            token = truncated ? root.child("NextContinuationToken")?.stringValueTrimmed : nil
        } while token != nil
        return listing
    }

    func head(_ key: String, bucket: String? = nil) async throws -> (size: Int64, etag: String?, metadata: [String: String])? {
        do {
            let (_, resp) = try await send(method: "HEAD", bucket: bucket ?? creds.bucket, key: key)
            let size = Int64(resp.value(forHTTPHeaderField: "Content-Length") ?? "") ?? -1
            var meta: [String: String] = [:]
            for (k, v) in resp.allHeaderFields {
                if let k = k as? String, k.lowercased().hasPrefix("x-amz-meta-"), let v = v as? String {
                    meta[String(k.lowercased().dropFirst("x-amz-meta-".count))] = v
                }
            }
            return (size, resp.value(forHTTPHeaderField: "ETag")?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")), meta)
        } catch R2Error.http(404, _, _) {
            return nil
        }
    }

    // MARK: Upload

    /// Uploads a file, using multipart for anything over 64 MB. Every part carries Content-MD5, so R2 rejects corrupted bytes.
    func upload(file: URL, key: String, bucket: String? = nil, metadata: [String: String] = [:],
                progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let size = Int64((try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        let bucket = bucket ?? creds.bucket
        var headers: [String: String] = ["content-type": R2Client.mimeType(for: file.pathExtension)]
        for (k, v) in metadata { headers["x-amz-meta-\(k)"] = v }

        if size <= R2Client.singlePutLimit {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            var h = headers
            h["content-md5"] = Data(Insecure.MD5.hash(data: data)).base64EncodedString()
            _ = try await send(method: "PUT", bucket: bucket, key: key, headers: h, body: data, progress: { sent, _ in progress(sent, size) })
            progress(size, size)
            return
        }

        // Multipart
        let (initData, _) = try await send(method: "POST", bucket: bucket, key: key, query: [("uploads", "")], headers: headers)
        guard let uploadId = try XMLDocument(data: initData).rootElement()?.child("UploadId")?.stringValueTrimmed else { throw R2Error.badResponse }
        let partCount = Int((size + R2Client.partSize - 1) / R2Client.partSize)
        let tracker = ProgressTracker(total: size, report: progress)
        do {
            var etags = [Int: String]()
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                var next = 1
                func addPart(_ n: Int) {
                    group.addTask {
                        let offset = Int64(n - 1) * R2Client.partSize
                        let length = Int(min(R2Client.partSize, size - offset))
                        let fh = try FileHandle(forReadingFrom: file)
                        defer { try? fh.close() }
                        try fh.seek(toOffset: UInt64(offset))
                        guard let chunk = try fh.read(upToCount: length), chunk.count == length else { throw R2Error.badResponse }
                        let md5 = Data(Insecure.MD5.hash(data: chunk)).base64EncodedString()
                        let lastSent = Counter()
                        let (_, resp) = try await self.send(method: "PUT", bucket: bucket, key: key,
                                                            query: [("partNumber", String(n)), ("uploadId", uploadId)],
                                                            headers: ["content-md5": md5], body: chunk,
                                                            progress: { sent, _ in
                                                                tracker.add(sent - lastSent.swap(sent))
                                                            })
                        tracker.add(Int64(length) - lastSent.value)
                        guard let etag = resp.value(forHTTPHeaderField: "ETag") else { throw R2Error.badResponse }
                        return (n, etag)
                    }
                }
                while next <= min(4, partCount) { addPart(next); next += 1 }
                while let (n, etag) = try await group.next() {
                    etags[n] = etag
                    if next <= partCount { addPart(next); next += 1 }
                }
            }
            var xml = "<CompleteMultipartUpload>"
            for n in 1...partCount {
                xml += "<Part><PartNumber>\(n)</PartNumber><ETag>\(etags[n] ?? "")</ETag></Part>"
            }
            xml += "</CompleteMultipartUpload>"
            _ = try await send(method: "POST", bucket: bucket, key: key, query: [("uploadId", uploadId)],
                               headers: ["content-type": "application/xml"], body: Data(xml.utf8))
        } catch {
            _ = try? await send(method: "DELETE", bucket: bucket, key: key, query: [("uploadId", uploadId)])
            throw error
        }
    }

    func putEmpty(key: String) async throws {
        _ = try await send(method: "PUT", bucket: creds.bucket, key: key, headers: ["content-type": "application/x-directory"], body: Data())
    }

    // MARK: Download

    func download(key: String, bucket: String? = nil, to destination: URL,
                  progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let request = signedRequest(method: "GET", bucket: bucket ?? creds.bucket, key: key)
        let delegate = TransferDelegate(progress: progress)
        let (tmp, resp) = try await session.download(for: request, delegate: delegate)
        guard let http = resp as? HTTPURLResponse else { throw R2Error.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = (try? Data(contentsOf: tmp)) ?? Data()
            throw R2Client.parseError(status: http.statusCode, data: body)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: tmp, to: destination)
    }

    // MARK: Delete

    func delete(key: String, bucket: String? = nil) async throws {
        _ = try await send(method: "DELETE", bucket: bucket ?? creds.bucket, key: key)
    }

    func delete(keys: [String], bucket: String? = nil) async throws {
        for batch in stride(from: 0, to: keys.count, by: 1000).map({ Array(keys[$0..<min($0 + 1000, keys.count)]) }) {
            var xml = "<Delete><Quiet>true</Quiet>"
            for k in batch { xml += "<Object><Key>\(R2Client.xmlEscape(k))</Key></Object>" }
            xml += "</Delete>"
            let body = Data(xml.utf8)
            _ = try await send(method: "POST", bucket: bucket ?? creds.bucket, key: nil, query: [("delete", "")],
                               headers: ["content-md5": Data(Insecure.MD5.hash(data: body)).base64EncodedString(),
                                         "content-type": "application/xml"], body: body)
        }
    }

    // MARK: Presigned links

    func presignedURL(key: String, bucket: String? = nil, expires: Int = 7 * 86_400) -> URL? {
        let now = Date()
        let amzDate = R2Client.amzDate(now)
        let dateStamp = String(amzDate.prefix(8))
        let scope = "\(dateStamp)/auto/s3/aws4_request"
        let path = R2Client.canonicalPath(bucket: bucket ?? creds.bucket, key: key)
        var query: [(String, String)] = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", "\(creds.accessKeyId)/\(scope)"),
            ("X-Amz-Date", amzDate),
            ("X-Amz-Expires", String(expires)),
            ("X-Amz-SignedHeaders", "host"),
        ]
        let canonicalQuery = R2Client.canonicalQuery(query)
        let canonicalRequest = ["GET", path, canonicalQuery, "host:\(creds.host)\n", "host", "UNSIGNED-PAYLOAD"].joined(separator: "\n")
        let signature = sign(canonicalRequest: canonicalRequest, amzDate: amzDate, dateStamp: dateStamp)
        query.append(("X-Amz-Signature", signature))
        return URL(string: "https://\(creds.host)\(path)?\(R2Client.canonicalQuery(query))")
    }

    // MARK: Signing

    func signedRequest(method: String, bucket: String?, key: String?, query: [(String, String)] = [],
                       headers: [String: String] = [:]) -> URLRequest {
        let now = Date()
        let amzDate = R2Client.amzDate(now)
        let dateStamp = String(amzDate.prefix(8))
        let path = bucket.map { R2Client.canonicalPath(bucket: $0, key: key) } ?? "/"
        let canonicalQuery = R2Client.canonicalQuery(query)

        var all: [String: String] = [:]
        for (k, v) in headers { all[k.lowercased()] = v.trimmingCharacters(in: .whitespaces) }
        all["host"] = creds.host
        all["x-amz-date"] = amzDate
        all["x-amz-content-sha256"] = "UNSIGNED-PAYLOAD"
        let names = all.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(all[$0]!)\n" }.joined()
        let signedHeaders = names.joined(separator: ";")
        let canonicalRequest = [method, path, canonicalQuery, canonicalHeaders, signedHeaders, "UNSIGNED-PAYLOAD"].joined(separator: "\n")
        let signature = sign(canonicalRequest: canonicalRequest, amzDate: amzDate, dateStamp: dateStamp)

        var urlString = "https://\(creds.host)\(path)"
        if !canonicalQuery.isEmpty { urlString += "?" + canonicalQuery }
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        for (k, v) in all where k != "host" { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("AWS4-HMAC-SHA256 Credential=\(creds.accessKeyId)/\(dateStamp)/auto/s3/aws4_request, SignedHeaders=\(signedHeaders), Signature=\(signature)",
                         forHTTPHeaderField: "Authorization")
        return request
    }

    private func sign(canonicalRequest: String, amzDate: String, dateStamp: String) -> String {
        let scope = "\(dateStamp)/auto/s3/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope, R2Client.sha256Hex(Data(canonicalRequest.utf8))].joined(separator: "\n")
        var key = SymmetricKey(data: Data("AWS4\(creds.secretAccessKey)".utf8))
        for part in [dateStamp, "auto", "s3", "aws4_request"] {
            key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: key)))
        }
        let sig = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        return Data(sig).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func send(method: String, bucket: String?, key: String?, query: [(String, String)] = [],
              headers: [String: String] = [:], body: Data? = nil,
              progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = signedRequest(method: method, bucket: bucket, key: key, query: query, headers: headers)
        let data: Data
        let resp: URLResponse
        if let body, method == "PUT" || method == "POST" {
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            let delegate = progress.map { TransferDelegate(progress: $0) }
            (data, resp) = try await session.upload(for: request, from: body, delegate: delegate)
        } else {
            (data, resp) = try await session.data(for: request)
        }
        guard let http = resp as? HTTPURLResponse else { throw R2Error.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw R2Client.parseError(status: http.statusCode, data: data) }
        return (data, http)
    }

    // MARK: Helpers

    static func parseError(status: Int, data: Data) -> R2Error {
        if let doc = try? XMLDocument(data: data), let root = doc.rootElement() {
            return .http(status, root.child("Code")?.stringValueTrimmed ?? "", root.child("Message")?.stringValueTrimmed ?? "")
        }
        return .http(status, HTTPURLResponse.localizedString(forStatusCode: status), "")
    }

    static func amzDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }

    static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private static let unreserved: Set<UInt8> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~".utf8)

    static func uriEncode(_ s: String, encodeSlash: Bool = true) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        let slash = UInt8(ascii: "/")
        for byte in s.utf8 {
            if unreserved.contains(byte) || (byte == slash && !encodeSlash) {
                out.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    static func canonicalPath(bucket: String, key: String?) -> String {
        guard let key, !key.isEmpty else { return "/" + uriEncode(bucket) }
        return "/" + uriEncode(bucket) + "/" + uriEncode(key, encodeSlash: false)
    }

    static func canonicalQuery(_ items: [(String, String)]) -> String {
        let encoded: [(String, String)] = items.map { (uriEncode($0.0), uriEncode($0.1)) }
        let sorted = encoded.sorted { (a: (String, String), b: (String, String)) -> Bool in
            a.0 == b.0 ? a.1 < b.1 : a.0 < b.0
        }
        return sorted.map { (pair: (String, String)) -> String in pair.0 + "=" + pair.1 }.joined(separator: "&")
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func mimeType(for ext: String) -> String {
        let map: [String: String] = [
            "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp",
            "heic": "image/heic", "svg": "image/svg+xml", "pdf": "application/pdf", "mp4": "video/mp4", "mov": "video/quicktime",
            "m4v": "video/x-m4v", "webm": "video/webm", "mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav",
            "zip": "application/zip", "dmg": "application/x-apple-diskimage", "json": "application/json", "txt": "text/plain",
            "md": "text/markdown", "html": "text/html", "csv": "text/csv",
        ]
        return map[ext.lowercased()] ?? "application/octet-stream"
    }

    /// Header-safe encoding for metadata values.
    static func metaEncode(_ s: String) -> String { uriEncode(s, encodeSlash: false) }
    static func metaDecode(_ s: String) -> String { s.removingPercentEncoding ?? s }
}

final class TransferDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Int64, Int64) -> Void
    private var last = Date.distantPast

    init(progress: @escaping @Sendable (Int64, Int64) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard Date().timeIntervalSince(last) > 0.1 || totalBytesSent == totalBytesExpectedToSend else { return }
        last = Date()
        progress(totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard Date().timeIntervalSince(last) > 0.1 else { return }
        last = Date()
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var v: Int64 = 0
    var value: Int64 { lock.lock(); defer { lock.unlock() }; return v }
    /// Stores the new value and returns the old one.
    func swap(_ n: Int64) -> Int64 { lock.lock(); defer { lock.unlock() }; let old = v; v = n; return old }
}

final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var done: Int64 = 0
    private let total: Int64
    private let report: @Sendable (Int64, Int64) -> Void

    init(total: Int64, report: @escaping @Sendable (Int64, Int64) -> Void) {
        self.total = total
        self.report = report
    }

    func add(_ n: Int64) {
        lock.lock()
        done += n
        let d = done
        lock.unlock()
        report(d, total)
    }
}

// MARK: - XML helpers

extension XMLElement {
    func children(named name: String) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { ($0.localName ?? $0.name) == name }
    }
    func child(_ name: String) -> XMLElement? { children(named: name).first }
    func descendants(named name: String) -> [XMLElement] {
        var out: [XMLElement] = []
        for c in (children ?? []).compactMap({ $0 as? XMLElement }) {
            if (c.localName ?? c.name) == name { out.append(c) }
            out += c.descendants(named: name)
        }
        return out
    }
    var stringValueTrimmed: String { (stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
}
