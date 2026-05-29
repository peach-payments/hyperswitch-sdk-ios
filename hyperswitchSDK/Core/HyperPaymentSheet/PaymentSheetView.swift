//
//  PaymentSheetView.swift
//  Hyperswitch
//
//  Created by Harshit Srivastava on 15/12/23.
//

import Foundation
import React
import WebKit

/// Extension on the PaymentSheet class to handle the creation of the React Native root view for the payment sheet.
internal extension PaymentSheet {

    /// Method to get the root view for the payment sheet based on the configured properties.
    func getRootView() -> RCTRootView {

        let hyperswitchConfiguration = try? hyperswitchConfiguration?.toDictionary()
        let paymentSessionConfiguration = try? paymentSessionConfiguration.toDictionary()

        /// Get the configuration dictionary from the configuration object.
        var configuration = try? self.configuration?.toDictionary()
        configuration?["subscribedEvents"] = subscribedEvents

        /// Create a dictionary of hyperParams with app ID, sdkVersion, country, user agent, default view, and launch time.
        let sdkParams = SDKParams.getSDKParams()

        /// Create a dictionary of props to be sent to React Native with configuration, type, sdkAuthorization, publishable key, hyperParams, custom backend URL, themes, and custom parameters.
        let props: [String: Any] = [
            "type": "payment",
            "hyperswitchConfig": hyperswitchConfiguration as Any,
            "paymentSessionConfig": paymentSessionConfiguration as Any,
            "sdkParams": sdkParams,
            "configuration": configuration as Any
        ]
        /// Get the root view from the RNViewManager with the "hyperSwitch" module and the props dictionary.
        let rootView = RNViewManager.sharedInstance.viewForModule("hyperSwitch", initialProperties: ["props": props])

        rootView.backgroundColor = UIColor.clear
        return rootView
    }

    /// Method to get the root view for the payment sheet with custom parameters.
    /// - Note: Used by Flutter and React Native Wrappers to send separate props.
    func getRootViewWithParams(props: [String: Any]) -> RCTRootView {

        let hyperswitchConfiguration = try? hyperswitchConfiguration?.toDictionary()
        let paymentSessionConfiguration = try? paymentSessionConfiguration.toDictionary()

        let sdkParams = SDKParams.getSDKParams()
        var propsDict = props
        propsDict["subscribedEvents"] = subscribedEvents

        let props: [String: Any] = [
            "type": "payment",
            "hyperswitchConfig": hyperswitchConfiguration as Any,
            "paymentSessionConfig": paymentSessionConfiguration as Any,
            "sdkParams": sdkParams,
            "configuration": propsDict,
            "from": "rn",
        ]

        let rootView = RNViewManager.sharedInstance.viewForModule("hyperSwitch", initialProperties: ["props": props])

        rootView.backgroundColor = UIColor.clear
        return rootView
    }
}

/// PaymentSheet receives the JS-side completion ("success"/"failed"/"cancelled")
/// via HyperModule.exitSheet -> RNViewManager.responseHandler. Without this
/// conformance the user's `completion: { result in ... }` closure would never
/// fire after the sheet's payment flow finishes, leaving the host app stuck
/// because HyperUIViewController swallows all touches by design.
extension PaymentSheet: RNResponseHandler {
    func didReceiveResponse(response: String?, error: Error?) {
        guard let completion = self.completion else { return }
        // Clear before invoking so a callback that immediately re-presents the
        // sheet doesn't accidentally fire twice.
        self.completion = nil

        if let error = error {
            completion(.failed(error: error))
        } else if response == "cancelled" {
            completion(.canceled(data: "cancelled"))
        } else {
            completion(.completed(data: response ?? "failed"))
        }
    }
}
