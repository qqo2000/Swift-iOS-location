//
//  HTTPServer.swift
//  LocationSpoofer
//
//  轻量级 HTTP 服务器（纯 Swift，无第三方依赖）
//  基于 BSD socket，仅用于本地内网通信
//

import Foundation

// MARK: - HTTP Request / Response

struct HTTPRequest {
    let method: String
    let path: String
    let queryParams: [String: String]
    let headers: [String: String]
    let body: Data?
}

class HTTPResponse {
    var status: Int = 200
    var contentType: String = "application/json"
    var body: Data = Data()
    var headers: [String: String] = [:]
    var cacheControl: String?

    func send() {
        // sent by server after route handler completes
    }

    func json(_ object: Any) {
        contentType = "application/json"
        if let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted) {
            body = data
        }
    }
}

// MARK: - Mini HTTP Server

class HTTPServer {
    private var listenSocket: Int32 = -1
    private var running = false
    private var routes: [(method: String, pattern: String, handler: (HTTPRequest, HTTPResponse) -> Void)] = []

    func route(_ method: String, _ pattern: String, handler: @escaping (HTTPRequest, HTTPResponse) -> Void) {
        routes.append((method: method.uppercased(), pattern: pattern, handler: handler))
    }

    func start(port: Int) throws {
        listenSocket = socket(AF_INET6, Int32(SOCK_STREAM.rawValue), 0)
        if listenSocket < 0 {
            listenSocket = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        }
        if listenSocket < 0 {
            throw NSError(domain: "HTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "socket() failed"])
        }

        // Allow port reuse
        var reuse: Int32 = 1
        setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind
        var addr = sockaddr_in6()
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = UInt16(port).bigEndian
        addr.sin6_addr = in6addr_any // bind to all interfaces

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(listenSocket, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }

        if bindResult < 0 {
            // Fallback to IPv4
            close(listenSocket)
            listenSocket = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
            var addr4 = sockaddr_in()
            addr4.sin_family = sa_family_t(AF_INET)
            addr4.sin_port = UInt16(port).bigEndian
            addr4.sin_addr.s_addr = INADDR_ANY.bigEndian
            let r = withUnsafePointer(to: &addr4) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    bind(listenSocket, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if r < 0 {
                throw NSError(domain: "HTTPServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "bind() failed on port \(port)"])
            }
        }

        // Listen
        if listen(listenSocket, 10) < 0 {
            throw NSError(domain: "HTTPServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "listen() failed"])
        }

        running = true

        // Accept loop in background
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            while self.running {
                var clientAddr = sockaddr_storage()
                var clientLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
                let clientSocket = accept(self.listenSocket, withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
                }, &clientLen)

                if clientSocket < 0 { continue }
                DispatchQueue.global(qos: .userInitiated).async {
                    self.handleClient(clientSocket)
                }
            }
        }
    }

    func stop() {
        running = false
        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
    }

    // MARK: - Client handling

    private func handleClient(_ clientSocket: Int32) {
        defer { close(clientSocket) }

        // Read request
        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)
        if bytesRead <= 0 { return }

        let requestData = Data(buffer[0..<bytesFound])
        guard let requestStr = String(data: requestData, encoding: .utf8) else {
            // Binary data - handle as raw bytes for POST body
            return
        }
        _ = requestStr

        // Parse HTTP request
        let lines = requestStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let method = parts[0]
        let fullPath = parts[1]

        // Parse path and query
        var pathStr = fullPath
        var queryParams: [String: String] = [:]
        if let questionIdx = fullPath.firstIndex(of: "?") {
            pathStr = String(fullPath[..<questionIdx])
            let queryString = String(fullPath[fullPath.index(after: questionIdx)...])
            for pair in queryString.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    queryParams[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        }

        // Parse headers
        var headers: [String: String] = [:]
        var bodyStart = 0
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty {
                // Body starts after this
                bodyStart = i + 1
                break
            }
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key.lowercased()] = value
            }
        }

        // Parse body
        var body: Data? = nil
        if bodyStart < lines.count {
            let bodyStr = lines[bodyStart...].joined(separator: "\r\n")
            body = bodyStr.data(using: .utf8)
        }

        let request = HTTPRequest(
            method: method,
            path: pathStr,
            queryParams: queryParams,
            headers: headers,
            body: body
        )

        // Match route
        let response = HTTPResponse()
        var matched = false
        for route in routes {
            if route.method == method.uppercased() {
                if pathMatches(route.pattern, pathStr) {
                    route.handler(request, response)
                    matched = true
                    break
                }
            }
        }

        if !matched {
            response.status = 404
            response.body = "Not Found".data(using: .utf8)!
        }

        // Send response
        let statusText: String
        switch response.status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "OK"
        }

        var responseStr = "HTTP/1.1 \(response.status) \(statusText)\r\n"
        responseStr += "Content-Type: \(response.contentType)\r\n"
        responseStr += "Content-Length: \(response.body.count)\r\n"
        responseStr += "Access-Control-Allow-Origin: *\r\n"
        responseStr += "Cache-Control: \(response.cacheControl ?? "no-store")\r\n"
        for (key, value) in response.headers {
            responseStr += "\(key): \(value)\r\n"
        }
        responseStr += "\r\n"

        var responseData = responseStr.data(using: .utf8)!
        responseData.append(response.body)

        let _ = responseData.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Int in
            return send(clientSocket, buf.baseAddress, buf.count, 0)
        }
    }

    // MARK: - Utilities

    private var bytesFound: Int = 0

    private func pathMatches(_ pattern: String, _ path: String) -> Bool {
        // Normalize: strip trailing slash
        let p = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
        let actual = path.hasSuffix("/") ? String(path.dropLast()) : path

        if p == "/" {
            return actual == "" || actual == "/"
        }

        // Check if path starts with pattern (prefix match for /local-module/ etc.)
        if actual == p {
            return true
        }
        // For wildcard matching
        if actual.hasPrefix(p + "/") {
            return true
        }
        return false
    }
}
