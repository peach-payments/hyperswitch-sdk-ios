//
//  WalletButtonView.swift
//  Hyperswitch
//
//  Standalone wallet buttons the host embeds directly in its own checkout UI,
//  with no payment sheet. The button itself is the real branded control
//  (PKPaymentButton for Apple Pay) rendered by the JS layer, so a customer tap
//  runs the same launch -> confirm flow the payment sheet uses.
//
//  Two shapes are exposed:
//    - ApplePayButton         a single Apple Pay button
//    - ExpressCheckoutButton  a row of every wallet enabled for the merchant
//

import Foundation

/// Shared plumbing for the standalone wallet button widgets. Not public: hosts
/// use `ApplePayButton` or `ExpressCheckoutButton`.
public class WalletButtonBase: UIControl {

    private let paymentSession: PaymentSession
    private let configuration: PaymentSheet.Configuration?
    private var configurationDict: [String: Any]?
    private let widgetType: String
    private var widgetReactTag: NSNumber?
    private var rootView: RCTRootView?
    private var completion: ((PaymentResult) -> Void)?
    private var subscribedEventNames: [String]?
    private var heightConstraint: NSLayoutConstraint?
    private var contentHeight: CGFloat = WalletButtonBase.defaultHeight

    internal var paymentEventListener: PaymentEventListener?

    internal static let defaultHeight: CGFloat = 52.0

    fileprivate init(
        widgetType: String,
        paymentSession: PaymentSession,
        configuration: PaymentSheet.Configuration?,
        configurationDict: [String: Any]?,
        completion: @escaping ((PaymentResult) -> Void),
        subscribe: ((PaymentEventSubscriptionBuilder) -> Void)?
    ) {
        self.widgetType = widgetType
        self.paymentSession = paymentSession
        self.configuration = configuration
        self.configurationDict = configurationDict
        self.completion = completion
        if let subscribe {
            let builder = PaymentEventSubscriptionBuilder()
            subscribe(builder)
            let (subscription, listener) = builder.build()
            self.paymentEventListener = listener
            self.subscribedEventNames = subscription.subscribedEventStrings()
        }
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    private func commonInit() {
        let hyperswitchConfiguration = try? paymentSession.hyperswitchConfiguration?.toDictionary()
        let paymentSessionConfiguration = try? paymentSession.paymentSessionConfiguration.toDictionary()

        let sdkParams = SDKParams.getSDKParams()

        var nativeConfig = try? configuration?.toDictionary()
        nativeConfig?["subscribedEvents"] = subscribedEventNames
        configurationDict?["subscribedEvents"] = subscribedEventNames

        // Full props (rather than just `type`) so the JS layer can authenticate
        // itself. Passing only the type is what leaves the legacy ExpressCheckout
        // view dependent on APIClient.shared being pre-seeded.
        let props: [String: Any] = [
            "type": widgetType,
            "hyperswitchConfig": hyperswitchConfiguration as Any,
            "paymentSessionConfig": paymentSessionConfiguration as Any,
            "sdkParams": sdkParams,
            "configuration": configurationDict ?? nativeConfig as Any,
            "from": (configurationDict != nil) ? "rn" : "nativeWidget",
        ]

        self.backgroundColor = .clear

        self.rootView = RNViewManager.sharedInstance.widgetViewForModule(
            "hyperSwitch",
            initialProperties: ["props": props]
        )

        guard let rootView = self.rootView else { return }

        self.widgetReactTag = rootView.reactTag
        rootView.backgroundColor = .clear
        addSubview(rootView)

        rootView.translatesAutoresizingMaskIntoConstraints = false
        let height = rootView.heightAnchor.constraint(equalToConstant: contentHeight)
        self.heightConstraint = height
        NSLayoutConstraint.activate([
            rootView.topAnchor.constraint(equalTo: topAnchor),
            rootView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootView.trailingAnchor.constraint(equalTo: trailingAnchor),
            height,
        ])
    }

    /// Starts the payment without waiting for a tap. The customer still completes
    /// it in the wallet's own sheet.
    public func confirm() {
        let payload: [String: Any] = [
            "rootTag": self.widgetReactTag ?? -1,
            "actionType": "CONFIRM_WALLET_PAYMENT",
        ]
        self.rootView?.bridge.enqueueJSCall(
            "RCTDeviceEventEmitter",
            method: "emit",
            args: ["triggerWidgetAction", payload],
            completion: nil
        )
    }

    /// Called from HyperModule when the JS layer reports the height its content
    /// actually needs — an express row with several wallets is taller than one
    /// button.
    internal func updateHeight(_ height: CGFloat) {
        guard height > 0, height != contentHeight else { return }
        contentHeight = height
        heightConstraint?.constant = height
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    internal func handleWalletPaymentResult(_ result: PaymentResult) {
        completion?(result)
    }

    internal func dispatchPaymentEvent(type: String, payload: [String: Any]) {
        guard let listener = paymentEventListener else { return }
        let event = PaymentEvent(type: type, payload: payload)
        if Thread.isMainThread {
            listener.onPaymentEvent(event)
        } else {
            DispatchQueue.main.async { listener.onPaymentEvent(event) }
        }
    }
}

/// A standalone Apple Pay button. Renders nothing when Apple Pay is unavailable
/// for the merchant, the connector, or the device.
public final class ApplePayButton: WalletButtonBase {

    public init(
        paymentSession: PaymentSession,
        configuration: PaymentSheet.Configuration? = nil,
        completion: @escaping ((PaymentResult) -> Void),
        subscribe: ((PaymentEventSubscriptionBuilder) -> Void)? = nil
    ) {
        super.init(
            widgetType: "apple_pay",
            paymentSession: paymentSession,
            configuration: configuration,
            configurationDict: nil,
            completion: completion,
            subscribe: subscribe
        )
    }

    //MARK: pass through
    public init(
        paymentSession: PaymentSession,
        configurationDict: [String: Any]?,
        completion: @escaping ((PaymentResult) -> Void),
        subscribe: ((PaymentEventSubscriptionBuilder) -> Void)? = nil
    ) {
        super.init(
            widgetType: "apple_pay",
            paymentSession: paymentSession,
            configuration: nil,
            configurationDict: configurationDict,
            completion: completion,
            subscribe: subscribe
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A row of every wallet button enabled for the merchant on this platform.
public final class ExpressCheckoutButton: WalletButtonBase {

    public init(
        paymentSession: PaymentSession,
        configuration: PaymentSheet.Configuration? = nil,
        completion: @escaping ((PaymentResult) -> Void),
        subscribe: ((PaymentEventSubscriptionBuilder) -> Void)? = nil
    ) {
        super.init(
            widgetType: "expressCheckout",
            paymentSession: paymentSession,
            configuration: configuration,
            configurationDict: nil,
            completion: completion,
            subscribe: subscribe
        )
    }

    //MARK: pass through
    public init(
        paymentSession: PaymentSession,
        configurationDict: [String: Any]?,
        completion: @escaping ((PaymentResult) -> Void),
        subscribe: ((PaymentEventSubscriptionBuilder) -> Void)? = nil
    ) {
        super.init(
            widgetType: "expressCheckout",
            paymentSession: paymentSession,
            configuration: nil,
            configurationDict: configurationDict,
            completion: completion,
            subscribe: subscribe
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
