import Foundation
import Testing
@testable import OwnwardServices

@Suite("Local HTTP codec")
struct HTTPCodecTests {
    @Test("parses query, bearer token, and JSON body")
    func parsesRequest() throws {
        let body = #"{"title":"System Design"}"#
        let raw = """
        POST /v1/tasks?board_id=abc HTTP/1.1\r
        Host: 127.0.0.1\r
        Authorization: Bearer secret\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        let request = try HTTPCodec.parseRequest(Data(raw.utf8))

        #expect(request.method == "POST")
        #expect(request.path == "/v1/tasks")
        #expect(request.query["board_id"] == "abc")
        #expect(request.headers["authorization"] == "Bearer secret")
        #expect(String(decoding: request.body, as: UTF8.self) == body)
    }

    @Test("encodes a complete close-delimited response")
    func encodesResponse() {
        let response = APIResponse(status: 201, body: Data("{}".utf8))
        let raw = String(decoding: HTTPCodec.encodeResponse(response), as: UTF8.self)
        #expect(raw.contains("HTTP/1.1 201 Created"))
        #expect(raw.contains("Content-Length: 2"))
        #expect(raw.hasSuffix("\r\n\r\n{}"))
    }

    @Test("empty content-length headers are handled without indexing past the split")
    func handlesEmptyContentLength() {
        let raw = "POST /v1/tasks HTTP/1.1\r\nContent-Length:\r\n\r\n"
        #expect(HTTPCodec.isCompleteRequest(Data(raw.utf8)))
    }
}
