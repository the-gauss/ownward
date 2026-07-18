import Foundation
import Network

public final class LocalAPIServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 47771

    private let router: APIRouter
    private let queue = DispatchQueue(label: "com.ownward.local-api", qos: .userInitiated)
    private var listener: NWListener?

    public init(router: APIRouter) { self.router = router }

    public func start(port: UInt16 = LocalAPIServer.defaultPort) throws {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw LocalAPIServerError.invalidPort }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { NSLog("Ownward local API failed: %@", error.localizedDescription) }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var accumulated = buffer
            if let data { accumulated.append(data) }
            if HTTPCodec.isCompleteRequest(accumulated) {
                Task {
                    let response: APIResponse
                    do { response = await self.router.handle(try HTTPCodec.parseRequest(accumulated)) }
                    catch { response = .error(status: 400, message: "Malformed HTTP request.") }
                    connection.send(content: HTTPCodec.encodeResponse(response), completion: .contentProcessed { _ in connection.cancel() })
                }
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: accumulated)
            }
        }
    }
}

public enum LocalAPIServerError: Error { case invalidPort }
