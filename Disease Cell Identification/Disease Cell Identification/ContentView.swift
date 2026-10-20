/*
 https://bbbc.broadinstitute.org/image_sets?utm_source=chatgpt.com
 */

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import CoreGraphics
import Combine

// MARK: - Main View

struct ContentView: View {
    @StateObject private var memory = CellMemory()

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var currentImage: UIImage?
    @State private var reconstructedImage: UIImage?
    @State private var currentFeatures: CellFeatures?
    @State private var matches: [PatternMatch] = []

    @State private var selectedLabel: CellLabel = .unlabeled
    @State private var imageName = ""
    @State private var statusMessage = "Import a cell image to begin."
    @State private var isProcessing = false
    @State private var showingFileImporter = false
    @State private var showingLabelPrompt = false
    @State private var pendingImportedImage: UIImage?
    @State private var pendingImportedName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    importSection

                    if let currentImage {
                        imageSection(
                            title: "Imported image",
                            image: currentImage
                        )
                    }

                    if let reconstructedImage {
                        imageSection(
                            title: "Cellular-automaton reconstruction",
                            image: reconstructedImage
                        )
                    }

                    if let currentFeatures {
                        featureSection(currentFeatures)
                    }

                    if !matches.isEmpty {
                        matchSection
                    }

                    memorySection

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Cell Pattern Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        clearCurrentAnalysis()
                    }
                    .disabled(isProcessing)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item, .data, .image],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }

            .confirmationDialog(
                "Classify this image",
                isPresented: $showingLabelPrompt,
                titleVisibility: .visible
            ) {
                Button("Healthy reference") {
                    savePendingImage(as: .healthyReference)
                }

                Button("Disease-labeled reference") {
                    savePendingImage(as: .diseaseReference)
                }

                Button("Unlabeled image") {
                    savePendingImage(as: .unlabeled)
                }

                Button("Cancel", role: .cancel) {
                    pendingImportedImage = nil
                }
            } message: {
                Text(
                    "Use a label only when it is supported by reliable " +
                    "ground truth. Labels are reference categories, not diagnoses."
                )
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    await loadPhoto(item)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cellular Pattern Reconstruction")
                .font(.title2.bold())

            Text(
                "Import microscopy images, reconstruct their grayscale " +
                "patterns, extract measurable features, and compare them " +
                "with locally stored reference images."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text("Research prototype — not a clinical diagnostic tool")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Import

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import image")
                .font(.headline)

            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Choose from Photos", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showingFileImporter = true
            } label: {
                Label("Import image or DIB/BMP file", systemImage: "doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text(
                "Supported image files depend on the system decoder. " +
                "The included DIB decoder supports common uncompressed " +
                "8-bit indexed, 24-bit BGR, and 32-bit BGRA bitmap data."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                analyzeCurrentImage()
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(
                        isProcessing
                        ? "Processing…"
                        : "Reconstruct and Analyze"
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentImage == nil || isProcessing)

            Button {
                guard let currentImage else { return }
                pendingImportedImage = currentImage
                pendingImportedName = imageName.isEmpty
                    ? "Cell image"
                    : imageName
                showingLabelPrompt = true
            } label: {
                Label("Save to Image Memory", systemImage: "externaldrive")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(currentImage == nil || isProcessing)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Image Display

    private func imageSection(
        title: String,
        image: UIImage
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 320)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            Color.secondary.opacity(0.2),
                            lineWidth: 1
                        )
                }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Feature Display

    private func featureSection(_ features: CellFeatures) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extracted image features")
                .font(.headline)

            featureRow(
                "Foreground fraction",
                value: features.foregroundFraction
            )

            featureRow(
                "Mean intensity",
                value: features.meanIntensity
            )

            featureRow(
                "Texture variation",
                value: features.textureVariation
            )

            featureRow(
                "Boundary irregularity",
                value: features.boundaryIrregularity
            )

            Text(
                "These are image-level descriptors, not validated " +
                "biological measurements. Their meaning depends on image " +
                "staining, illumination, magnification, and preprocessing."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func featureRow(
        _ title: String,
        value: Double
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)

            Spacer()

            Text(value, format: .number.precision(.fractionLength(3)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Reference Matching

    private var matchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Closest stored references")
                .font(.headline)

            Text(
                "Ranked by feature distance. A smaller distance means " +
                "the extracted image features are more similar; it does " +
                "not mean the image has a particular disease."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(matches) { match in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(match.record.name)
                                .font(.subheadline.bold())

                            Text(match.record.label.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(
                            match.distance,
                            format: .number.precision(.fractionLength(3))
                        )
                        .font(.subheadline.monospacedDigit())
                    }

                    ProgressView(
                        value: 1.0 / (1.0 + max(0, match.distance))
                    )
                    .tint(.blue)
                }
                .padding(.vertical, 5)
            }

            if matches.isEmpty {
                Text("No comparable reference images are available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Stored Image Memory

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local image memory")
                    .font(.headline)

                Spacer()

                Text("\(memory.records.count) saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if memory.records.isEmpty {
                Text(
                    "Saved images will appear here. Images and their " +
                    "labels are stored locally in the app's Application Support folder."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                ForEach(memory.records) { record in
                    HStack(alignment: .top, spacing: 10) {
                        if let thumbnail = memory.loadThumbnail(for: record) {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 8)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 58, height: 58)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.name)
                                .font(.subheadline.bold())

                            Text(record.label.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(record.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 4)

                        Button("Load") {
                            loadStoredImage(record)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            memory.delete(record)
                            statusMessage = "Removed \(record.name) from memory."
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(record.name)")
                    }

                    if record.id != memory.records.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Import Handlers

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                statusMessage = "Could not read the selected photo."
                return
            }

            setCurrentImage(image, name: "Photo import")
            statusMessage = "Photo imported. Run reconstruction to analyze it."
        } catch {
            statusMessage = "Photo import failed: \(error.localizedDescription)"
        }
    }

    private func handleFileImport(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                statusMessage = "No file was selected."
                return
            }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)

                let image: UIImage?
                if DIBImageDecoder.looksLikeBitmap(data) {
                    image = DIBImageDecoder.decode(data)
                } else {
                    image = UIImage(data: data)
                }

                guard let image else {
                    statusMessage =
                        "The file could not be decoded. The format may be unsupported."
                    return
                }

                setCurrentImage(image, name: url.lastPathComponent)
                statusMessage =
                    "Imported \(url.lastPathComponent). Run reconstruction to analyze it."
            } catch {
                statusMessage = "File import failed: \(error.localizedDescription)"
            }

        case .failure(let error):
            statusMessage = "File selection failed: \(error.localizedDescription)"
        }
    }

    private func setCurrentImage(
        _ image: UIImage,
        name: String
    ) {
        currentImage = image
        reconstructedImage = nil
        currentFeatures = nil
        matches = []
        imageName = name
    }

    // MARK: - Analysis

    private func analyzeCurrentImage() {
        guard let image = currentImage else { return }

        isProcessing = true
        statusMessage = "Reconstructing image and calculating features…"

        Task {
            do {
                let result = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try CellAnalyzer.analyze(image)
                }.value

                await MainActor.run {
                    reconstructedImage = result.reconstruction
                    currentFeatures = result.features

                    matches = memory.findMatches(
                        features: result.features,
                        excludingName: imageName,
                        limit: 5
                    )

                    isProcessing = false
                    statusMessage =
                        "Analysis complete. Reference distances are exploratory similarity measures."
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    statusMessage =
                        "Analysis failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Save / Load

    private func savePendingImage(as label: CellLabel) {
        guard let image = pendingImportedImage else { return }

        let name = pendingImportedName.isEmpty
            ? "Cell image"
            : pendingImportedName

        memory.save(image, name: name, label: label)

        pendingImportedImage = nil
        statusMessage = "Saved \(name) as \(label.displayName)."

        if let currentFeatures {
            matches = memory.findMatches(
                features: currentFeatures,
                excludingName: imageName,
                limit: 5
            )
        }
    }

    private func loadStoredImage(_ record: CellMemoryRecord) {
        guard let image = memory.loadImage(for: record) else {
            statusMessage = "Could not load the stored image."
            return
        }

        setCurrentImage(image, name: record.name)
        statusMessage = "Loaded \(record.name). Run reconstruction to analyze it."
    }

    private func clearCurrentAnalysis() {
        currentImage = nil
        reconstructedImage = nil
        currentFeatures = nil
        matches = []
        imageName = ""
        selectedPhoto = nil
        statusMessage = "Import a cell image to begin."
    }
}

// MARK: - Cell Labels

enum CellLabel: String, Codable, CaseIterable, Identifiable {
    case unlabeled
    case healthyReference
    case diseaseReference

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unlabeled:
            return "Unlabeled"
        case .healthyReference:
            return "Healthy reference"
        case .diseaseReference:
            return "Disease-labeled reference"
        }
    }
}

// MARK: - Stored Image Record

struct CellMemoryRecord: Codable, Identifiable {
    var id: UUID
    var name: String
    var filename: String
    var label: CellLabel
    var createdAt: Date
    var features: CellFeatures?
}

// MARK: - Feature Vector

struct CellFeatures: Codable, Equatable {
    var foregroundFraction: Double
    var meanIntensity: Double
    var textureVariation: Double
    var boundaryIrregularity: Double

    func distance(to other: CellFeatures) -> Double {
        let a = [
            foregroundFraction,
            meanIntensity,
            textureVariation,
            boundaryIrregularity
        ]

        let b = [
            other.foregroundFraction,
            other.meanIntensity,
            other.textureVariation,
            other.boundaryIrregularity
        ]

        let weights = [1.0, 0.8, 1.2, 1.0]

        let weightedSquaredDistance = zip(zip(a, b), weights)
            .reduce(0.0) { partial, pair in
                let ((lhs, rhs), weight) = pair
                let difference = lhs - rhs
                return partial + weight * difference * difference
            }

        return sqrt(weightedSquaredDistance)
    }
}

// MARK: - Pattern Match

struct PatternMatch: Identifiable {
    var record: CellMemoryRecord
    var distance: Double

    var id: UUID { record.id }
}

// MARK: - Local Image Memory

@MainActor
final class CellMemory: ObservableObject {
    @Published private(set) var records: [CellMemoryRecord] = []

    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let indexURL: URL

    init() {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        directoryURL = base.appendingPathComponent(
            "CellPatternMemory",
            isDirectory: true
        )

        indexURL = directoryURL.appendingPathComponent("index.json")

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            loadIndex()
        } catch {
            records = []
        }
    }

    func save(
        _ image: UIImage,
        name: String,
        label: CellLabel
    ) {
        guard let data = normalizedImage(image).jpegData(
            compressionQuality: 0.95
        ) else {
            return
        }

        let id = UUID()
        let filename = "\(id.uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL, options: .atomic)

            let features = try? CellAnalyzer.analyze(image).features

            let record = CellMemoryRecord(
                id: id,
                name: name,
                filename: filename,
                label: label,
                createdAt: Date(),
                features: features
            )

            records.insert(record, at: 0)
            saveIndex()
        } catch {
            print("Could not save image: \(error)")
        }
    }

    func loadImage(for record: CellMemoryRecord) -> UIImage? {
        let url = directoryURL.appendingPathComponent(record.filename)
        return UIImage(contentsOfFile: url.path)
    }

    func loadThumbnail(for record: CellMemoryRecord) -> UIImage? {
        guard let image = loadImage(for: record) else { return nil }

        let maxDimension: CGFloat = 180
        let scale = min(
            maxDimension / max(image.size.width, 1),
            maxDimension / max(image.size.height, 1),
            1
        )

        let size = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func delete(_ record: CellMemoryRecord) {
        let url = directoryURL.appendingPathComponent(record.filename)
        try? fileManager.removeItem(at: url)

        records.removeAll { $0.id == record.id }
        saveIndex()
    }

    func findMatches(
        features: CellFeatures,
        excludingName: String,
        limit: Int
    ) -> [PatternMatch] {
        records.compactMap { record in
            guard let referenceFeatures = record.features else {
                return nil
            }

            guard record.name != excludingName else {
                return nil
            }

            return PatternMatch(
                record: record,
                distance: features.distance(to: referenceFeatures)
            )
        }
        .sorted { $0.distance < $1.distance }
        .prefix(limit)
        .map { $0 }
    }

    private func normalizedImage(_ image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else {
            records = []
            return
        }

        do {
            records = try JSONDecoder().decode(
                [CellMemoryRecord].self,
                from: data
            )
        } catch {
            records = []
        }
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("Could not save image index: \(error)")
        }
    }
}

// MARK: - Image Analysis Result

struct CellAnalysisResult {
    var reconstruction: UIImage
    var features: CellFeatures
}

// MARK: - Cellular Automaton Image Analyzer

enum CellAnalyzer {
    static let gridWidth = 64
    static let gridHeight = 64

    static func analyze(_ image: UIImage) throws -> CellAnalysisResult {
        let pixels = try grayscalePixels(
            from: image,
            width: gridWidth,
            height: gridHeight
        )

        let reconstructedPixels = runCellularAutomaton(
            pixels,
            width: gridWidth,
            height: gridHeight,
            iterations: 12
        )

        let features = extractFeatures(
            from: reconstructedPixels,
            width: gridWidth,
            height: gridHeight
        )

        let reconstruction = makeImage(
            from: reconstructedPixels,
            width: gridWidth,
            height: gridHeight
        )

        return CellAnalysisResult(
            reconstruction: reconstruction,
            features: features
        )
    }

    // Convert the image to a normalized grayscale grid.

    private static func grayscalePixels(
        from image: UIImage,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        guard width > 0, height > 0 else {
            throw AnalysisError.invalidDimensions
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        var pixels = [UInt8](
            repeating: 0,
            count: width * height
        )

        let success = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .high
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let rect = CGRect(x: 0, y: 0, width: width, height: height)

            if let cgImage = image.cgImage {
                context.draw(cgImage, in: rect)
            } else {
                let renderer = UIGraphicsImageRenderer(
                    size: CGSize(width: width, height: height)
                )

                let rendered = renderer.image { _ in
                    image.draw(in: rect)
                }

                if let cgImage = rendered.cgImage {
                    context.draw(cgImage, in: rect)
                } else {
                    return false
                }
            }

            return true
        }

        guard success else {
            throw AnalysisError.couldNotCreateImageContext
        }

        return pixels
    }

    // A simple iterative smoothing rule.
    // This is an image-processing automaton, not a biological cell model.

    private static func runCellularAutomaton(
        _ input: [UInt8],
        width: Int,
        height: Int,
        iterations: Int
    ) -> [UInt8] {
        var current = input

        guard width > 2, height > 2 else {
            return current
        }

        for _ in 0..<iterations {
            var next = current

            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let index = y * width + x

                    let neighborhood = [
                        current[index - width - 1],
                        current[index - width],
                        current[index - width + 1],
                        current[index - 1],
                        current[index],
                        current[index + 1],
                        current[index + width - 1],
                        current[index + width],
                        current[index + width + 1]
                    ]

                    let average = neighborhood.reduce(0) {
                        $0 + Int($1)
                    } / neighborhood.count

                    let original = Int(current[index])

                    // Preserve some of the original pixel while smoothing.
                    let updated = (original * 2 + average) / 3
                    next[index] = UInt8(
                        min(255, max(0, updated))
                    )
                }
            }

            current = next
        }

        return current
    }

    // Compute normalized image descriptors.

    private static func extractFeatures(
        from pixels: [UInt8],
        width: Int,
        height: Int
    ) -> CellFeatures {
        let count = max(1, pixels.count)

        let normalized = pixels.map { Double($0) / 255.0 }

        let mean = normalized.reduce(0, +) / Double(count)

        let threshold = mean
        let foregroundCount = normalized.filter {
            $0 < threshold
        }.count

        let foregroundFraction =
            Double(foregroundCount) / Double(count)

        var variation = 0.0
        var edgeChanges = 0.0
        var edgeCount = 0.0
        var boundaryChanges = 0.0
        var boundaryCount = 0.0

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value = normalized[index]

                if x + 1 < width {
                    let right = normalized[index + 1]
                    variation += abs(value - right)
                    edgeCount += 1

                    if (value < threshold) != (right < threshold) {
                        edgeChanges += 1
                    }
                }

                if y + 1 < height {
                    let below = normalized[index + width]
                    variation += abs(value - below)
                    edgeCount += 1

                    if (value < threshold) != (below < threshold) {
                        edgeChanges += 1
                    }
                }

                if x == 0 || y == 0 ||
                    x == width - 1 || y == height - 1 {
                    boundaryCount += 1

                    if value < threshold {
                        boundaryChanges += 1
                    }
                }
            }
        }

        let textureVariation = edgeCount > 0
            ? variation / edgeCount
            : 0

        let boundaryIrregularity = boundaryCount > 0
            ? boundaryChanges / boundaryCount
            : 0

        // edgeChanges is included in the texture descriptor's supporting
        // calculation, but it is not treated as a clinical measure.
        _ = edgeChanges

        return CellFeatures(
            foregroundFraction: foregroundFraction,
            meanIntensity: mean,
            textureVariation: textureVariation,
            boundaryIrregularity: boundaryIrregularity
        )
    }

    // Convert the grid back into a grayscale UIImage.

    private static func makeImage(
        from pixels: [UInt8],
        width: Int,
        height: Int
    ) -> UIImage {
        let data = Data(pixels)

        let provider = CGDataProvider(data: data as CFData)!

        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.none.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!

        return UIImage(cgImage: cgImage)
    }

    enum AnalysisError: LocalizedError {
        case invalidDimensions
        case couldNotCreateImageContext

        var errorDescription: String? {
            switch self {
            case .invalidDimensions:
                return "The image dimensions are invalid."
            case .couldNotCreateImageContext:
                return "Could not create the grayscale image context."
            }
        }
    }
}

// MARK: - DIB / BMP Decoder

enum DIBImageDecoder {
    static func looksLikeBitmap(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }

        return data[data.startIndex] == 0x42 &&
               data[data.startIndex + 1] == 0x4D
    }

    static func decode(_ data: Data) -> UIImage? {
        let bytes = [UInt8](data)

        guard bytes.count >= 54,
              bytes[0] == 0x42,
              bytes[1] == 0x4D else {
            return nil
        }

        let pixelOffset = Int(readUInt32(bytes, at: 10))
        let dibHeaderSize = Int(readUInt32(bytes, at: 14))

        guard dibHeaderSize >= 40,
              bytes.count >= 14 + dibHeaderSize else {
            return nil
        }

        let width = Int(readInt32(bytes, at: 18))
        let signedHeight = readInt32(bytes, at: 22)
        let height = Int(abs(signedHeight))
        let planes = readUInt16(bytes, at: 26)
        let bitsPerPixel = readUInt16(bytes, at: 28)
        let compression = readUInt32(bytes, at: 30)

        guard width > 0,
              height > 0,
              width <= 20_000,
              height <= 20_000,
              planes == 1,
              compression == 0,
              [8, 24, 32].contains(bitsPerPixel),
              pixelOffset >= 14 + dibHeaderSize,
              pixelOffset < bytes.count else {
            return nil
        }

        let bytesPerPixel = Int(bitsPerPixel / 8)
        let rawRowBytes = width * bytesPerPixel
        let rowStride = ((rawRowBytes + 3) / 4) * 4

        guard rowStride > 0,
              height <= (bytes.count - pixelOffset) / rowStride else {
            return nil
        }

        var rgba = [UInt8](
            repeating: 255,
            count: width * height * 4
        )

        let colorsUsed = Int(readUInt32(bytes, at: 46))
        let paletteStart = 14 + dibHeaderSize

        var palette: [[UInt8]] = []

        if bitsPerPixel == 8 {
            let paletteCount = colorsUsed == 0 ? 256 : colorsUsed

            guard paletteCount > 0,
                  paletteCount <= 256,
                  paletteStart + paletteCount * 4 <= pixelOffset else {
                return nil
            }

            for i in 0..<paletteCount {
                let p = paletteStart + i * 4
                palette.append([
                    bytes[p + 2],
                    bytes[p + 1],
                    bytes[p],
                    255
                ])
            }
        }

        let isBottomUp = signedHeight > 0

        for y in 0..<height {
            let sourceY = isBottomUp ? height - 1 - y : y
            let sourceRow = pixelOffset + sourceY * rowStride

            for x in 0..<width {
                let destination = (y * width + x) * 4
                let source = sourceRow + x * bytesPerPixel

                switch bitsPerPixel {
                case 8:
                    let paletteIndex = Int(bytes[source])

                    guard palette.indices.contains(paletteIndex) else {
                        return nil
                    }

                    let color = palette[paletteIndex]
                    rgba[destination] = color[0]
                    rgba[destination + 1] = color[1]
                    rgba[destination + 2] = color[2]
                    rgba[destination + 3] = 255

                case 24:
                    rgba[destination] = bytes[source + 2]
                    rgba[destination + 1] = bytes[source + 1]
                    rgba[destination + 2] = bytes[source]
                    rgba[destination + 3] = 255

                case 32:
                    rgba[destination] = bytes[source + 2]
                    rgba[destination + 1] = bytes[source + 1]
                    rgba[destination + 2] = bytes[source]
                    rgba[destination + 3] = bytes[source + 3]

                default:
                    return nil
                }
            }
        }

        let dataProvider = CGDataProvider(
            data: Data(rgba) as CFData
        )!

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.last.rawValue
            ),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static func readUInt16(
        _ bytes: [UInt8],
        at offset: Int
    ) -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }

        return UInt16(bytes[offset]) |
               (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(
        _ bytes: [UInt8],
        at offset: Int
    ) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }

        return UInt32(bytes[offset]) |
               (UInt32(bytes[offset + 1]) << 8) |
               (UInt32(bytes[offset + 2]) << 16) |
               (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readInt32(
        _ bytes: [UInt8],
        at offset: Int
    ) -> Int32 {
        Int32(bitPattern: readUInt32(bytes, at: offset))
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
