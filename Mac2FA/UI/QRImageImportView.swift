import SwiftUI
import Vision

struct QRImageImportView: View {
    var onDone: (Bool) -> Void
    @State private var image: NSImage?
    @State private var drafts: [OTPAccountDraft] = []
    @State private var selectedIndices: Set<Int> = []
    @State private var showingPreview = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isTargeted = false

    private var selectableIndices: [Int] {
        drafts.indices.filter { drafts[$0].type == .totp }
    }

    private var allSelectableSelected: Bool {
        !selectableIndices.isEmpty && selectableIndices.allSatisfy { selectedIndices.contains($0) }
    }

    var body: some View {
        VStack {
            if !showingPreview {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [10]))
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.05)))

                    VStack(spacing: 12) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Drag and drop a QR image here")
                            .foregroundStyle(.secondary)
                        Button("Select Image...") {
                            selectImage()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
                    handleDrop(providers: providers)
                }
            } else {
                HStack {
                    Button(allSelectableSelected ? "Deselect All" : "Select All") {
                        if allSelectableSelected {
                            selectedIndices.removeAll()
                        } else {
                            selectedIndices = Set(selectableIndices)
                        }
                    }
                    .disabled(selectableIndices.isEmpty)
                    Spacer()
                    Text("\(selectedIndices.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                List {
                    ForEach(drafts.indices, id: \.self) { index in
                        let draft = drafts[index]
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { selectedIndices.contains(index) },
                                set: { isOn in
                                    if isOn {
                                        selectedIndices.insert(index)
                                    } else {
                                        selectedIndices.remove(index)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .disabled(draft.type != .totp)
                            VStack(alignment: .leading) {
                                Text(draft.issuer.isEmpty ? "Unknown" : draft.issuer)
                                    .font(.headline)
                                Text(draft.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if draft.type == .hotp {
                                Text("HOTP (unsupported)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("TOTP \(draft.digits) digits")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack {
                    Button("Back") {
                        showingPreview = false
                    }
                    Button("Import Selected (\(selectedIndices.count))") {
                        importSelected()
                    }
                    .disabled(selectedIndices.isEmpty)
                }
                .padding()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .padding()
    }

    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.beginSheetModal(for: NSApp.keyWindow!) { result in
            if result == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
                processImage(image)
            }
        }
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
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorMessage = "Failed to read image."
            showingError = true
            return
        }

        let request = VNDetectBarcodesRequest { request, error in
            guard let results = request.results as? [VNBarcodeObservation], !results.isEmpty else {
                DispatchQueue.main.async {
                    errorMessage = "No QR code found in image."
                    showingError = true
                }
                return
            }

            var allDrafts: [OTPAccountDraft] = []
            for result in results {
                guard let payload = result.payloadStringValue else { continue }
                if payload.hasPrefix("otpauth-migration://") {
                    if let parsed = try? GoogleMigrationParser.parse(payload) {
                        allDrafts.append(contentsOf: parsed)
                    }
                } else if payload.hasPrefix("otpauth://") {
                    if let parsed = try? OTPAuthParser.parse(payload) {
                        allDrafts.append(parsed)
                    }
                }
            }

            DispatchQueue.main.async {
                if allDrafts.isEmpty {
                    errorMessage = "No valid OTP QR codes found."
                    showingError = true
                } else {
                    drafts = allDrafts
                    selectedIndices = Set(allDrafts.indices.filter { allDrafts[$0].type == .totp })
                    showingPreview = true
                }
            }
        }
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            self.errorMessage = "Failed to analyze image."
            self.showingError = true
        }
    }

    private func importSelected() {
        let selected = selectedIndices.sorted().compactMap { drafts.indices.contains($0) ? drafts[$0] : nil }
        Task {
            var imported = 0
            for draft in selected {
                guard draft.type == .totp else { continue }
                do {
                    _ = try await AccountStore.shared.addAccount(draft: draft)
                    imported += 1
                } catch AccountStoreError.duplicateAccount {
                    // Skip duplicates
                } catch {
                    // Skip failed
                }
            }
            await MainActor.run {
                onDone(imported > 0)
            }
        }
    }
}
