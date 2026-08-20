//
//  LocationConfigManager.swift
//  LocationSpoofer
//
//  管理坐标配置的持久化存储
//

import Foundation
import Combine

struct LocationConfig: Codable {
    var enabled: Bool = true
    var latitude: Double = 37.3349
    var longitude: Double = -122.00902
    var altitude: Int = 530
    var horizontalAccuracy: Int = 39
    var verticalAccuracy: Int = 1000
    var unknownValue4: Int = 3
    var motionActivityType: Int = 63
    var motionActivityConfidence: Int = 467
    var failOpen: Bool = true
    var debug: Bool = true
}

class LocationConfigManager: ObservableObject {
    @Published var config: LocationConfig = LocationConfig()
    @Published var token: String = ""
    @Published var port: Int = 18099
    @Published var serverRunning: Bool = false
    @Published var savedLocations: [SavedLocation] = []

    struct SavedLocation: Codable, Identifiable {
        var id = UUID()
        var name: String
        var latitude: Double
        var longitude: Double
        var altitude: Int?
        var horizontalAccuracy: Int?
    }

    private let defaults = UserDefaults.standard
    private let configKey = "locationSpooferConfig"
    private let tokenKey = "locationSpooferToken"
    private let portKey = "locationSpooferPort"
    private let savedKey = "locationSpooferSaved"

    func loadConfig() {
        if let data = defaults.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(LocationConfig.self, from: data) {
            config = decoded
        }

        if let savedToken = defaults.string(forKey: tokenKey), !savedToken.isEmpty {
            token = savedToken
        } else {
            token = generateToken()
            defaults.set(token, forKey: tokenKey)
        }

        port = defaults.integer(forKey: portKey)
        if port == 0 { port = 18099 }

        if let savedData = defaults.data(forKey: savedKey),
           let decoded = try? JSONDecoder().decode([SavedLocation].self, from: savedData) {
            savedLocations = decoded
        }
    }

    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: configKey)
        }
    }

    func saveToken(_ newToken: String) {
        token = newToken
        defaults.set(newToken, forKey: tokenKey)
    }

    func savePort(_ newPort: Int) {
        port = newPort
        defaults.set(newPort, forKey: portKey)
    }

    func updateLocation(lat: Double, lng: Double, alt: Int?, hAcc: Int?, vAcc: Int?) {
        config.latitude = lat
        config.longitude = lng
        config.enabled = true
        if let alt = alt { config.altitude = alt }
        if let hAcc = hAcc { config.horizontalAccuracy = hAcc }
        if let vAcc = vAcc { config.verticalAccuracy = vAcc }
        saveConfig()
    }

    func toggleEnabled() {
        config.enabled.toggle()
        saveConfig()
    }

    func addSavedLocation(name: String, lat: Double, lng: Double, alt: Int?, hAcc: Int?) {
        let loc = SavedLocation(name: name, latitude: lat, longitude: lng, altitude: alt, horizontalAccuracy: hAcc)
        savedLocations.insert(loc, at: 0)
        if savedLocations.count > 12 {
            savedLocations = Array(savedLocations.prefix(12))
        }
        saveSavedLocations()
    }

    func removeSavedLocation(at index: Int) {
        if index < savedLocations.count {
            savedLocations.remove(at: index)
            saveSavedLocations()
        }
    }

    private func saveSavedLocations() {
        if let data = try? JSONEncoder().encode(savedLocations) {
            defaults.set(data, forKey: savedKey)
        }
    }

    private func generateToken() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<32).map { _ in letters.randomElement()! })
    }

    func configToJSON() -> [String: Any] {
        return [
            "enabled": config.enabled,
            "latitude": config.latitude,
            "longitude": config.longitude,
            "altitude": config.altitude,
            "horizontalAccuracy": config.horizontalAccuracy,
            "verticalAccuracy": config.verticalAccuracy,
            "unknownValue4": config.unknownValue4,
            "motionActivityType": config.motionActivityType,
            "motionActivityConfidence": config.motionActivityConfidence,
            "failOpen": config.failOpen,
            "debug": config.debug
        ]
    }
}
