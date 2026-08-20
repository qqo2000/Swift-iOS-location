//
//  LocationSpooferApp.swift
//  LocationSpoofer
//
//  iOS 定位欺骗一体化 App
//  内置 HTTP 服务器托管脚本 + 地图选点 UI + 坐标管理
//

import SwiftUI

@main
struct LocationSpooferApp: App {
    @StateObject private var server = HTTPServerManager()
    @StateObject private var locationManager = LocationConfigManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(server)
                .environmentObject(locationManager)
                .onAppear {
                    locationManager.loadConfig()
                    server.start(token: locationManager.token, port: locationManager.port, configManager: locationManager)
                }
        }
    }
}
