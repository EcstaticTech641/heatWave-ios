// DocumentPicker.swift
// heatWaveIOS
//
// A UIViewControllerRepresentable wrapper around UIDocumentPickerViewController.
// Presents the native iOS Files picker, restricted to PDF files only.
// Returns the file URL to the caller via a completion closure.
//
// Usage in a SwiftUI view:
//   .sheet(isPresented: $isPresented) {
//       DocumentPicker(allowedTypes: ["com.adobe.pdf"]) { url in
//           // handle selected url
//       }
//   }

import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {

    // UTType strings for the file types to display (e.g. "com.adobe.pdf")
    let allowedTypes: [String]

    // Called on the main thread when the user picks exactly one document.
    let onPick: (URL) -> Void

    // MARK: - UIViewControllerRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = allowedTypes.compactMap { UTType($0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        // asCopy: true — copies the file into our sandbox so we have read access
        // without needing to maintain a security-scoped resource bookmark.
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No dynamic updates needed; picker configuration is set at creation time.
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIDocumentPickerDelegate {

        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User dismissed without picking; nothing to do —
            // ContentView retains its current state.
        }
    }
}
