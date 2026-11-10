import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import ScriptureCore

enum AppleSignInNonce {
    static func random(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            bytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: ReaderModel
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var ads: AdsManager
    @Environment(\.dismiss) private var dismiss
    @State private var appleNonce = ""
    @State private var showingDeleteAccount = false

    var body: some View {
        NavigationStack {
            Form {
                proSection
                readingSection
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
            .alert("Delete account?", isPresented: $showingDeleteAccount) {
                Button("Cancel", role: .cancel) {}
                Button("Delete account", role: .destructive) {
                    Task { await pro.deleteAccount { model.clearLocalReaderData() } }
                }
            } message: {
                Text(
                    "This permanently deletes your sign-in, Pro entitlement, and synced data for every GCore app using this account. "
                        + "Local notes and favorites on this device are also cleared. "
                        + "Your App Store subscription is not canceled — cancel it in the App Store if you do not want to be billed again."
                )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var proSection: some View {
        Section("Pro") {
            if !pro.configured {
                Text("Add GoogleService-Info.plist to enable sign-in, purchases, and server-verified Pro.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Status")
                Spacer()
                Text(pro.isPro ? "Pro" : "Free")
                    .foregroundStyle(pro.isPro ? Color.accentColor : Color.secondary)
            }
            if let expiresAt = pro.expiresAt, pro.isPro {
                LabeledContent("Renews / expires", value: expiresAt.formatted(date: .abbreviated, time: .omitted))
            }

            if let email = pro.signedInEmail {
                LabeledContent("Account", value: email)
                Button("Sign out", role: .destructive) { pro.signOut() }
                Button("Delete account…", role: .destructive) { showingDeleteAccount = true }
                    .disabled(pro.busy)
            } else {
                Button {
                    Task { await pro.signInWithGoogle() }
                } label: {
                    Label("Continue with Google", systemImage: "person.crop.circle")
                }
                .disabled(!pro.configured || pro.busy)

                SignInWithAppleButton(.signIn) { request in
                    let nonce = AppleSignInNonce.random()
                    appleNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = AppleSignInNonce.sha256(nonce)
                } onCompletion: { result in
                    Task { await pro.completeAppleSignIn(result, rawNonce: appleNonce) }
                }
                .frame(height: 44)
                .disabled(!pro.configured || pro.busy)
            }

            if pro.signedInEmail != nil {
                Button {
                    Task { await pro.buy(monthly: true) }
                } label: {
                    HStack {
                        Text("Monthly")
                        Spacer()
                        Text(pro.monthlyPrice ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(pro.busy)

                Button {
                    Task { await pro.buy(monthly: false) }
                } label: {
                    HStack {
                        Text("Yearly")
                        Spacer()
                        Text(pro.yearlyPrice ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(pro.busy)
            }

            Button {
                Task { await pro.restorePurchases() }
            } label: {
                Label("Restore purchases", systemImage: "arrow.clockwise")
            }
            .disabled(!pro.configured || pro.busy)

            if pro.isPro {
                Button("Manage subscription") { pro.manageSubscriptions() }
            }

            if AppFeatureFlags.explanationsEnabled, pro.isPro {
                LabeledContent(
                    "Offline explanations",
                    value: pro.offlinePackVersion.map { "\(pro.offlinePackCount) saved · v\($0)" } ?? "Not downloaded"
                )
                Button {
                    Task { await pro.downloadExplanationPack() }
                } label: {
                    Label("Download offline explanations", systemImage: "arrow.down.circle")
                }
                .disabled(pro.busy)

                if pro.offlinePackVersion != nil {
                    Button("Remove offline explanations", role: .destructive) {
                        pro.clearOfflineExplanations()
                    }
                }
            }

            if let message = pro.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if pro.busy {
                ProgressView()
            }
        }
    }

    private var readingSection: some View {
        Section("Reading") {
            HStack {
                Text("Text size")
                Slider(value: $model.fontSize, in: 18...42, step: 1)
                Text("\(Int(model.fontSize))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
            Picker("Theme", selection: $model.theme) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        Section("Privacy") {
            if ads.privacyOptionsRequired {
                Button("Ad privacy options") { ads.showPrivacyOptions() }
            } else {
                Text(pro.isPro ? "Pro removes banner and interstitial ads." : "Ads are requested only after consent and are limited per session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = ads.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Translation", value: model.translationLabel)
            if let edition = model.edition {
                LabeledContent("Source updated", value: edition.sourceUpdated)
                if let url = URL(string: edition.source) {
                    Link("Source text", destination: url)
                }
            }
            Text("World English Bible is public domain. The World English Bible name is a trademark of eBible.org.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
