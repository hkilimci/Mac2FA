import SwiftUI
import UniformTypeIdentifiers
import Vision

struct QRImageImportView: View {
    /// Called with the accounts found in the image's QR codes.
    let onFound: ([ImportCandidate]) -> Void

    @State private var isTargeted = false
    @State private var isChoosingFile = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            dropZone
                .padding(.horizontal, 20)
                .padding(.top, 16)

            SheetFooter {
                Button("Choose Image…") {
                    isChoosingFile = true
                }
            }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                loadImage(at: url)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text("Drop a QR Code Image Here")
                .font(.headline)
            Text("Use a screenshot of the QR code, or of the Transfer Accounts screen in Google Authenticator.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            }
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func loadImage(at url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
        guard let image = NSImage(contentsOf: url) else {
            problem = "This file couldn't be opened as an image."
            return
        }
        processImage(image)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage {
                        DispatchQueue.main.async {
                            processImage(image)
                        }
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    if let data = data as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       let image = NSImage(contentsOf: url) {
                        DispatchQueue.main.async {
                            processImage(image)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func processImage(_ image: NSImage) {
        problem = nil
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            problem = "This image couldn't be read."
            return
        }

        let payloads: [String]
        do {
            payloads = try QRCodeReader.payloads(in: cgImage)
        } catch {
            problem = "This image couldn't be analyzed."
            return
        }
        guard !payloads.isEmpty else {
            problem = "No QR code was found in this image."
            return
        }

        let drafts = payloads.flatMap { (try? OTPPayload.drafts(from: $0)) ?? [] }
        guard !drafts.isEmpty else {
            problem = "This QR code doesn't contain a two-factor authentication account."
            return
        }
        onFound(drafts.map(ImportCandidate.init(draft:)))
    }
}

private enum QRCodeReader {
    /// Text of every QR code found in the image.
    static func payloads(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}
