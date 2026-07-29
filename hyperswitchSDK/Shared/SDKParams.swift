//
//  HyperParams.swift
//  hyperswitch
//
//  Created by Shivam Nan on 15/01/25.
//

import UIKit

class SDKParams {
    static let appId: String? = Bundle.main.bundleIdentifier
    static let sdkVersion: String = SDKVersion.current
    static let country: String? = NSLocale.current.regionCode
    static let deviceModel: String = UIDevice.current.model
    static let osVersion: String = UIDevice.current.systemVersion

    // Synthesised Safari-style UA. Avoids touching WKWebView, which would
    // require main-thread init and isn't safe from the JS/RN dispatch sites
    // where getSDKParams() is read. Some Hyperswitch connectors require
    // browser_info.user_agent on /payments/confirm — omitting it triggers
    // an IR_06 "missing field user_agent" deserialise error.
    static let userAgent: String = {
        let osString = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let appName = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "PeachDemoStore"
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        return "Mozilla/5.0 (\(UIDevice.current.model); CPU OS \(osString) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 \(appName)/\(appVersion)"
    }()

    static func getSDKParams() -> [String: Any?] {
        let params: [String: Any?] = [
            "appId": appId,
            "sdkVersion": sdkVersion,
            "country": country,
            "user-agent": userAgent,
            "device_model": deviceModel,
            "os_version": osVersion,
            "os_type": "ios",
            "launchTime": Int(Date().timeIntervalSince1970 * 1000),
        ]
        return params
    }
}
