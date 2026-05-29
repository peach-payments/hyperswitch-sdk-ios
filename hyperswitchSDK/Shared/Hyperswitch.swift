//
//  Hyperswitch.swift
//  HyperswitchCore
//
//  Created by Harshit Srivastava on 17/05/26.
//

public final class Hyperswitch {

    internal let hyperswitchConfiguration: HyperswitchConfiguration

    public init(configuration: HyperswitchConfiguration) {  // MARK: async on superposition impl
        self.hyperswitchConfiguration = configuration
        // Mirror the legacy PaymentSession behavior: push config to
        // APIClient.shared so internal SDK components that read directly
        // from it (e.g. PaymentMethodManagementWidget, ExpressCheckoutLauncher)
        // can locate the publishable key, profile, and custom endpoints.
        // Without this, those flows render with empty creds and look broken
        // ("green screen" / "Invalid publishable key") even though the
        // PaymentSheet flow works because it ships hyperswitchConfig via props.
        APIClient.shared.publishableKey = configuration.publishableKey
        APIClient.shared.profileId = configuration.profileId
        if let endpoints = configuration.customEndpoints {
            switch endpoints {
            case .commonEndpoint(let url):
                APIClient.shared.customBackendUrl = url
            case .overrideEndpoints(let override):
                APIClient.shared.customBackendUrl = override.customBackendEndpoint
                APIClient.shared.customLogUrl = override.customLoggingEndpoint
            }
        }
        // Task {} Superposition
    }

    public func initPaymentSession(configuration: PaymentSessionConfiguration) -> PaymentSession {
        PaymentSession(paymentSessionConfiguration: configuration, hyperswitchConfiguration: hyperswitchConfiguration)
    }
}
