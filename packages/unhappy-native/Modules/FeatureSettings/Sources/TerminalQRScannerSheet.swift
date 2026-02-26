import SwiftUI
import AVFoundation
#if canImport(VisionKit)
import VisionKit
#endif

@MainActor
struct TerminalQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isRequestingPermission = false
    @State private var scannerErrorMessage: String?

    let onScanned: @MainActor (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isRequestingPermission {
                    ProgressView("Requesting camera access...")
                } else if authorizationStatus == .authorized {
                    scannerContent
                } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                    deniedContent
                } else {
                    ProgressView("Preparing scanner...")
                }
            }
            .navigationTitle("Scan Terminal QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await requestPermissionIfNeeded()
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
#if canImport(VisionKit)
        #if targetEnvironment(simulator)
        unsupportedContent
        #else
        if #available(iOS 16.0, *),
           DataScannerViewController.isSupported,
           DataScannerViewController.isAvailable {
            TerminalDataScannerView(
                onScanned: { value in
                    onScanned(value)
                    dismiss()
                },
                onError: { message in
                    scannerErrorMessage = message
                }
            )
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if let scannerErrorMessage, !scannerErrorMessage.isEmpty {
                        Text(scannerErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Text("Align the QR code in the center of the camera preview.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
        } else {
            unsupportedContent
        }
        #endif
#else
        unsupportedContent
#endif
    }

    private var deniedContent: some View {
        VStack(spacing: 12) {
            Text("Camera access is required to scan terminal QR codes.")
                .multilineTextAlignment(.center)
            Text("Enable Camera permission in Settings and reopen scanner.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var unsupportedContent: some View {
        VStack(spacing: 12) {
            Text("QR scanner is unavailable on this device.")
                .multilineTextAlignment(.center)
            Text("Use \"Paste from Clipboard\" in Terminal settings instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func requestPermissionIfNeeded() async {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = currentStatus
        guard currentStatus == .notDetermined else { return }

        isRequestingPermission = true
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        isRequestingPermission = false
        authorizationStatus = granted ? .authorized : .denied
    }
}

#if canImport(VisionKit)
@available(iOS 16.0, *)
private struct TerminalDataScannerView: UIViewControllerRepresentable {
    let onScanned: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onError: onError)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !context.coordinator.hasStartedScanning else { return }
        do {
            try uiViewController.startScanning()
            context.coordinator.hasStartedScanning = true
        } catch {
            context.coordinator.reportError("Failed to start scanner: \(error.localizedDescription)")
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
        coordinator.hasStartedScanning = false
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var hasStartedScanning = false
        private var hasEmitted = false
        private let onScanned: (String) -> Void
        private let onError: (String) -> Void

        init(
            onScanned: @escaping (String) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onScanned = onScanned
            self.onError = onError
        }

        func reportError(_ message: String) {
            onError(message)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasEmitted else { return }
            guard
                let scannedValue = addedItems
                    .compactMap({ item in
                        if case .barcode(let barcode) = item {
                            return barcode.payloadStringValue
                        }
                        return nil
                    })
                    .first
            else {
                return
            }

            hasEmitted = true
            onScanned(scannedValue)
        }
    }
}
#endif
