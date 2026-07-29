//
//  SwiftUIview.swift
//  hyperswitch
//
//  Created by Harshit Srivastava on 25/10/24.
//

import SwiftUI

struct SwiftUIView: View {
    @ObservedObject var hyperViewModel = HyperViewModel()
    @State var paymentResult: PaymentResult?

    var body: some View {
        ZStack(alignment: .top) {
            Color.gray.opacity(0.2)
                .ignoresSafeArea()
            LazyVStack(spacing: 94) {
                Button {
                    hyperViewModel.preparePaymentSheet()
                } label: {
                    Text("Reload Client Secret")
                }.padding(.vertical, 11)
                    .padding(.horizontal, 58)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10.0)
                Spacer()
                if let paymentSession = hyperViewModel.paymentSession {
                    PaymentSheet.PaymentButtonLite(
                        paymentSession: paymentSession,
                        configuration: setupConfiguration(),
                        onCompletion: onPaymentCompletion
                    ) {
                        Text("Launch Payment Sheet")
                            .padding(.vertical, 11)
                            .padding(.horizontal, 58)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10.0)
                    }

                    if let result = paymentResult {
                        switch result {
                        case .completed:
                            Text("Payment complete")
                                .padding()
                        case .failed(let error as NSError, _):
                            Text("Payment failed: \(error)")
                                .padding()
                        case .canceled:
                            Text("Payment canceled.")
                                .padding()
                        }
                    }
                }
            }.onAppear { hyperViewModel.preparePaymentSheet() }
                .padding(.top, 80)
        }
    }
    func setupConfiguration() -> PaymentSheet.Configuration {
        var configuration = PaymentSheet.Configuration()
        configuration.primaryButtonLabel = "Pay Now"
        configuration.savedPaymentSheetHeaderLabel = "Payment methods"
        configuration.paymentSheetHeaderLabel = "Select payment method"
        configuration.displaySavedPaymentMethods = true

        var appearance = PaymentSheet.Appearance()
        appearance.font.base = UIFont(name: "montserrat", size: UIFont.systemFontSize)
        appearance.font.sizeScaleFactor = 1.0
        appearance.shadow = .disabled
        
        configuration.appearance = appearance

        return configuration
    }
    func onPaymentCompletion(result: PaymentResult) {
        DispatchQueue.main.async {
            paymentResult = result
        }
    }
}
