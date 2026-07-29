//
//  ContentView.swift
//  Hyperswitch
//
//  Created by Shivam Shashank on 09/12/22.
//

import SwiftUI

struct ContentView: View {
    // UIKit is the primary demo surface. The other views (SwiftUI, Headless,
    // 3DS, C2P, Widget) remain available as UIViewControllerRepresentables
    // below for ad-hoc testing, but the segmented tab bar has been removed.
    var body: some View {
        UIKitView()
    }
}
struct HeadlessView: UIViewControllerRepresentable {
    typealias UIViewControllerType = HeadlessViewController

    func makeUIViewController(context: Context) -> HeadlessViewController {
        return HeadlessViewController()
    }

    func updateUIViewController(_ uiViewController: HeadlessViewController, context: Context) {
    }
}

struct UIKitView: UIViewControllerRepresentable {
    typealias UIViewControllerType = ViewController

    func makeUIViewController(context: Context) -> ViewController {
        return ViewController()
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
    }
}

struct ThreeDSView: UIViewControllerRepresentable {
    typealias UIViewControllerType = AuthenticationViewController

    func makeUIViewController(context: Context) -> AuthenticationViewController {
        return AuthenticationViewController()
    }

    func updateUIViewController(_ uiViewController: AuthenticationViewController, context: Context) {
    }
}

struct ClickToPayView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UINavigationController

    func makeUIViewController(context: Context) -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: ClickToPayViewController())
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
    }
}

struct WidgetView: UIViewControllerRepresentable {
    typealias UIViewControllerType = WidgetViewController

    func makeUIViewController(context: Context) -> WidgetViewController {
        return WidgetViewController()
    }

    func updateUIViewController(_ uiViewController: WidgetViewController, context: Context) {
    }
}
