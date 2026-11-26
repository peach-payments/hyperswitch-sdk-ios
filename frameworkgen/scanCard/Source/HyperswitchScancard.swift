import Foundation
import React
import HyperswitchScanCard

// @usableFromInline gives this class public linkage without making it public API. Under SPM
// its Objective-C bridge shim is a separate target (SPM has no mixed-language targets), and in
// Release builds an internal class is emitted hidden, so the shim fails to link with
// "Undefined symbols: _OBJC_CLASS_$_<name>". Debug builds and CocoaPods never showed it.
@objc(HyperswitchScancard)
@usableFromInline
class HyperswitchScancard: NSObject {

    @objc
    func launchScanCard(_ rnMessage: String, _ rnCallback: @escaping RCTResponseSenderBlock) {

        DispatchQueue.main.async {
            var message: [String: Any] = [:]
            var callback: [String: Any] = [:]
            let cardScanSheet = CardScanSheet()
            cardScanSheet.present(from: RCTPresentedViewController()!) { result in

                switch result {
                case .completed(var card as ScannedCard?):
                    message["pan"] = card?.pan
                    message["expiryMonth"] = card?.expiryMonth
                    message["expiryYear"] = card?.expiryYear
                    callback["status"] = "Succeeded"
                    callback["data"] = message
                case .canceled:
                    callback["status"] = "Cancelled"
                case .failed(let error):
                    callback["status"] = "Failed"

                }
                rnCallback([callback])
            }
        }
    }
}
