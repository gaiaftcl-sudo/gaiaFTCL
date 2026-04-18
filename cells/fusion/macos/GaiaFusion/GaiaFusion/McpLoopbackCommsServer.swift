import Foundation
@preconcurrency import Swifter

/// Binds **127.0.0.1:8803** (default) and reverse-proxies HTTP to the MCP gateway **upstream** (FusionSidecar guest,
/// host compose, or head tunnel). Local **comms surface** for `mcp_mac_cell_probe`, `fusion_ui_self_heal_loop`,
/// and `MCP_BASE_URL=http://127.0.0.1:8803` without requiring Docker Desktop on the Mac.
///
/// Env:
/// - `GAIAFUSION_MCP_LOOPBACK_DISABLE=1` — do not bind.
/// - `GAIAFUSION_MCP_LOOPBACK_PORT` — default `8803`.
/// - `GAIAFUSION_MCP_COMMS_UPSTREAM` — full base URL, e.g. `http://192.168.64.10:8803` (FusionSidecar guest).
///   If unset, defaults to `http://192.168.64.10:8803`; `MCP_BASE_URL` is also honored when set.
enum McpLoopbackCommsServer {
    private static let proxyHttp = HttpServer()
    private static let stateLock = NSLock()
    /// Protected by `stateLock` (Swift 6 global-mutable workaround).
    nonisolated(unsafe) private static var startedFlag = false
    nonisolated(unsafe) private static var middlewareInstalled = false

    static func startIfConfigured() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !startedFlag else { return }
        if ProcessInfo.processInfo.environment["GAIAFUSION_MCP_LOOPBACK_DISABLE"] == "1" {
            return
        }
        let port = Int(ProcessInfo.processInfo.environment["GAIAFUSION_MCP_LOOPBACK_PORT"] ?? "8803") ?? 8803
        guard port > 0, port <= 65_535 else { return }
        guard let upstream = resolveUpstreamBase() else {
            print("McpLoopbackCommsServer: skip (no upstream base URL)")
            return
        }
        guard let base = URL(string: upstream), let scheme = base.scheme, let host = base.host else {
            print("McpLoopbackCommsServer: invalid GAIAFUSION_MCP_COMMS_UPSTREAM=\(upstream)")
            return
        }
        let basePort = base.port ?? (scheme == "https" ? 443 : 80)

        if !middlewareInstalled {
            proxyHttp.middleware.append { request in
                Self.proxyMiddleware(
                    request: request,
                    scheme: scheme,
                    upstreamHost: host,
                    upstreamPort: basePort,
                    upstreamPathPrefix: base.path
                )
            }
            middlewareInstalled = true
        }

        do {
            try proxyHttp.start(UInt16(port), forceIPv4: true)
            startedFlag = true
            print("McpLoopbackCommsServer: 127.0.0.1:\(port) → \(upstream) (MCP comms surface)")
            fflush(stdout)
        } catch {
            print("McpLoopbackCommsServer: bind 127.0.0.1:\(port) failed: \(error.localizedDescription) (port may be in use)")
            fflush(stdout)
        }
    }

    static func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard startedFlag else { return }
        proxyHttp.stop()
        startedFlag = false
    }

    private static func resolveUpstreamBase() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["GAIAFUSION_MCP_COMMS_UPSTREAM"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw.hasPrefix("http") ? raw : "http://\(raw)"
        }
        if let raw = env["MCP_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw.hasPrefix("http") ? raw : "http://\(raw)"
        }
        return "http://192.168.64.10:8803"
    }

    private final class ProxyResultBox: @unchecked Sendable {
        var data = Data()
        var statusCode = 502
        var headers: [String: String] = [:]
    }

    private static func proxyMiddleware(
        request: HttpRequest,
        scheme: String,
        upstreamHost: String,
        upstreamPort: Int,
        upstreamPathPrefix: String
    ) -> HttpResponse? {
        var path = request.path
        if path.isEmpty { path = "/" }
        let prefix = upstreamPathPrefix.hasSuffix("/") ? String(upstreamPathPrefix.dropLast()) : upstreamPathPrefix
        if !prefix.isEmpty, prefix != "/" {
            path = prefix + (path.hasPrefix("/") ? path : "/\(path)")
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = upstreamHost
        components.port = upstreamPort
        if !path.hasPrefix("/") {
            path = "/\(path)"
        }
        components.path = path
        if !request.queryParams.isEmpty {
            components.queryItems = request.queryParams.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else {
            return .raw(500, "Bad upstream URL", ["Content-Type": "text/plain"]) { w in
                try w.write(Data("bad url".utf8))
            }
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body.isEmpty ? nil : Data(request.body)
        urlRequest.setValue("\(upstreamHost):\(upstreamPort)", forHTTPHeaderField: "Host")
        for (k, v) in request.headers where k.lowercased() != "host" {
            urlRequest.setValue(v, forHTTPHeaderField: k)
        }
        urlRequest.timeoutInterval = 60

        let box = ProxyResultBox()
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: urlRequest) { data, response, _ in
            box.data = data ?? Data()
            if let http = response as? HTTPURLResponse {
                box.statusCode = http.statusCode
                for (k, v) in http.allHeaderFields {
                    if let key = k as? String, let val = v as? String {
                        box.headers[key] = val
                    }
                }
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 65)
        let filtered = box.headers.filter { !["transfer-encoding", "Transfer-Encoding"].contains($0.key) }
        return .raw(box.statusCode, "proxy", filtered) { writer in
            try writer.write(box.data)
        }
    }
}
