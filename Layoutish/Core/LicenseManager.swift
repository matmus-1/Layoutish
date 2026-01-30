//
//  LicenseManager.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import Foundation
import Security
import AppKit
import IOKit
import Combine

// MARK: - License Status

enum LicenseStatus: Equatable {
    case unknown
    case valid(expiresAt: Date?)
    case invalid(reason: String)
    case expired
    case noLicense
}

// MARK: - License Response Models

struct LicenseActivationResponse: Codable {
    let activated: Bool?
    let valid: Bool?
    let error: String?
    let licenseKey: LicenseKeyData?
    let instance: InstanceData?
    let meta: MetaData?

    var isSuccess: Bool {
        return activated == true || valid == true
    }

    enum CodingKeys: String, CodingKey {
        case activated
        case valid
        case error
        case licenseKey = "license_key"
        case instance
        case meta
    }
}

struct LicenseKeyData: Codable {
    let id: Int
    let status: String
    let key: String
    let activationLimit: Int
    let activationUsage: Int
    let createdAt: String
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case key
        case activationLimit = "activation_limit"
        case activationUsage = "activation_usage"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct InstanceData: Codable {
    let id: String
    let name: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
    }
}

struct MetaData: Codable {
    let storeId: Int?
    let orderId: Int?
    let productId: Int?
    let productName: String?
    let variantId: Int?
    let variantName: String?
    let customerId: Int?
    let customerName: String?
    let customerEmail: String?

    enum CodingKeys: String, CodingKey {
        case storeId = "store_id"
        case orderId = "order_id"
        case productId = "product_id"
        case productName = "product_name"
        case variantId = "variant_id"
        case variantName = "variant_name"
        case customerId = "customer_id"
        case customerName = "customer_name"
        case customerEmail = "customer_email"
    }
}

// MARK: - License Manager

@MainActor
final class LicenseManager: ObservableObject {

    // MARK: - Singleton

    static let shared = LicenseManager()

    // MARK: - Published State

    @Published private(set) var status: LicenseStatus = .unknown
    @Published private(set) var isValidating: Bool = false
    @Published private(set) var customerEmail: String?
    @Published private(set) var productName: String?

    // MARK: - Constants

    private let licenseKeyKey = "com.appish.layoutish.licenseKey"
    private let instanceIdKey = "com.appish.layoutish.instanceId"
    private let lemonSqueezyAPIBase = "https://api.lemonsqueezy.com/v1/licenses"

    // MARK: - Computed Properties

    var isLicensed: Bool {
        if case .valid = status { return true }
        return false
    }

    var storedLicenseKey: String? {
        UserDefaults.standard.string(forKey: licenseKeyKey)
    }

    var instanceId: String {
        if let existing = UserDefaults.standard.string(forKey: instanceIdKey) {
            return existing
        }

        let newId = getMachineUUID() ?? UUID().uuidString
        UserDefaults.standard.set(newId, forKey: instanceIdKey)
        return newId
    }

    // MARK: - Initialization

    private init() {
        Task {
            await checkExistingLicense()
        }
    }

    // MARK: - Public API

    /// Check if there's a stored license and validate it
    func checkExistingLicense() async {
        guard let licenseKey = storedLicenseKey else {
            status = .noLicense
            return
        }

        await validateLicense(key: licenseKey, activate: false)
    }

    /// Activate a new license key
    func activateLicense(key: String) async -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            status = .invalid(reason: "Please enter a license key")
            return false
        }

        return await validateLicense(key: trimmedKey, activate: true)
    }

    /// Deactivate the current license
    func deactivateLicense() async -> Bool {
        guard let licenseKey = storedLicenseKey else { return true }

        isValidating = true
        defer { isValidating = false }

        let url = URL(string: "\(lemonSqueezyAPIBase)/deactivate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "license_key", value: licenseKey),
            URLQueryItem(name: "instance_id", value: instanceId)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            removeLicenseKey()
            status = .noLicense
            customerEmail = nil
            productName = nil
            return true
        } catch {
            removeLicenseKey()
            status = .noLicense
            customerEmail = nil
            productName = nil
            return true
        }
    }

    /// Remove license locally (without deactivating on server)
    func removeLicenseLocally() {
        removeLicenseKey()
        status = .noLicense
        customerEmail = nil
        productName = nil
    }

    // MARK: - Private Methods

    @discardableResult
    private func validateLicense(key: String, activate: Bool) async -> Bool {
        isValidating = true
        defer { isValidating = false }

        let endpoint = activate ? "activate" : "validate"
        let url = URL(string: "\(lemonSqueezyAPIBase)/\(endpoint)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var queryItems = [URLQueryItem(name: "license_key", value: key)]
        if activate {
            let instanceName = Host.current().localizedName ?? "Mac"
            queryItems.append(URLQueryItem(name: "instance_name", value: instanceName))
        }

        var components = URLComponents()
        components.queryItems = queryItems
        request.httpBody = components.query?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                status = .invalid(reason: "Invalid response from server")
                return false
            }

            let decoder = JSONDecoder()

            if httpResponse.statusCode == 200 {
                if let result = try? decoder.decode(LicenseActivationResponse.self, from: data) {
                    if result.isSuccess {
                        saveLicenseKey(key)

                        var expiryDate: Date?
                        if let expiresAt = result.licenseKey?.expiresAt {
                            let formatter = ISO8601DateFormatter()
                            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            expiryDate = formatter.date(from: expiresAt)
                        }

                        customerEmail = result.meta?.customerEmail
                        productName = result.meta?.productName

                        status = .valid(expiresAt: expiryDate)
                        NSLog("[License] Validated successfully for: \(customerEmail ?? "unknown")")
                        return true
                    } else {
                        let reason = result.error ?? "License key is not valid"
                        status = .invalid(reason: reason)
                        return false
                    }
                }
            }

            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? String {
                status = .invalid(reason: error)
            } else {
                status = .invalid(reason: "Failed to validate license (HTTP \(httpResponse.statusCode))")
            }
            return false

        } catch {
            NSLog("[License] Validation error: \(error)")
            status = .invalid(reason: "Network error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Storage Helpers

    private func saveLicenseKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: licenseKeyKey)
        NSLog("[License] License key saved")
    }

    private func removeLicenseKey() {
        UserDefaults.standard.removeObject(forKey: licenseKeyKey)
        NSLog("[License] License key removed")
    }

    // MARK: - Machine UUID

    private func getMachineUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        defer { IOObjectRelease(platformExpert) }

        guard platformExpert != 0 else { return nil }

        if let serialNumber = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            return serialNumber
        }

        return nil
    }
}
