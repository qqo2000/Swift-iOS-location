//
//  HTTPServerManager.swift
//  LocationSpoofer
//
//  内置 HTTP 服务器：
//  1. 托管 location-spoofer.js 脚本（代理软件 script-path 拉取）
//  2. 提供 /loc.json 坐标读写 API
//  3. 提供动态生成模块文件的 /local-module/ 端点
//

import Foundation
import Combine

class HTTPServerManager: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var serverAddress: String = ""
    @Published var statusMessage: String = "未启动"

    private var server: HTTPServer?
    private var token: String = ""
    private var port: Int = 18099
    private weak var configManager: LocationConfigManager?

    func start(token: String, port: Int, configManager: LocationConfigManager) {
        self.token = token
        self.port = port
        self.configManager = configManager

        DispatchQueue.global(qos: .background).async {
            let sv = HTTPServer()
            self.server = sv

            sv.route("GET", "/loc.json") { req, res in
                if !self.checkToken(req, res) { return }
                let json = configManager.configToJSON()
                res.json(json)
            }

            sv.route("GET", "/status") { req, res in
                if !self.checkToken(req, res) { return }
                res.json([
                    "server": "LocationSpoofer-iOS",
                    "version": "1.0",
                    "token_ok": true,
                    "current_location": [
                        "latitude": configManager.config.latitude,
                        "longitude": configManager.config.longitude,
                        "altitude": configManager.config.altitude,
                        "enabled": configManager.config.enabled
                    ],
                    "port": self.port
                ])
            }

            sv.route("GET", "/js/location-spoofer.js") { req, res in
                if !self.checkToken(req, res) { return }
                if let js = self.loadScript("location-spoofer") {
                    res.contentType = "application/javascript; charset=utf-8"
                    res.body = js.data(using: .utf8) ?? Data()
                    res.cacheControl = "public, max-age=3600"
                    res.send()
                } else {
                    res.status = 404
                    res.body = "Script not found".data(using: .utf8)!
                    res.send()
                }
            }

            sv.route("GET", "/js/location-spoofer-qx.js") { req, res in
                if !self.checkToken(req, res) { return }
                if let js = self.loadScript("location-spoofer-qx") {
                    res.contentType = "application/javascript; charset=utf-8"
                    res.body = js.data(using: .utf8) ?? Data()
                    res.send()
                } else {
                    res.status = 404; res.send()
                }
            }

            sv.route("POST", "/set") { req, res in
                if !self.checkToken(req, res) { return }
                guard let body = req.body,
                      let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                      let lat = json["lat"] as? Double,
                      let lng = json["lng"] as? Double else {
                    res.status = 400
                    res.json(["error": "bad coords"])
                    return
                }
                let alt = json["altitude"] as? Int
                let hAcc = json["horizontalAccuracy"] as? Int
                let vAcc = json["verticalAccuracy"] as? Int

                DispatchQueue.main.async {
                    configManager.updateLocation(lat: lat, lng: lng, alt: alt, hAcc: hAcc, vAcc: vAcc)
                }

                res.json(configManager.configToJSON())
            }

            sv.route("POST", "/enable") { req, res in
                if !self.checkToken(req, res) { return }
                let enableVal: Bool
                if let body = req.body,
                   let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let enabled = json["enabled"] as? Bool {
                    enableVal = enabled
                } else {
                    enableVal = true
                }

                DispatchQueue.main.async {
                    if configManager.config.enabled != enableVal {
                        configManager.toggleEnabled()
                    }
                }
                res.json(["enabled": enableVal])
            }

            // 动态生成模块文件
            sv.route("GET", "/local-module/") { req, res in
                if !self.checkToken(req, res) { return }
                self.serveModuleFile(req: req, res: res)
            }

            // 首页
            sv.route("GET", "/") { req, res in
                if !self.checkToken(req, res) { return }
                res.contentType = "application/json"
                res.json([
                    "app": "LocationSpoofer",
                    "message": "Server running. Use the app UI to manage locations.",
                    "endpoints": [
                        "/loc.json?token=TOKEN",
                        "/js/location-spoofer.js?token=TOKEN",
                        "/status?token=TOKEN",
                        "/set?token=TOKEN (POST)",
                        "/enable?token=TOKEN (POST)"
                    ]
                ])
            }

            do {
                try sv.start(port: port)
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.statusMessage = "运行中"
                    let ip = self.getIPAddress() ?? "127.0.0.1"
                    self.serverAddress = "http://\(ip):\(port)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.statusMessage = "启动失败: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        server?.stop()
        isRunning = false
        statusMessage = "已停止"
    }

    // MARK: - Private

    private func checkToken(_ req: HTTPRequest, _ res: HTTPResponse) -> Bool {
        let queryToken = req.queryParams["token"] ?? ""
        if queryToken.isEmpty {
            res.status = 401
            res.json(["error": "missing token"])
            return false
        }
        if queryToken != token {
            res.status = 403
            res.json(["error": "bad token"])
            return false
        }
        return true
    }

    private func loadScript(_ name: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: "js"),
           let data = try? String(contentsOf: url, encoding: .utf8) {
            return data
        }
        return nil
    }

    private func serveModuleFile(req: HTTPRequest, res: HTTPResponse) {
        let path = req.path
        let fileName = String(path.dropFirst("/local-module/".count))
        let host = req.queryParams["host"] ?? req.headers["host"] ?? "localhost:\(port)"
        let scriptBase = "http://\(host)/js/location-spoofer.js?token=\(token)"
        let configUrl = "http://\(host)/loc.json?token=\(token)"

        var content = ""

        switch fileName {
        case "ios-location-spoofer-local.sgmodule":
            content = """
            #!name=iOS Location Spoofer (Local)
            #!desc=拦截 Apple 定位服务器回应的 GPS 坐标，替换成自定义位置。
            [Script]
            iOS Location Spoofer = type=http-response,pattern=^https?:\\/\\/(?:gs-loc(?:-cn)?\\.apple\\.com|gsp-ssl\\.ls\\.apple\\.com|bluedot\\.is\\.autonavi\\.com(?:\\.gds\\.alibabadns\\.com)?)\\/clls\\/wloc(?:\\?.*)?$,requires-body=1,binary-body-mode=1,max-size=1048576,timeout=10,script-path=\(scriptBase),argument=mode=response&latitude=\(configManager?.config.latitude ?? 37.3349)&longitude=\(configManager?.config.longitude ?? -122.00902)&horizontalAccuracy=\(configManager?.config.horizontalAccuracy ?? 39)&verticalAccuracy=\(configManager?.config.verticalAccuracy ?? 1000)&altitude=\(configManager?.config.altitude ?? 530)&debug=true&configUrl=\(configUrl.urlEncoded)

            [MITM]
            hostname = %APPEND% gs-loc.apple.com, gs-loc-cn.apple.com, gsp-ssl.ls.apple.com, bluedot.is.autonavi.com, bluedot.is.autonavi.com.gds.alibabadns.com
            """
        case "ios-location-spoofer-local.lnplugin":
            content = """
            #!name=iOS Location Spoofer (Local)
            #!desc=拦截 Apple 定位服务回传的坐标并置换为指定位置（Loon 插件 - 本地服务器版）

            [Argument]
            enabled = switch,true,tag=启用定位修改
            latitude = input,"\(configManager?.config.latitude ?? 37.3349)",tag=纬度(备用)
            longitude = input,"\(configManager?.config.longitude ?? -122.00902)",tag=经度(备用)
            altitude = input,"\(configManager?.config.altitude ?? 530)",tag=海拔(米)
            horizontalAccuracy = input,"\(configManager?.config.horizontalAccuracy ?? 39)",tag=水平精度
            verticalAccuracy = input,"\(configManager?.config.verticalAccuracy ?? 1000)",tag=垂直精度
            address = input,"",tag=地址搜索
            configHost = input,"http://\(host)",tag=配置服务器
            configToken = input,"\(token)",tag=配置Token
            configUrl = input,"",tag=远程配置URL
            debug = switch,true,tag=调试日志

            [Script]
            http-request ^https?:\\/\\/(?:gs-loc(?:-cn)?\\.apple\\.com|gsp-ssl\\.ls\\.apple\\.com|bluedot\\.is\\.autonavi\\.com(?:\\.gds\\.alibabadns\\.com)?)\\/clls\\/wloc(?:\\?.*)?$ script-path=\(scriptBase), requires-body=false, timeout=3, tag=iOS Location Spoofer Prepare, argument=[{debug}]
            http-response ^https?:\\/\\/(?:gs-loc(?:-cn)?\\.apple\\.com|gsp-ssl\\.ls\\.apple\\.com|bluedot\\.is\\.autonavi\\.com(?:\\.gds\\.alibabadns\\.com)?)\\/clls\\/wloc(?:\\?.*)?$ script-path=\(scriptBase), requires-body=true, binary-body-mode=true, max-size=1048576, timeout=12, tag=iOS Location Spoofer, argument=[{enabled},{latitude},{longitude},{altitude},{horizontalAccuracy},{verticalAccuracy},{address},{configHost},{configToken},{configUrl},{debug}]
            cron "*/15 * * * *" script-path=\(scriptBase), timeout=30, tag=iOS Location Spoofer Sync, argument=[{address},{configHost},{configToken},{configUrl},{debug}]

            [mitm]
            hostname = gs-loc.apple.com, gs-loc-cn.apple.com, gsp-ssl.ls.apple.com, bluedot.is.autonavi.com, bluedot.is.autonavi.com.gds.alibabadns.com
            """
        case "ios-location-spoofer-surge-local.sgmodule":
            content = """
            #!name=iOS Location Spoofer (Local)
            #!desc=拦截 Apple 定位服务器回应的 GPS 坐标，替换成自定义位置。本地服务器版（Surge）。
            #!arguments=latitude:\(configManager?.config.latitude ?? 37.3349),longitude:\(configManager?.config.longitude ?? -122.00902),altitude:\(configManager?.config.altitude ?? 530),horizontalAccuracy:\(configManager?.config.horizontalAccuracy ?? 39),verticalAccuracy:\(configManager?.config.verticalAccuracy ?? 1000),debug:false

            [Script]
            iOS Location Spoofer = type=http-response,pattern=^https?:\\/\\/(?:gs-loc(?:-cn)?\\.apple\\.com|gsp-ssl\\.ls\\.apple\\.com|bluedot\\.is\\.autonavi\\.com(?:\\.gds\\.alibabadns\\.com)?)\\/clls\\/wloc(?:\\?.*)?$,requires-body=1,binary-body-mode=1,max-size=1048576,timeout=10,script-path=\(scriptBase),argument=mode=response&latitude={{{latitude}}}&longitude={{{longitude}}}&horizontalAccuracy={{{horizontalAccuracy}}}&verticalAccuracy={{{verticalAccuracy}}}&altitude={{{altitude}}}&debug={{{debug}}}&configUrl=\(configUrl.urlEncoded)

            [MITM]
            hostname = %APPEND% gs-loc.apple.com, gs-loc-cn.apple.com, gsp-ssl.ls.apple.com, bluedot.is.autonavi.com, bluedot.is.autonavi.com.gds.alibabadns.com
            """
        case "ios-location-spoofer-local.stoverride":
            content = """
            name: iOS Location Spoofer (Local)
            desc: 劫持 Apple 定位封包，把坐标换成你想要的。本地服务器版（Stash）。

            http:
              script:
                - match: ^https?:\\/\\/(?:gs-loc(?:-cn)?\\.apple\\.com|gsp-ssl\\.ls\\.apple\\.com|bluedot\\.is\\.autonavi\\.com(?:\\.gds\\.alibabadns\\.com)?)\\/clls\\/wloc(?:\\?.*)?$
                  name: ios-location-spoofer
                  type: response
                  require-body: true
                  binary-mode: true
                  max-size: 1048576
                  timeout: 10
                  argument: mode=response&latitude=\(configManager?.config.latitude ?? 37.3349)&longitude=\(configManager?.config.longitude ?? -122.00902)&horizontalAccuracy=\(configManager?.config.horizontalAccuracy ?? 39)&verticalAccuracy=\(configManager?.config.verticalAccuracy ?? 1000)&altitude=\(configManager?.config.altitude ?? 530)&debug=false&configUrl=\(configUrl.urlEncoded)
              mitm:
                - gs-loc.apple.com
                - gs-loc-cn.apple.com
                - gsp-ssl.ls.apple.com
                - bluedot.is.autonavi.com
                - bluedot.is.autonavi.com.gds.alibabadns.com

            script-providers:
              ios-location-spoofer:
                url: \(scriptBase)
                interval: 86400
            """
        case "ios-location-spoofer-local.snippet":
            let qxBase = "http://\(host)/js/location-spoofer-qx.js?token=\(token)"
            content = """
            #!name=iOS Location Spoofer (Local)
            #!desc=透过 MITM 改写 Apple 定位回应的经纬度。本地服务器版（Quantumult X）。

            [rewrite_local]
            ^https?:\\/\\/(?:gs-loc(?:-cn)?\\.apple\\.com|gsp-ssl\\.ls\\.apple\\.com|bluedot\\.is\\.autonavi\\.com(?:\\.gds\\.alibabadns\\.com)?)\\/clls\\/wloc(?:\\?.*)?$ url script-response-body \(qxBase)

            [mitm]
            hostname = gs-loc.apple.com, gs-loc-cn.apple.com, gsp-ssl.ls.apple.com, bluedot.is.autonavi.com, bluedot.is.autonavi.com.gds.alibabadns.com
            """
        default:
            res.status = 404
            res.body = "Module not found: \(fileName)".data(using: .utf8)!
            res.send()
            return
        }

        res.contentType = "text/plain; charset=utf-8"
        res.body = content.data(using: .utf8)!
        res.headers["Content-Disposition"] = "attachment; filename=\"\(fileName)\""
        res.send()
    }

    private func getIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr!.pointee.ifa_next }

                let interface = ptr!.pointee
                guard let ifaAddr = interface.ifa_addr else { continue }
                let addrFamily = ifaAddr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let nameC = interface.ifa_name
                    let name = nameC != nil ? String(cString: nameC!) : ""
                    if name == "en0" || name == "pdp_ip0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(ifaAddr,
                                    socklen_t(ifaAddr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}

// MARK: - String URL Encoding helper
extension String {
    var urlEncoded: String {
        return self.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
