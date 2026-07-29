//
//  HyperViewModel.swift
//  Hyperswitch
//
//  Created by Harshit Srivastava on 25/04/24.
//

import SwiftUI
import UIKit

class HyperViewModel: ObservableObject {

    struct Environment {
        let label: String
        let playgroundUrl: String
        let sdkBackendUrl: String
    }

    static let environments: [Environment] = [
        Environment(
            label: "Sandbox",
            playgroundUrl: "https://playground.sandbox-next.peachpayments.com",
            sdkBackendUrl: "https://app.sandbox-next.peachpayments.com/api"
        ),
        Environment(
            label: "QA",
            playgroundUrl: "https://playground.qa-next.ppay.io",
            sdkBackendUrl: "https://app.qa-next.ppay.io/api"
        ),
        Environment(
            label: "UAT",
            playgroundUrl: "https://playground.uat-next.peachpayments.com",
            sdkBackendUrl: "https://app.next.peachpayments.com/api"
        ),
    ]

    private static let environmentIndexKey = "HyperswitchDemoEnvironmentIndex"
    private static let sessionIdKey = "HyperswitchDemoSessionId"

    @Published var environmentIndex: Int {
        didSet {
            UserDefaults.standard.set(environmentIndex, forKey: HyperViewModel.environmentIndexKey)
        }
    }
    @Published var sessionId: String {
        didSet {
            UserDefaults.standard.set(sessionId, forKey: HyperViewModel.sessionIdKey)
        }
    }

    @Published var hyperswitch: Hyperswitch?
    @Published var paymentSession: PaymentSession?
    @Published var status: APIStatus = .loading
    internal var netceteraApiKey: String?
    internal var paymentId: String?

    enum APIStatus {
        case loading
        case success
        case failure(String)
    }

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: HyperViewModel.environmentIndexKey) as? Int ?? 0
        self.environmentIndex = max(0, min(saved, HyperViewModel.environments.count - 1))
        self.sessionId = defaults.string(forKey: HyperViewModel.sessionIdKey) ?? ""
    }

    var currentEnvironment: Environment { HyperViewModel.environments[environmentIndex] }

    private var backendUrl: URL {
        URL(string: DemoConfig.shared.apiBaseUrl ?? currentEnvironment.playgroundUrl)!
    }

    private func intentEndpoint() -> String {
        let base = DemoConfig.shared.createIntentEndpoint ?? "/api/create-msdk-intent"
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return base
        }
        return base.contains("?") ? "\(base)&sessionId=\(encoded)" : "\(base)?sessionId=\(encoded)"
    }

    func preparePaymentSheet() {
        Task {
            do {
                let json = try await NetworkUtility.fetchData(from: intentEndpoint(), baseUrl: backendUrl)
                // The playground returns `clientSecret` (and snake_case companions);
                // the newer Hyperswitch flow expects an `sdkAuthorization` field.
                // Accept either, and treat clientSecret as sdkAuthorization for now.
                guard let sdkAuthorization = (json["sdkAuthorization"] as? String)
                        ?? (json["clientSecret"] as? String),
                      let publishableKey = json["publishableKey"] as? String
                else {
                    throw NSError(domain: "API Error", code: 500, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
                }
                let profileId = (json["profileId"] as? String) ?? (json["profile_id"] as? String)
                self.paymentId = (json["paymentId"] as? String) ?? (json["payment_id"] as? String)
                // PaymentMethodManagementWidget reads PaymentSession.ephemeralKey from
                // the props it builds — without this, PMMangementNavigatorRouter on
                // the JS side bails immediately (PMM screen opens blank then closes).
                let ephemeralKey = (json["ephemeralKey"] as? String) ?? (json["ephemeral_key"] as? String)

                DispatchQueue.main.async {
                    self.status = .success
                    let hyperswitchConfiguration = HyperswitchConfiguration(
                        publishableKey: publishableKey,
                        profileId: profileId,
                        customEndpoints: .commonEndpoint(DemoConfig.shared.sdkBackendUrl ?? self.currentEnvironment.sdkBackendUrl)
                    )
                    let paymentSessionConfiguration = PaymentSessionConfiguration(sdkAuthorization: sdkAuthorization)

                    self.hyperswitch = Hyperswitch(configuration: hyperswitchConfiguration)
                    self.paymentSession = self.hyperswitch?.initPaymentSession(configuration: paymentSessionConfiguration)
                    PaymentSession.ephemeralKey = ephemeralKey
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .failure(error.localizedDescription)
                }
            }
        }
    }

    func updatePaymentIntent() {
        self.paymentSession?.updateIntent(
            authorizationProvider: { completion in
                if let paymentId = self.paymentId {
                    Task {
                        do {
                            let json = try await NetworkUtility.postData(
                                to: "/update-payment",
                                body: ["paymentId": paymentId],
                                baseUrl: self.backendUrl
                            )
                            guard let sdkAuthorization = (json["sdkAuthorization"] as? String)
                                    ?? (json["clientSecret"] as? String)
                            else {
                                throw NSError(
                                    domain: "API Error",
                                    code: 500,
                                    userInfo: [NSLocalizedDescriptionKey: "Missing required fields"]
                                )
                            }
                            completion(sdkAuthorization)
                        } catch {
                            completion("")  //needs to be handled
                        }
                    }
                }
            },
            completion: { result in
                switch result {
                case .success:
                    print("updateIntent: success")
                case .cancelled:
                    print("updateIntent: cancelled")
                case .failure(let error):
                    print("updateIntent: failed — \(error.localizedDescription)")
                }
            }
        )
    }

    func fetchNetceteraSDKApiKey() {
        Task {
            do {
                let apiKey = try await NetworkUtility.fetchData(from: "/netcetera-sdk-api-key", baseUrl: backendUrl)
                guard let netceteraApiKey = apiKey["netceteraApiKey"] as? String else {
                    DispatchQueue.main.async {
                        self.netceteraApiKey = nil
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.netceteraApiKey = netceteraApiKey
                }
            } catch {
                DispatchQueue.main.async {
                    self.netceteraApiKey = nil
                }
            }
        }
    }
}

/// Demo-only runtime config injected via Appetize launch params.
///
/// On iOS, Appetize `launchArgs` arrive in `ProcessInfo.processInfo.arguments`.
/// Pass a single JSON string as one launch arg, e.g.:
/// {"apiBaseUrl":"https://playground.sandbox-next.peachpayments.com",
///  "createIntentEndpoint":"/api/create-msdk-intent",
///  "primaryColor":"#de481e","backgroundColor":"#ffffff","textColor":"#1a1a1a",
///  "errorColor":"#e5484d","cornerRadius":8,"borderWidth":1}
/// All fields are optional; anything omitted falls back to the demo defaults.
struct DemoConfig: Decodable {
    var apiBaseUrl: String?
    var createIntentEndpoint: String?
    var sdkBackendUrl: String?
    var primaryColor: String?
    var backgroundColor: String?
    var textColor: String?
    var errorColor: String?
    var cornerRadius: Double?
    var borderWidth: Double?

    static let shared: DemoConfig = DemoConfig.parseLaunchParams()

    private static func parseLaunchParams() -> DemoConfig {
        var cfg = DemoConfig()

        // (a) A JSON blob passed via Appetize `launchArgs`. Appetize splits launchArgs
        // on whitespace, so join the args back and extract the {...} span.
        let joined = ProcessInfo.processInfo.arguments.joined(separator: " ")
        if let start = joined.firstIndex(of: "{"), let end = joined.lastIndex(of: "}"), start < end {
            let jsonStr = String(joined[start...end])
            if let data = jsonStr.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(DemoConfig.self, from: data) {
                cfg = parsed
            }
        }

        // (b) Individual `-key value` launch args (the canonical Appetize form) are
        // exposed via UserDefaults (NSArgumentDomain). These override / fill in.
        let d = UserDefaults.standard
        cfg.apiBaseUrl = d.string(forKey: "apiBaseUrl") ?? cfg.apiBaseUrl
        cfg.createIntentEndpoint = d.string(forKey: "createIntentEndpoint") ?? cfg.createIntentEndpoint
        cfg.sdkBackendUrl = d.string(forKey: "sdkBackendUrl") ?? cfg.sdkBackendUrl
        cfg.primaryColor = d.string(forKey: "primaryColor") ?? cfg.primaryColor
        cfg.backgroundColor = d.string(forKey: "backgroundColor") ?? cfg.backgroundColor
        cfg.textColor = d.string(forKey: "textColor") ?? cfg.textColor
        cfg.errorColor = d.string(forKey: "errorColor") ?? cfg.errorColor
        if d.object(forKey: "cornerRadius") != nil { cfg.cornerRadius = d.double(forKey: "cornerRadius") }
        if d.object(forKey: "borderWidth") != nil { cfg.borderWidth = d.double(forKey: "borderWidth") }

        return cfg
    }

    var primaryUIColor: UIColor? { primaryColor.flatMap(UIColor.init(demoHex:)) }
    var backgroundUIColor: UIColor? { backgroundColor.flatMap(UIColor.init(demoHex:)) }
    var textUIColor: UIColor? { textColor.flatMap(UIColor.init(demoHex:)) }
    var errorUIColor: UIColor? { errorColor.flatMap(UIColor.init(demoHex:)) }
}

extension UIColor {
    /// Parse "#RRGGBB" / "#RRGGBBAA" (with or without leading '#').
    convenience init?(demoHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((v >> 24) & 0xff) / 255; g = CGFloat((v >> 16) & 0xff) / 255
            b = CGFloat((v >> 8) & 0xff) / 255; a = CGFloat(v & 0xff) / 255
        } else {
            r = CGFloat((v >> 16) & 0xff) / 255; g = CGFloat((v >> 8) & 0xff) / 255
            b = CGFloat(v & 0xff) / 255; a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
