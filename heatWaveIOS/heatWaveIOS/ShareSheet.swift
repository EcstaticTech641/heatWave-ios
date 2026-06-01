// ShareSheet.swift
// heatWaveIOS
//
// Minimum Deployment Target: iOS 16.0
//
// A SwiftUI wrapper around UIActivityViewController for sharing files.

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}
