import Foundation
import Network

final class RedirectServer {
    private var listener: NWListener?

    var isRunning: Bool {
        listener != nil
    }

    func start() throws {
        guard listener == nil else { return }
        let port = NWEndpoint.Port(rawValue: 8765)!
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            self.receiveRequest(on: connection)
        }
        listener.start(queue: .global())
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let firstLine = request.split(separator: "\n").first ?? ""
            if let path = firstLine.split(separator: " ").dropFirst().first,
               let url = URL(string: "http://127.0.0.1\(path)") {
                AuthRedirectHandler.shared.handle(url: url)
            }

            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nYou can close this window."
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
