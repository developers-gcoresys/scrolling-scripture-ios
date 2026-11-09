import Foundation
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

@MainActor
final class AdsManager: NSObject, ObservableObject {
    @Published private(set) var consentReady = false
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var lastError: String?

    let bannerUnitID: String
    let interstitialUnitID: String

    private var interstitial: InterstitialAd?
    private var started = false

    override init() {
        bannerUnitID = Bundle.main.object(forInfoDictionaryKey: "AdMobBannerUnitID") as? String
            ?? "ca-app-pub-3940256099942544/2934735716"
        interstitialUnitID = Bundle.main.object(forInfoDictionaryKey: "AdMobInterstitialUnitID") as? String
            ?? "ca-app-pub-3940256099942544/4411468910"
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        requestConsent()
    }

    private func requestConsent() {
        guard let viewController = UIApplication.shared.topViewController else { return }
        let parameters = UMPRequestParameters()
        parameters.tagForUnderAgeOfConsent = false
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                UMPConsentForm.loadAndPresentIfRequired(from: viewController) { [weak self] formError in
                    Task { @MainActor in
                        guard let self else { return }
                        if let formError { self.lastError = formError.localizedDescription }
                        self.consentReady = UMPConsentInformation.sharedInstance.canRequestAds
                        self.privacyOptionsRequired = UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
                        if self.consentReady { self.loadInterstitial() }
                    }
                }
            }
        }
    }

    func loadInterstitial() {
        guard consentReady else { return }
        InterstitialAd.load(with: interstitialUnitID, request: Request()) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                self.interstitial = ad
                ad?.fullScreenContentDelegate = self
            }
        }
    }

    /// Presents a loaded interstitial and returns true when presentation started.
    /// Ads are never requested before UMP consent is available.
    @discardableResult
    func presentInterstitialIfAvailable() -> Bool {
        guard consentReady, let ad = interstitial, let viewController = UIApplication.shared.topViewController else {
            return false
        }
        ad.present(fromRootViewController: viewController)
        return true
    }

    func showPrivacyOptions() {
        guard let viewController = UIApplication.shared.topViewController else { return }
        UMPConsentForm.presentPrivacyOptionsForm(from: viewController) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.lastError = error.localizedDescription }
                self.privacyOptionsRequired = UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
            }
        }
    }
}

extension AdsManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        loadInterstitial()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        lastError = error.localizedDescription
        interstitial = nil
        loadInterstitial()
    }
}

struct BannerAdView: UIViewRepresentable {
    let unitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = unitID
        banner.rootViewController = UIApplication.shared.topViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
