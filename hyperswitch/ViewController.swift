//
//  ViewController.swift
//  Hyperswitch
//
//  Created by Harshit Srivastava on 14/07/23.
//

import Combine
import SwiftUI
import UIKit

class ViewController: UIViewController {

    // MARK: - Branding
    //
    // Single source of truth for the demo's Peach Payments branding.
    // Swap `brandColor` for the exact brand hex, and drop a "PeachLogo" image
    // set into Assets.xcassets to replace the text wordmark automatically.
    // Brand color: overridable via the Appetize launch-param config; falls back to Peach #de481e.
    private let brandColor =
        DemoConfig.shared.primaryUIColor ?? UIColor(red: 0xDE / 255, green: 0x48 / 255, blue: 0x1E / 255, alpha: 1)
    private let brandName = "Peach Payments"
    private let surfaceColor = UIColor(red: 0xF5 / 255, green: 0xF8 / 255, blue: 0xF9 / 255, alpha: 1)

    // MARK: - Demo cart (mock data)
    private struct CartItem { let name: String; let qty: Int; let price: Double }
    private let currency = "R"
    private let cartItems: [CartItem] = [
        CartItem(name: "Running Sneakers", qty: 1, price: 424.00),
        CartItem(name: "Ankle Socks (2-pack)", qty: 1, price: 75.00),
    ]
    private var cartTotal: Double { cartItems.reduce(0) { $0 + $1.price * Double($1.qty) } }

    @ObservedObject var hyperViewModel = HyperViewModel()
    private let environmentButton = UIButton(type: .system)
    private let sessionIdTextField = UITextField()
    private let inputStack = UIStackView()
    private var reloadButton = UIButton()
    private var paymentSheetButton = UIButton()
    private var paymentMethodManagementButton = UIButton()
    private var statusLabel = UILabel()
    private var cancellables = Set<AnyCancellable>()

    // Express wallet buttons embedded in the cart: paid directly, no sheet.
    private let expressCheckoutStack = UIStackView()
    private let expressCheckoutLabel = UILabel()
    private var expressCheckoutButton: ExpressCheckoutButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        print("[DemoConfig] launch args: \(ProcessInfo.processInfo.arguments)")
        print("[DemoConfig] parsed: \(DemoConfig.shared)")
        view.backgroundColor = .systemBackground
        hyperViewModel.fetchNetceteraSDKApiKey()
        hyperViewModel.preparePaymentSheet()
        asyncBind()
        viewFrame()
    }

    private func asyncBind() {
        hyperViewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .loading:
                    self?.statusLabel.text = "Loading…"
                case .success:
                    self?.statusLabel.text = "Connected to server"
                    self?.attachExpressCheckout()
                case .failure(let message):
                    self?.statusLabel.text = message
                }
            }
            .store(in: &cancellables)
    }

    @objc
    func openPaymentSheet(_ sender: Any) {

        var configuration = PaymentSheet.Configuration()
        configuration.primaryButtonLabel = "Pay Now"
        configuration.savedPaymentSheetHeaderLabel = "Payment methods"
        configuration.paymentSheetHeaderLabel = "Select payment method"
        configuration.displaySavedPaymentMethods = true

        var appearance = PaymentSheet.Appearance()
        appearance.font.base = UIFont(name: "montserrat", size: UIFont.systemFontSize)
        appearance.font.sizeScaleFactor = 1.0
        appearance.shadow = .disabled

        // Apply appearance overrides from the Appetize launch-param config.
        let cfg = DemoConfig.shared
        if let c = cfg.primaryUIColor { appearance.colors.primary = c }
        if let c = cfg.backgroundUIColor { appearance.colors.background = c }
        if let c = cfg.textUIColor { appearance.colors.text = c }
        if let c = cfg.errorUIColor { appearance.colors.danger = c }
        if let r = cfg.cornerRadius { appearance.cornerRadius = CGFloat(r) }
        if let w = cfg.borderWidth { appearance.borderWidth = CGFloat(w) }

        configuration.appearance = appearance
        if let netceteraApiKey = hyperViewModel.netceteraApiKey {
            configuration.netceteraSDKApiKey = netceteraApiKey
        }

        hyperViewModel.paymentSession?.presentPaymentSheet(
            viewController: self,
            configuration: configuration,
            subscribe: { builder in
                builder.on(.paymentMethodInfoCard) { event in
                    if case .cardInfo(let info) = event.data {
                        print(info)
                    }
                }
            },
            completion: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .completed:
                        self.statusLabel.text = "Payment complete"
                        self.showToast("Payment successful", isError: false)
                    case .failed(let error, let paymentIntent):
                        if let paymentIntent { print("Failed payment intent: \(paymentIntent)") }
                        self.statusLabel.text = "Payment failed: \(error)"
                        self.showToast("Payment failed", isError: true)
                    case .canceled:
                        self.statusLabel.text = "Payment canceled."
                        self.showToast("Payment cancelled", isError: false)
                    }
                }
            }
        )
    }

    @objc
    func openPaymentMethodManagement(_ sender: Any) {
        let paymentMethodVC = PaymentMethodManagementViewController()
        paymentMethodVC.modalPresentationStyle = .fullScreen
        present(paymentMethodVC, animated: true)
    }

    private func selectEnvironment(at index: Int) {
        guard index != hyperViewModel.environmentIndex else { return }
        hyperViewModel.environmentIndex = index
        var config = environmentButton.configuration
        config?.title = HyperViewModel.environments[index].label
        environmentButton.configuration = config
        environmentButton.menu = makeEnvironmentMenu()
        hyperViewModel.fetchNetceteraSDKApiKey()
        hyperViewModel.preparePaymentSheet()
    }

    private func makeEnvironmentMenu() -> UIMenu {
        UIMenu(
            title: "Environment",
            children: HyperViewModel.environments.enumerated().map { (idx, env) in
                UIAction(
                    title: env.label,
                    state: idx == hyperViewModel.environmentIndex ? .on : .off
                ) { [weak self] _ in
                    self?.selectEnvironment(at: idx)
                }
            }
        )
    }

    @objc
    private func sessionIdChanged(_ sender: UITextField) {
        hyperViewModel.sessionId = sender.text ?? ""
    }

    private func configureTextField(_ field: UITextField, placeholder: String, text: String) {
        field.placeholder = placeholder
        field.text = text
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 14)
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.delegate = self
    }

    @objc
    func reload(_ sender: Any) {
        hyperViewModel.fetchNetceteraSDKApiKey()
        hyperViewModel.preparePaymentSheet()
        reloadButton.isUserInteractionEnabled = false
        UIView.animate(
            withDuration: 0.8,
            animations: { self.reloadButton.alpha = 0.4 }
        ) { _ in
            self.reloadButton.alpha = 1.0
            self.reloadButton.isUserInteractionEnabled = true
        }
    }

    /// Transient toast shown when the payment sheet closes (iOS has no native toast).
    func showToast(_ message: String, isError: Bool) {
        let container = UIView()
        container.backgroundColor =
            isError
            ? UIColor(red: 0.86, green: 0.20, blue: 0.24, alpha: 1)
            : UIColor(red: 0.13, green: 0.60, blue: 0.30, alpha: 1)
        container.layer.cornerRadius = 12
        container.alpha = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])

        UIView.animate(withDuration: 0.25, animations: { container.alpha = 1 }) { _ in
            UIView.animate(
                withDuration: 0.25, delay: 2.5, options: [],
                animations: { container.alpha = 0 },
                completion: { _ in container.removeFromSuperview() }
            )
        }
    }
}

extension ViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Layout
extension ViewController {

    private func money(_ value: Double) -> String {
        String(format: "%@%.2f", currency, value)
    }

    func viewFrame() {
        // Scrollable content column so the cart + dev options fit any device.
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 20
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        content.addArrangedSubview(makeHeader())
        content.addArrangedSubview(makeCartCard())
        content.addArrangedSubview(makePayButton())
        content.addArrangedSubview(makeExpressCheckoutSection())
        content.addArrangedSubview(makeDeveloperSection())
    }

    // Container for the wallet buttons. Starts empty — the button can only be
    // built once the payment session exists, which arrives asynchronously.
    private func makeExpressCheckoutSection() -> UIView {
        expressCheckoutLabel.text = "or pay instantly with"
        expressCheckoutLabel.textAlignment = .center
        expressCheckoutLabel.font = .systemFont(ofSize: 13)
        expressCheckoutLabel.textColor = .secondaryLabel
        expressCheckoutLabel.isHidden = true

        expressCheckoutStack.axis = .vertical
        expressCheckoutStack.spacing = 10
        expressCheckoutStack.alignment = .fill
        expressCheckoutStack.addArrangedSubview(expressCheckoutLabel)
        return expressCheckoutStack
    }

    /// Build the express wallet buttons once a session is available. Rebuilt on
    /// reload so the buttons always target the current payment intent.
    private func attachExpressCheckout() {
        guard let paymentSession = hyperViewModel.paymentSession else { return }

        // Drop any button from a previous intent.
        expressCheckoutButton?.removeFromSuperview()
        expressCheckoutButton = nil

        var configuration = PaymentSheet.Configuration()
        configuration.appearance = expressCheckoutAppearance()

        let button = ExpressCheckoutButton(
            paymentSession: paymentSession,
            configuration: configuration
        ) { [weak self] result in
            switch result {
            case .completed(let data):
                self?.statusLabel.text = "Wallet payment complete → \(data)"
            case .canceled:
                self?.statusLabel.text = "Wallet payment canceled."
            case .failed(let error, _):
                self?.statusLabel.text = "Wallet payment failed: \(error.localizedDescription)"
            }
        }

        expressCheckoutButton = button
        expressCheckoutLabel.isHidden = false
        expressCheckoutStack.addArrangedSubview(button)
    }

    private func expressCheckoutAppearance() -> PaymentSheet.Appearance {
        var appearance = PaymentSheet.Appearance()
        let cfg = DemoConfig.shared
        if let c = cfg.primaryUIColor { appearance.colors.primary = c }
        if let r = cfg.cornerRadius { appearance.cornerRadius = CGFloat(r) }
        return appearance
    }

    // Peach logo (or text wordmark fallback) + "Secure checkout" title.
    private func makeHeader() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .leading

        if let logo = UIImage(named: "PeachLogo") {
            let imageView = UIImageView(image: logo)
            imageView.contentMode = .scaleAspectFit
            imageView.heightAnchor.constraint(equalToConstant: 28).isActive = true
            stack.addArrangedSubview(imageView)
        } else {
            let wordmark = UILabel()
            wordmark.text = brandName
            wordmark.font = .systemFont(ofSize: 20, weight: .bold)
            wordmark.textColor = brandColor
            stack.addArrangedSubview(wordmark)
        }

        let title = UILabel()
        title.text = "Secure checkout (Demo Store)"
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = .label
        stack.addArrangedSubview(title)

        return stack
    }

    private func makeCartCard() -> UIView {
        let card = UIView()
        card.backgroundColor = surfaceColor
        card.layer.cornerRadius = 16

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])

        for item in cartItems {
            stack.addArrangedSubview(
                lineRow(
                    left: item.name,
                    sub: "Qty \(item.qty)",
                    right: money(item.price * Double(item.qty))
                )
            )
        }

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(summaryRow(label: "Subtotal", value: money(cartTotal), bold: false))
        stack.addArrangedSubview(summaryRow(label: "Shipping", value: "Free", bold: false))
        stack.addArrangedSubview(summaryRow(label: "Total", value: money(cartTotal), bold: true))

        return card
    }

    private func lineRow(left: String, sub: String, right: String) -> UIView {
        let nameStack = UIStackView()
        nameStack.axis = .vertical
        nameStack.spacing = 2

        let name = UILabel()
        name.text = left
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        name.textColor = .label

        let subtitle = UILabel()
        subtitle.text = sub
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabel

        nameStack.addArrangedSubview(name)
        nameStack.addArrangedSubview(subtitle)

        let price = UILabel()
        price.text = right
        price.font = .systemFont(ofSize: 16, weight: .semibold)
        price.textColor = .label
        price.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [nameStack, price])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    private func summaryRow(label: String, value: String, bold: Bool) -> UIView {
        let l = UILabel()
        l.text = label
        l.font = .systemFont(ofSize: bold ? 18 : 15, weight: bold ? .bold : .regular)
        l.textColor = bold ? .label : .secondaryLabel

        let v = UILabel()
        v.text = value
        v.font = .systemFont(ofSize: bold ? 18 : 15, weight: bold ? .bold : .regular)
        v.textColor = bold ? .label : .secondaryLabel
        v.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [l, v])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func makePayButton() -> UIView {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = brandColor
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        config.title = "Pay \(money(cartTotal))"
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            return outgoing
        }
        paymentSheetButton.configuration = config
        paymentSheetButton.addTarget(self, action: #selector(openPaymentSheet(_:)), for: .touchUpInside)
        return paymentSheetButton
    }

    // Muted "Developer options" section — kept one tap away for testing.
    private func makeDeveloperSection() -> UIView {
        let header = UILabel()
        header.text = "DEVELOPER OPTIONS"
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabel

        // Environment picker + session id
        let currentLabel = HyperViewModel.environments[hyperViewModel.environmentIndex].label
        var envConfig = UIButton.Configuration.bordered()
        envConfig.baseForegroundColor = .secondaryLabel
        envConfig.title = currentLabel
        envConfig.image = UIImage(systemName: "chevron.down")
        envConfig.imagePlacement = .trailing
        envConfig.imagePadding = 6
        envConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        environmentButton.configuration = envConfig
        environmentButton.menu = makeEnvironmentMenu()
        environmentButton.showsMenuAsPrimaryAction = true
        environmentButton.changesSelectionAsPrimaryAction = false

        configureTextField(sessionIdTextField, placeholder: "Session ID (optional)", text: hyperViewModel.sessionId)
        sessionIdTextField.autocapitalizationType = .none
        sessionIdTextField.autocorrectionType = .no
        sessionIdTextField.addTarget(self, action: #selector(sessionIdChanged(_:)), for: .editingChanged)

        inputStack.axis = .horizontal
        inputStack.spacing = 8
        inputStack.distribution = .fillEqually
        inputStack.addArrangedSubview(environmentButton)
        inputStack.addArrangedSubview(sessionIdTextField)

        // Secondary (muted) buttons
        styleSecondary(reloadButton, title: "Reload Client Secret", action: #selector(reload(_:)))
        styleSecondary(
            paymentMethodManagementButton,
            title: "Manage Payment Methods",
            action: #selector(openPaymentMethodManagement(_:))
        )

        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [
            header, inputStack, reloadButton, paymentMethodManagementButton, statusLabel,
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: header)
        return stack
    }

    private func styleSecondary(_ button: UIButton, title: String, action: Selector) {
        var config = UIButton.Configuration.bordered()
        config.baseForegroundColor = .secondaryLabel
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        config.title = title
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            return outgoing
        }
        button.configuration = config
        button.addTarget(self, action: action, for: .touchUpInside)
    }
}
