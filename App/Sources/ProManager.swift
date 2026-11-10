import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import GoogleSignIn
import StoreKit
import UIKit
import ScriptureCore

@MainActor
final class ProManager: NSObject, ObservableObject {
    @Published private(set) var isPro = false
    @Published private(set) var status = "inactive"
    @Published private(set) var expiresAt: Date?
    @Published private(set) var willRenew = false
    @Published private(set) var monthlyPrice: String?
    @Published private(set) var yearlyPrice: String?
    @Published private(set) var signedInEmail: String?
    @Published private(set) var busy = false
    @Published private(set) var offlinePackVersion: Int?
    @Published private(set) var offlinePackCount = 0
    @Published private(set) var configured = FirebaseRuntime.isConfigured
    @Published var message: String?

    let appId: String
    private var products: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var started = false
    private let appAccountToken = AppAccountTokenStore.loadOrCreate()

    init(appId: String) {
        self.appId = appId
        super.init()
    }

    deinit {
        updatesTask?.cancel()
    }

    func start() {
        guard !started, configured else { return }
        started = true
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                self.signedInEmail = user?.email
                if user != nil {
                    await self.refreshEntitlement()
                    await self.syncCurrentEntitlements()
                } else {
                    self.apply(ProEntitlement.inactive)
                }
            }
        }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = update else { continue }
                await self.handle(transaction: transaction)
            }
        }
        Task { await loadProducts() }
        refreshOfflinePackInfo()
    }

    func loadProducts() async {
        guard configured else { return }
        do {
            let loaded = try await Product.products(for: ProProductIDs.all)
            for product in loaded {
                products[product.id] = product
                if product.id == ProProductIDs.monthly { monthlyPrice = product.displayPrice }
                if product.id == ProProductIDs.yearly { yearlyPrice = product.displayPrice }
            }
        } catch {
            message = "Subscriptions are unavailable right now."
        }
    }

    func signInWithGoogle() async {
        guard configured else {
            message = "Add GoogleService-Info.plist to enable sign-in and Pro."
            return
        }
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            message = "Google sign-in is not configured for this build."
            return
        }
        guard let presenter = UIApplication.shared.topViewController else { return }
        busy = true
        defer { busy = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                message = "Google did not return an identity token."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await Auth.auth().signIn(with: credential)
            message = "Signed in. Checking Pro…"
        } catch {
            message = "Google sign-in failed. Check the Firebase and Google configuration."
        }
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>, rawNonce: String) async {
        guard configured else { return }
        busy = true
        defer { busy = false }
        switch result {
        case .failure:
            message = "Sign in with Apple was canceled."
        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = appleCredential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                message = "Apple did not return an identity token."
                return
            }
            do {
                let credential = OAuthProvider.appleCredential(
                    withIDToken: idToken,
                    rawNonce: rawNonce,
                    fullName: appleCredential.fullName
                )
                try await Auth.auth().signIn(with: credential)
                message = "Signed in. Checking Pro…"
            } catch {
                message = "Sign in with Apple failed. Check the Sign in with Apple capability."
            }
        }
    }

    func buy(monthly: Bool) async {
        guard configured else {
            message = "Pro is not configured for this build."
            return
        }
        guard Auth.auth().currentUser != nil else {
            message = "Sign in before subscribing so your purchase can be restored."
            return
        }
        let productId = monthly ? ProProductIDs.monthly : ProProductIDs.yearly
        guard let product = products[productId] else {
            message = "This subscription is not available yet."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                _ = try await verifyWithBackend(transactionId: String(transaction.id), productId: productId)
                await transaction.finish()
                await refreshEntitlement()
                message = "Pro is active."
            case .userCancelled:
                message = "Purchase canceled."
            case .pending:
                message = "Purchase is pending approval."
            @unknown default:
                message = "Purchase could not be completed."
            }
        } catch {
            message = "Purchase could not be verified. Try Restore Purchases."
        }
    }

    func restorePurchases() async {
        guard configured else {
            message = "Pro is not configured for this build."
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await syncCurrentEntitlements()
            await refreshEntitlement()
            message = isPro ? "Pro restored." : "No active Pro subscription was found for this account."
        } catch {
            message = "Restore failed. Check your connection and try again."
        }
    }

    func refreshEntitlement() async {
        guard configured, Auth.auth().currentUser != nil else {
            apply(ProEntitlement.inactive)
            return
        }
        do {
            let result = try await functions().httpsCallable("getProEntitlement").call(["appId": appId])
            apply(result.data)
        } catch {
            // Keep the last known state; the UI still requires an active expiry.
            if !isPro { message = "Could not check Pro status." }
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        apply(ProEntitlement.inactive)
        message = "Signed out."
    }

    /// Deletes the Firebase account and this app's server-side data. The App
    /// Store subscription keeps billing until the user cancels it there, so the
    /// UI must warn about that first.
    func deleteAccount(localCleanup: @escaping () -> Void = {}) async {
        guard configured, Auth.auth().currentUser != nil else {
            message = "Sign in to delete your account."
            return
        }
        busy = true
        defer { busy = false }
        do {
            _ = try await functions().httpsCallable("deleteAccount").call(["appId": appId])
            localCleanup()
            try? Auth.auth().signOut()
            apply(ProEntitlement.inactive)
            message = "Your account and app data were deleted. Your App Store subscription is not canceled."
        } catch {
            message = "Account deletion could not be completed. Check your connection and try again."
        }
    }

    func manageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    func refreshOfflinePackInfo() {
        offlinePackVersion = OfflineExplanationStore.version()
        offlinePackCount = OfflineExplanationStore.load().count
    }

    /// Downloads the curated Pro explanation pack and keeps it in private app
    /// storage. The backend returns an empty pack until one has been published.
    func downloadExplanationPack() async {
        guard configured, Auth.auth().currentUser != nil else {
            message = "Sign in with Pro to download offline explanations."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let result = try await functions().httpsCallable("downloadProExplanationPack").call(["appId": appId])
            guard let dictionary = result.data as? [String: Any] else {
                message = "The offline explanation pack was not available."
                return
            }
            guard let packVersion = (dictionary["packVersion"] as? NSNumber)?.intValue else {
                message = "No offline explanation pack is available yet."
                return
            }
            let rawItems = dictionary["items"] as? [[String: Any]] ?? []
            let items = rawItems.compactMap { item -> OfflineExplanation? in
                guard let reference = item["reference"] as? String,
                      let explanation = item["explanation"] as? String,
                      !reference.isEmpty, !explanation.isEmpty else { return nil }
                let citations = item["citations"] as? [String] ?? []
                return OfflineExplanation(reference: reference, explanation: explanation, citations: citations)
            }
            guard !items.isEmpty else {
                message = "No offline explanation pack is available yet."
                return
            }
            try OfflineExplanationStore.save(items, appId: appId, packVersion: packVersion)
            refreshOfflinePackInfo()
            message = "Offline explanations saved (\(items.count))."
        } catch {
            message = "Offline explanations could not be downloaded. Check your connection and try again."
        }
    }

    func clearOfflineExplanations() {
        OfflineExplanationStore.clear()
        refreshOfflinePackInfo()
        message = "Offline explanations removed."
    }

    private func syncCurrentEntitlements() async {
        guard configured, Auth.auth().currentUser != nil else { return }
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProProductIDs.all.contains(transaction.productID), transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration <= Date() { continue }
            _ = try? await verifyWithBackend(transactionId: String(transaction.id), productId: transaction.productID)
        }
    }

    private func handle(transaction: Transaction) async {
        guard ProProductIDs.all.contains(transaction.productID), transaction.revocationDate == nil else { return }
        do {
            _ = try await verifyWithBackend(transactionId: String(transaction.id), productId: transaction.productID)
            await transaction.finish()
            await refreshEntitlement()
        } catch {
            message = "A subscription could not be verified yet. Try Restore Purchases."
        }
    }

    @discardableResult
    private func verifyWithBackend(transactionId: String, productId: String) async throws -> Any? {
        let result = try await functions().httpsCallable("verifyProPurchase").call([
            "appId": appId,
            "platform": "ios",
            "productId": productId,
            "transactionId": transactionId
        ])
        apply(result.data)
        return result.data
    }

    private func functions() -> Functions {
        Functions.functions(region: "us-central1")
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified(_, let error): throw error
        }
    }

    private func apply(_ data: Any?) {
        guard let dictionary = data as? [String: Any] else { return }
        let entitlement = ProEntitlement(
            appId: dictionary["appId"] as? String ?? appId,
            isPro: dictionary["isPro"] as? Bool ?? false,
            status: dictionary["status"] as? String ?? "inactive",
            productId: dictionary["productId"] as? String,
            expiresAt: (dictionary["expiresAt"] as? String).flatMap(ScriptureISO8601.date),
            willRenew: dictionary["willRenew"] as? Bool ?? false
        )
        apply(entitlement)
    }

    private func apply(_ entitlement: ProEntitlement) {
        isPro = entitlement.isActivePro()
        status = isPro ? entitlement.status : "inactive"
        expiresAt = entitlement.expiresAt
        willRenew = isPro && entitlement.willRenew
    }
}
