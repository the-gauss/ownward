import Foundation

public enum HTTPCodecError: Error { case malformedRequest, incompleteRequest }

public enum HTTPCodec {
    public static func parseRequest(_ data: Data) throws -> APIRequest {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { throw HTTPCodecError.incompleteRequest }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { throw HTTPCodecError.malformedRequest }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw HTTPCodecError.malformedRequest }
        let pieces = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard pieces.count == 3 else { throw HTTPCodecError.malformedRequest }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let target = pieces[1]
        let components = URLComponents(string: "http://localhost\(target)")
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        let bodyStart = headerRange.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count >= bodyStart + contentLength else { throw HTTPCodecError.incompleteRequest }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return APIRequest(method: pieces[0], path: components?.path ?? target, query: query, headers: headers, body: body)
    }

    public static func isCompleteRequest(_ data: Data) -> Bool {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
              let text = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return false }
        let contentLength = text.components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { line in
                let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2 else { return nil }
                return Int(pieces[1].trimmingCharacters(in: .whitespaces))
            } ?? 0
        return data.count >= headerRange.upperBound + contentLength
    }

    public static func encodeResponse(_ response: APIResponse) -> Data {
        let reason = reasonPhrase(for: response.status)
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        let headerLines = headers.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\r\n")
        var data = Data("HTTP/1.1 \(response.status) \(reason)\r\n\(headerLines)\r\n\r\n".utf8)
        data.append(response.body)
        return data
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Response"
        }
    }
}
