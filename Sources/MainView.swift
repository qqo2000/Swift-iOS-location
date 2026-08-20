//
//  MainView.swift
//  LocationSpoofer
//
//  主界面：地图选点 + 服务器状态 + 配置面板
//

import SwiftUI
import MapKit

struct MainView: View {
    @EnvironmentObject var server: HTTPServerManager
    @EnvironmentObject var locationManager: LocationConfigManager

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.00902),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var pinLocation = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.00902)
    @State private var altitude: String = "530"
    @State private var horizontalAccuracy: String = "39"
    @State private var verticalAccuracy: String = "1000"
    @State private var searchQuery: String = ""
    @State private var showingSaveAlert = false
    @State private var saveLocationName: String = ""
    @State private var showingSavedLocations = false
    @State private var showingSettings = false
    @State private var showingCopyToast = false
    @State private var copyToastText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Server status bar
                statusBar

                // Map
                MapViewRepresentable(
                    region: $region,
                    pinLocation: $pinLocation,
                    onTap: { coord in
                        pinLocation = coord
                        region.center = coord
                        locationManager.config.latitude = coord.latitude
                        locationManager.config.longitude = coord.longitude
                    }
                )
                .frame(height: 380)
                .ignoresSafeArea(edges: .horizontal)

                // Info bar
                infoBar

                // Options
                optionsBar

                // Action buttons
                actionButtons

                // Server config section
                serverConfigSection
            }
            .navigationBarTitle("定位欺骗", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: { showingSavedLocations = true }) {
                    Image(systemName: "bookmark.fill")
                },
                trailing: Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                }
            )
            .alert("收藏此位置", isPresented: $showingSaveAlert) {
                TextField("名称", text: $saveLocationName)
                Button("收藏") {
                    locationManager.addSavedLocation(
                        name: saveLocationName.isEmpty ? String(format: "%.4f", pinLocation.latitude) : saveLocationName,
                        lat: pinLocation.latitude,
                        lng: pinLocation.longitude,
                        alt: Int(altitude),
                        hAcc: Int(horizontalAccuracy)
                    )
                    saveLocationName = ""
                }
                Button("取消", role: .cancel) { }
            }
            .sheet(isPresented: $showingSavedLocations) {
                SavedLocationsView()
                    .environmentObject(locationManager)
                    .onDisappear { loadCurrentConfig() }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(server)
                    .environmentObject(locationManager)
            }
            .overlay(
                Group {
                    if showingCopyToast {
                        VStack {
                            Spacer()
                            Text(copyToastText)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.black.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding(.bottom, 30)
                        }
                        .transition(.opacity)
                    }
                }
            )
            .onAppear {
                loadCurrentConfig()
                region.center = CLLocationCoordinate2D(
                    latitude: locationManager.config.latitude,
                    longitude: locationManager.config.longitude
                )
                pinLocation = region.center
                altitude = String(locationManager.config.altitude)
                horizontalAccuracy = String(locationManager.config.horizontalAccuracy)
                verticalAccuracy = String(locationManager.config.verticalAccuracy)
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(server.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(server.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(server.serverAddress)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(.systemGray6))
    }

    // MARK: - Info bar

    private var infoBar: some View {
        HStack {
            if !locationManager.config.enabled {
                Text("已恢复真实定位")
                    .foregroundColor(.orange)
                    .font(.subheadline.bold())
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text(String(format: "WGS-84: %.5f, %.5f  海拔 %dm", pinLocation.latitude, pinLocation.longitude, locationManager.config.altitude))
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Options bar

    private var optionsBar: some View {
        HStack(spacing: 12) {
            optionField(title: "海拔(m)", text: $altitude)
            optionField(title: "水平精度", text: $horizontalAccuracy)
            optionField(title: "垂直精度", text: $verticalAccuracy)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func optionField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .frame(width: 80)
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: saveLocation) {
                Label("保存定位", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button(action: toggleEnabled) {
                Label(
                    locationManager.config.enabled ? "恢复真实" : "开启伪造",
                    systemImage: locationManager.config.enabled ? "xmark.circle" : "play.circle.fill"
                )
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(locationManager.config.enabled ? .gray : .orange)

            Button(action: { showingSaveAlert = true }) {
                Image(systemName: "bookmark")
                    .frame(width: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    // MARK: - Server config section

    private var serverConfigSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("模块下载（GitHub CDN 直连）").font(.caption.bold())
            configRow(title: "Shadowrocket", value: "https://cdn.jsdelivr.net/gh/qqo2000/Swift-iOS-location@main/ios-location-spoofer.sgmodule")
            configRow(title: "Loon", value: "https://cdn.jsdelivr.net/gh/qqo2000/Swift-iOS-location@main/ios-location-spoofer.lnplugin")
            configRow(title: "Surge", value: "https://cdn.jsdelivr.net/gh/qqo2000/Swift-iOS-location@main/ios-location-spoofer-surge.sgmodule")
            configRow(title: "Stash", value: "https://cdn.jsdelivr.net/gh/qqo2000/Swift-iOS-location@main/ios-location-spoofer.stoverride")
            configRow(title: "QX", value: "https://cdn.jsdelivr.net/gh/qqo2000/Swift-iOS-location@main/ios-location-spoofer.snippet")
            
            Text("本地服务器配置地址").font(.caption.bold()).padding(.top, 4)
            configRow(title: "Script-Path", value: "\(server.serverAddress)/js/location-spoofer.js?token=\(locationManager.token)")
            configRow(title: "ConfigUrl", value: "\(server.serverAddress)/loc.json?token=\(locationManager.token)")
            configRow(title: "状态页", value: "\(server.serverAddress)/status?token=\(locationManager.token)")
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .background(Color(.systemGray6))
    }

    private func configRow(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Text(value).font(.caption2.monospaced()).lineLimit(1).truncationMode(.middle)
            Button(action: { copyToClipboard(value) }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func saveLocation() {
        locationManager.updateLocation(
            lat: pinLocation.latitude,
            lng: pinLocation.longitude,
            alt: Int(altitude),
            hAcc: Int(horizontalAccuracy),
            vAcc: Int(verticalAccuracy)
        )
        showToast("已保存 · 关开定位生效")
    }

    private func toggleEnabled() {
        locationManager.toggleEnabled()
        showToast(locationManager.config.enabled ? "已开启伪造" : "已恢复真实定位")
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        showToast("已复制")
    }

    private func showToast(_ text: String) {
        copyToastText = text
        withAnimation { showingCopyToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showingCopyToast = false }
        }
    }

    private func loadCurrentConfig() {
        pinLocation = CLLocationCoordinate2D(
            latitude: locationManager.config.latitude,
            longitude: locationManager.config.longitude
        )
        region.center = pinLocation
        altitude = String(locationManager.config.altitude)
        horizontalAccuracy = String(locationManager.config.horizontalAccuracy)
        verticalAccuracy = String(locationManager.config.verticalAccuracy)
    }
}

// MARK: - Map View

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var pinLocation: CLLocationCoordinate2D
    var onTap: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if mapView.region.center.latitude != region.center.latitude ||
           mapView.region.center.longitude != region.center.longitude {
            mapView.setRegion(region, animated: true)
        }

        // Update annotations
        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = pinLocation
        annotation.title = "定位点"
        mapView.addAnnotation(annotation)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapViewRepresentable

        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap(coord)
        }
    }
}

// MARK: - Sub Views

struct SavedLocationsView: View {
    @EnvironmentObject var locationManager: LocationConfigManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(locationManager.savedLocations) { loc in
                    Button(action: {
                        locationManager.config.latitude = loc.latitude
                        locationManager.config.longitude = loc.longitude
                        if let alt = loc.altitude { locationManager.config.altitude = alt }
                        if let hAcc = loc.horizontalAccuracy { locationManager.config.horizontalAccuracy = hAcc }
                        locationManager.saveConfig()
                        dismiss()
                    }) {
                        VStack(alignment: .leading) {
                            Text(loc.name).font(.body)
                            Text(String(format: "%.5f, %.5f", loc.latitude, loc.longitude))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    indexSet.forEach { locationManager.removeSavedLocation(at: $0) }
                }
            }
            .navigationTitle("收藏位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var server: HTTPServerManager
    @EnvironmentObject var locationManager: LocationConfigManager
    @Environment(\.dismiss) var dismiss

    @State private var tokenInput: String = ""
    @State private var portInput: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("服务器设置") {
                    HStack {
                        Text("端口")
                        Spacer()
                        TextField("端口", text: $portInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("TOKEN")
                        Spacer()
                        TextField("TOKEN", text: $tokenInput)
                            .font(.caption.monospaced())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    Button("保存设置") {
                        if let p = Int(portInput), p > 0 {
                            locationManager.savePort(p)
                        }
                        if !tokenInput.isEmpty {
                            locationManager.saveToken(tokenInput)
                        }
                        dismiss()
                    }
                }

                Section("使用说明") {
                    Text("1. 启动 App 后服务器自动运行\n2. 在代理软件中导入模块文件\n3. 开启 MITM + 信任证书\n4. 断开重连 VPN → 开关定位\n5. 打开地图 App 验证")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("MITM 域名") {
                    Text("gs-loc.apple.com\ngs-loc-cn.apple.com\ngsp-ssl.ls.apple.com\nbluedot.is.autonavi.com\nbluedot.is.autonavi.com.gds.alibabadns.com")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                tokenInput = locationManager.token
                portInput = String(locationManager.port)
            }
        }
    }
}
