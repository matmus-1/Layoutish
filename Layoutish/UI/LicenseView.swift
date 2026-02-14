//
//  LicenseView.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import SwiftUI

struct LicenseView: View {
    @ObservedObject private var licenseManager = LicenseManager.shared
    @State private var licenseKey: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var onLicenseActivated: (() -> Void)?

    private let checkoutURL = "https://appish.lemonsqueezy.com/checkout/buy/56819b38-7f1b-4d1b-ba3c-8f74c550f2a5"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.bottom, 24)

            // License Key Input
            inputSection
                .padding(.bottom, 16)

            // Error Message
            if showError {
                errorSection
                    .padding(.bottom, 16)
            }

            // Activate Button
            activateButton
                .padding(.bottom, 24)

            Spacer()

            // Footer
            footerSection
        }
        .padding(32)
        .frame(width: 480, height: 400)
        .onChange(of: licenseManager.status) { newStatus in
            if case .valid = newStatus {
                onLicenseActivated?()
            } else if case .invalid(let reason) = newStatus {
                errorMessage = reason
                showError = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((licenseManager.trialExpired ? Color.red : Color.brandPurple).opacity(0.15))
                    .frame(width: 72, height: 72)

                Image(systemName: licenseManager.trialExpired ? "clock.badge.xmark" : (licenseManager.isInTrial ? "clock.fill" : "key.fill"))
                    .font(.system(size: 32))
                    .foregroundColor(licenseManager.trialExpired ? .red : .brandPurple)
            }

            Text(licenseManager.trialExpired ? "Trial Expired" : (licenseManager.isInTrial ? "\(licenseManager.trialDaysRemaining) Day\(licenseManager.trialDaysRemaining == 1 ? "" : "s") Remaining" : "Activate Layoutish"))
                .font(.title2)
                .fontWeight(.bold)

            Text(licenseManager.trialExpired ? "Your free trial has ended. Enter a license key to continue using Layoutish." : (licenseManager.isInTrial ? "Enter your license key to unlock Layoutish permanently" : "Enter your license key to unlock all features"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("License Key")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $licenseKey)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(showError ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .onChange(of: licenseKey) { _ in
                    showError = false
                }

            Text("You received this key in your purchase confirmation email")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error Section

    private var errorSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.red)

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
        )
    }

    // MARK: - Activate Button

    private var activateButton: some View {
        Button(action: {
            Task {
                showError = false
                let success = await licenseManager.activateLicense(key: licenseKey)
                if !success {
                    if case .invalid(let reason) = licenseManager.status {
                        errorMessage = reason
                    } else {
                        errorMessage = "Failed to activate license"
                    }
                    showError = true
                }
            }
        }) {
            HStack {
                if licenseManager.isValidating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(licenseManager.isValidating ? "Validating..." : "Activate License")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.brandPurple)
        .disabled(licenseKey.isEmpty || licenseManager.isValidating)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 16) {
                Button("Buy License") {
                    if let url = URL(string: checkoutURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)

                Text("·")
                    .foregroundColor(.secondary)

                Button("Restore Purchase") {
                    if let url = URL(string: "mailto:layoutish@appish.app?subject=License%20Recovery") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        }
    }
}

// MARK: - License Status View (for Settings)

struct LicenseStatusView: View {
    @ObservedObject private var licenseManager = LicenseManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("License Active")
                        .font(.system(size: 12, weight: .semibold))

                    if let email = licenseManager.customerEmail {
                        Text(email)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // License Details
            VStack(alignment: .leading, spacing: 4) {
                if case .valid(let expiresAt) = licenseManager.status {
                    if let expiry = expiresAt {
                        LicenseDetailRow(
                            label: "Expires",
                            value: expiry.formatted(date: .abbreviated, time: .omitted)
                        )
                    } else {
                        LicenseDetailRow(label: "Expires", value: "Never (Lifetime)")
                    }
                }

                if let key = licenseManager.storedLicenseKey {
                    LicenseDetailRow(label: "Key", value: maskLicenseKey(key))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.1))
        )
    }

    private func maskLicenseKey(_ key: String) -> String {
        if key.count > 8 {
            let prefix = String(key.prefix(4))
            let suffix = String(key.suffix(4))
            return "\(prefix)••••\(suffix)"
        }
        return "••••••••"
    }
}

// MARK: - Trial Status View (for Settings)

struct TrialStatusView: View {
    @ObservedObject private var licenseManager = LicenseManager.shared
    @State private var showLicenseSheet = false
    @State private var licenseKeyInput = ""
    @State private var licenseError: String?

    private let checkoutURL = "https://appish.lemonsqueezy.com/checkout/buy/56819b38-7f1b-4d1b-ba3c-8f74c550f2a5"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.brandPurple)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Trial Active")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(licenseManager.trialDaysRemaining) day\(licenseManager.trialDaysRemaining == 1 ? "" : "s") remaining")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.brandPurple.opacity(0.1))
            )

            // License key input (optional during trial)
            TextField("License key", text: $licenseKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))

            if let error = licenseError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }

            HStack {
                Button("Activate") {
                    Task {
                        licenseError = nil
                        let success = await licenseManager.activateLicense(key: licenseKeyInput)
                        if !success {
                            if case .invalid(let reason) = licenseManager.status {
                                licenseError = reason
                            } else {
                                licenseError = "Activation failed"
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPurple)
                .controlSize(.small)
                .disabled(licenseKeyInput.isEmpty || licenseManager.isValidating)

                if licenseManager.isValidating {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Spacer()

                Button("Buy License") {
                    if let url = URL(string: checkoutURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
                .foregroundStyle(Color.brandPurple)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Unlicensed View (for Settings)

struct UnlicensedView: View {
    @State private var showLicenseSheet = false

    private let checkoutURL = "https://appish.lemonsqueezy.com/checkout/buy/56819b38-7f1b-4d1b-ba3c-8f74c550f2a5"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "key")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Text("Unlicensed")
                    .font(.system(size: 12, weight: .medium))

                Spacer()
            }

            HStack(spacing: 12) {
                Button("Buy License") {
                    if let url = URL(string: checkoutURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPurple)
                .controlSize(.small)

                Button("Activate") {
                    showLicenseSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .sheet(isPresented: $showLicenseSheet) {
            LicenseView {
                showLicenseSheet = false
            }
        }
    }
}

// MARK: - License Detail Row

struct LicenseDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            Text(value)
                .font(.system(size: 10, design: .monospaced))
        }
    }
}

#Preview {
    LicenseView()
}
