//
//  HyperModule.swift
//  Hyperswitch
//
//  Created by Harshit Srivastava on 07/03/24.
//

import Foundation
import React

@objc(HyperModule)
internal class HyperModule: RCTEventEmitter {

    private let applePayPaymentHandler = ApplePayHandler()
    private let expressCheckoutHandler = ExpressCheckoutLauncher()
    private var presentCallback: RCTResponseSenderBlock? = nil
    internal static var shared: HyperModule?

    override init() {
        super.init()
        HyperModule.shared = self
    }

    @objc
    internal override static func requiresMainQueueSetup() -> Bool {
        return true
    }

    @objc
    internal override func supportedEvents() -> [String] {
        return ["confirm", "confirmEC", "triggerWidgetAction", "updateIntentInit", "updateIntentComplete"]
    }

    @objc
    internal func confirm(data: [String: Any]) {
        self.sendEvent(withName: "confirm", body: data)
    }
    // MARK: WIP
    //    @objc func confirmEC(data: [String: Any]) {
    //        self.sendEvent(withName: "confirmEC", body: data)
    //    }

    @objc
    private func sendMessageToNative(_ rnMessage: String) {}

    @objc
    private func launchWidgetPaymentSheet(_ request: NSMutableDictionary, _ callback: @escaping RCTResponseSenderBlock) {
        expressCheckoutHandler.launchPaymentSheet(paymentResult: request, callBack: callback)
    }

    @objc
    private func onAddPaymentMethod(_ rnMessage: String) {
        PaymentMethodManagementWidget.onAddPaymentMethod?()
    }

    @objc
    private func launchApplePay(_ rnMessage: String, _ rnCallback: @escaping RCTResponseSenderBlock) {
        applePayPaymentHandler.startPayment(rnMessage: rnMessage, rnCallback: rnCallback, presentCallback: self.presentCallback)
    }

    @objc
    private func startApplePay(_ rnMessage: String, _ rnCallback: @escaping RCTResponseSenderBlock) {
        rnCallback([])
    }

    @objc
    private func presentApplePay(_ rnMessage: String, _ rnCallback: @escaping RCTResponseSenderBlock) {
        self.presentCallback = rnCallback
    }

    @objc
    private func exitPaymentsheet(_ reactTag: NSNumber, _ rnMessage: String, _ reset: Bool) {
        // Delegate to exitSheet so the dismissal uses the cached
        // RNViewManager.sharedInstance.rootView reference rather than a
        // viewRegistry[reactTag] lookup that can return nil after a 3DS
        // roundtrip — that lookup was leaving the full-screen sheet
        // container undismissed on successful saved-card payments.
        // The host's completion closure still fires via the
        // RNResponseHandler conformance on PaymentSheet.
        exitSheet(rnMessage)
    }

    @objc
    private func exitWidgetPaymentsheet(_ reactTag: NSNumber, _ rnMessage: String, _ reset: Bool) {
        let result = paymentResult(from: rnMessage)
        withWidget(reactTag) { w in
            w.handleConfirmPaymentResponse(result)
        }
    }

    /// Result of a standalone wallet button payment (ApplePayButton /
    /// ExpressCheckoutButton). `widgetType` is what Android routes on; here the
    /// reactTag identifies the embedded view instance directly.
    @objc
    private func exitWidget(_ reactTag: NSNumber, _ rnMessage: String, _ widgetType: String) {
        let result = paymentResult(from: rnMessage)
        withWalletButton(reactTag) { button in
            button.handleWalletPaymentResult(result)
        }
    }

    /// The JS layer reports the height its content needs so an express row with
    /// several wallets isn't clipped to a single button's height.
    @objc
    private func updateWidgetHeight(_ widgetType: String, _ height: NSNumber) {
        // No reactTag in this call, so resize every mounted wallet button of this
        // type — a host embeds at most one of each.
        RCTGetUIManagerQueue().async {
            self.bridge.uiManager.addUIBlock { _, viewRegistry in
                guard let views = viewRegistry?.values else { return }
                let matches = views.compactMap { view -> WalletButtonBase? in
                    var current: UIView? = view
                    while let v = current {
                        if let button = v as? WalletButtonBase { return button }
                        current = v.superview
                    }
                    return nil
                }
                let unique = matches.reduce(into: [WalletButtonBase]()) { acc, button in
                    if !acc.contains(where: { $0 === button }) { acc.append(button) }
                }
                DispatchQueue.main.async {
                    unique.forEach { $0.updateHeight(CGFloat(height.doubleValue)) }
                }
            }
        }
    }

    private func paymentResult(from rnMessage: String) -> PaymentResult {
        guard let data = rnMessage.data(using: .utf8) else {
            return .failed(
                error: NSError(
                    domain: "UNKNOWN_ERROR",
                    code: 0,
                    userInfo: ["message": "An error has occurred."]
                )
            )
        }

        do {
            guard let jsonDictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else {
                return .failed(
                    error: NSError(
                        domain: "UNKNOWN_ERROR",
                        code: 0,
                        userInfo: ["message": "An error has occurred."]
                    )
                )
            }

            let status = jsonDictionary["status"]

            if status == "failed" || status == "requires_payment_method" {
                let error = NSError(
                    domain: (jsonDictionary["code"] ?? "") != "" ? jsonDictionary["code"]! : "UNKNOWN_ERROR",
                    code: 0,
                    userInfo: ["message": jsonDictionary["message"] ?? "An error has occurred."]
                )
                // The RN layer attaches an up-to-date payment intent (stringified JSON) on
                // genuine payment failures; forward it to the host when present.
                let paymentIntent = jsonDictionary["paymentIntent"].flatMap { $0.isEmpty ? nil : $0 }
                return .failed(error: error, paymentIntent: paymentIntent)
            } else if status == "cancelled" {
                return .canceled(data: "cancelled")
            } else {
                return .completed(data: status ?? "failed")
            }
        } catch {
            return .failed(
                error: NSError(
                    domain: "UNKNOWN_ERROR",
                    code: 0,
                    userInfo: ["message": "An error has occurred."]
                )
            )
        }
    }

    @objc
    private func exitPaymentMethodManagement(_ reactTag: NSNumber, _ rnMessage: String, _ reset: Bool) {
        exitSheet(rnMessage)
    }

    @objc
    private func notifyWidgetPaymentResult(_ rootTag: NSNumber, _ rnMessage: String) {
    }

    @objc
    private func onUpdateIntentEvent(_ rootTag: NSNumber, _ type: String, _ result: String) {
        withWidget(rootTag) { widget in
            widget.handleUpdateIntentEvent(type: type, result: result)
        }
    }

    @objc func emitPaymentEvent(_ rootTag: NSNumber, _ eventType: String, _ payload: NSDictionary) {
        let map = (payload as? [String: Any]) ?? [:]
        resolveSubscribingTarget(rootTag) { target in
            if let widget = target as? PaymentWidget, widget.paymentEventListener != nil {
                widget.dispatchPaymentEvent(type: eventType, payload: map)
            } else if let cvc = target as? CVCWidget, cvc.paymentEventListener != nil {
                cvc.dispatchPaymentEvent(type: eventType, payload: map)
            } else if let walletButton = target as? WalletButtonBase, walletButton.paymentEventListener != nil {
                walletButton.dispatchPaymentEvent(type: eventType, payload: map)
            } else if let sheet = target as? PaymentSheet, sheet.paymentEventListener != nil {
                sheet.dispatchPaymentEvent(type: eventType, payload: map)
            }
        }
    }

    @objc
    private func exitCardForm(_ rnMessage: String) {
        var response: String?
        var error: NSError?

        if let data = rnMessage.data(using: .utf8) {
            do {
                if let jsonDictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                    let status = jsonDictionary["status"]

                    if status == "failed" || status == "requires_payment_method" {
                        var userInfo: [String: Any] = ["message": jsonDictionary["message"] ?? "An error has occurred."]
                        // The RN layer attaches an up-to-date payment intent (stringified JSON) on
                        // genuine payment failures. Carry it on the error's userInfo so the
                        // RNResponseHandler can surface it as PaymentResult.failed(paymentIntent:).
                        if let paymentIntent = jsonDictionary["paymentIntent"], !paymentIntent.isEmpty {
                            userInfo["payment_intent"] = paymentIntent
                        }
                        error = NSError(
                            domain: (jsonDictionary["code"] ?? "") != "" ? jsonDictionary["code"]! : "UNKNOWN_ERROR",
                            code: 0,
                            userInfo: userInfo
                        )
                    } else {
                        response = status
                    }
                    RNViewManager.sharedInstance.responseHandler?.didReceiveResponse(response: response, error: error)
                } else {
                    RNViewManager.sharedInstance.responseHandler?.didReceiveResponse(
                        response: "failed",
                        error: NSError(domain: "UNKNOWN_ERROR", code: 0, userInfo: ["message": "An error has occurred."])
                    )
                }
            } catch {
                RNViewManager.sharedInstance.responseHandler?.didReceiveResponse(
                    response: "failed",
                    error: NSError(domain: "UNKNOWN_ERROR", code: 0, userInfo: ["message": "An error has occurred."])
                )
            }
        } else {
            RNViewManager.sharedInstance.responseHandler?.didReceiveResponse(
                response: "failed",
                error: NSError(domain: "UNKNOWN_ERROR", code: 0, userInfo: ["message": "An error has occurred."])
            )
        }
    }

    @objc
    private func exitSheet(_ rnMessage: String) {
        var response: String?
        var error: NSError?

        if let data = rnMessage.data(using: .utf8) {
            do {
                if let jsonDictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                    let status = jsonDictionary["status"]

                    if status == "failed" || status == "requires_payment_method" {
                        var userInfo: [String: Any] = ["message": jsonDictionary["message"] ?? "An error has occurred."]
                        // The RN layer attaches an up-to-date payment intent (stringified JSON) on
                        // genuine payment failures. Carry it on the error's userInfo so the
                        // RNResponseHandler can surface it as PaymentResult.failed(paymentIntent:).
                        if let paymentIntent = jsonDictionary["paymentIntent"], !paymentIntent.isEmpty {
                            userInfo["payment_intent"] = paymentIntent
                        }
                        error = NSError(
                            domain: (jsonDictionary["code"] ?? "") != "" ? jsonDictionary["code"]! : "UNKNOWN_ERROR",
                            code: 0,
                            userInfo: userInfo
                        )
                    } else {
                        response = status
                    }
                    RNViewManager.sharedInstance.responseHandler?.didReceiveResponse(response: response, error: error)
                } else {
                    RNViewManager.sharedInstance.responseHandler?.didReceiveResponse(
                        response: "failed",
                        error: NSError(domain: "UNKNOWN_ERROR", code: 0, userInfo: ["message": "An error has occurred."])
                    )
                }
            } catch {
                RNViewManager.sharedInstance.responseHandler?.didReceiveResponse(
                    response: "failed",
                    error: NSError(domain: "UNKNOWN_ERROR", code: 0, userInfo: ["message": "An error has occurred."])
                )
            }
        } else {
            RNViewManager.sharedInstance.responseHandler?.didReceiveResponse(
                response: "failed",
                error: NSError(domain: "UNKNOWN_ERROR", code: 0, userInfo: ["message": "An error has occurred."])
            )
        }
        DispatchQueue.main.async {
            if let view = RNViewManager.sharedInstance.rootView {
                let reactNativeVC: UIViewController? = view.reactViewController()
                reactNativeVC?.dismiss(animated: false, completion: nil)
            }
        }
    }

    @objc
    private func onPaymentConfirmButtonClick(_ rootTag: NSNumber, _ payload: String, _ callback: @escaping RCTResponseSenderBlock) {
        resolveSubscribingTarget(rootTag) { target in
            if let widget = target as? PaymentWidget {
                widget.handleShouldProceedWithPayment(payload: payload) { shouldProceed in
                    callback([shouldProceed])
                }
            } else if let sheet = target as? PaymentSheet {
                sheet.handleShouldProceedWithPayment(payload: payload) { shouldProceed in
                    callback([shouldProceed])
                }
            } else {
                callback([true])
            }
        }
    }

    private func withWalletButton(_ rootTag: NSNumber, _ block: @escaping (WalletButtonBase) -> Void) {
        RCTGetUIManagerQueue().async {
            self.bridge.uiManager.addUIBlock { _, viewRegistry in
                guard let view = viewRegistry?[rootTag] else { return }
                var current: UIView? = view
                while let v = current {
                    if let button = v as? WalletButtonBase {
                        DispatchQueue.main.async { block(button) }
                        return
                    }
                    current = v.superview
                }
            }
        }
    }

    private func withWidget(_ rootTag: NSNumber, _ block: @escaping (PaymentWidget) -> Void) {
        RCTGetUIManagerQueue().async {
            self.bridge.uiManager.addUIBlock { _, viewRegistry in
                guard let view = viewRegistry?[rootTag] else { return }
                var current: UIView? = view
                while let v = current {
                    if let widget = v as? PaymentWidget {
                        block(widget)
                        return
                    }
                    current = v.superview
                }
            }
        }
    }

    private func resolveSubscribingTarget(_ rootTag: NSNumber, _ block: @escaping (AnyObject?) -> Void) {
        RCTGetUIManagerQueue().async {
            self.bridge.uiManager.addUIBlock { _, viewRegistry in
                guard let view = viewRegistry?[rootTag] else {
                    DispatchQueue.main.async { block(nil) }
                    return
                }
                var current: UIView? = view
                while let v = current {
                    if v is PaymentWidget || v is CVCWidget || v is WalletButtonBase {
                        DispatchQueue.main.async { block(v) }
                        return
                    }
                    current = v.superview
                }
                let sheet = (view.reactViewController() as? HyperUIViewController)?.paymentSheet
                DispatchQueue.main.async { block(sheet) }
            }
        }
    }

    private func withPaymentSheet(_ rootTag: NSNumber, _ block: @escaping (UIViewController?, PaymentSheet?) -> Void) {
        RCTGetUIManagerQueue().async {
            self.bridge.uiManager.addUIBlock { _, viewRegistry in
                let view = viewRegistry?[rootTag]
                let vc = view?.reactViewController() as? HyperUIViewController
                let sheet = vc?.paymentSheet
                DispatchQueue.main.async { block(vc, sheet) }
            }
        }
    }
}
