//
//  HyperViewModel.swift
//  Hyperswitch
//
//  Created by Harshit Srivastava on 25/04/24.
//

import SwiftUI

class HyperViewModel: ObservableObject {

    struct Environment {
        let label: String
        let playgroundUrl: String
        let sdkBackendUrl: String
    }

    static let environments: [Environment] = [
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
        URL(string: currentEnvironment.playgroundUrl)!
    }

    private func intentEndpoint() -> String {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return "/api/create-msdk-intent"
        }
        return "/api/create-msdk-intent?sessionId=\(encoded)"
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
                        customEndpoints: .commonEndpoint(self.currentEnvironment.sdkBackendUrl)
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
