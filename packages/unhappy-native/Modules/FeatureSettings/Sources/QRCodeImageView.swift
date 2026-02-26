import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct QRCodeImageView: View {
    let content: String
    var size: CGFloat = 220

    var body: some View {
        Group {
            if let image = generateImage(from: content) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        Text("Unable to generate QR")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Account restore QR code")
    }

    private func generateImage(from text: String) -> UIImage? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else {
            return nil
        }

        let scaleX = size / output.extent.width
        let scaleY = size / output.extent.height
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        guard let cgImage = QRCodeImageView.context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static let context = CIContext()
}
