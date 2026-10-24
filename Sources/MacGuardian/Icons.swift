import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacGuardianCore

private actor IconLoader {
    static let shared = IconLoader()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.countLimit = 256; cache.totalCostLimit = 16 * 1024 * 1024 }
    func image(path: String?, fileType: String?) -> NSImage? {
        let key = (fileType.map { "extension:" + $0 } ?? path) ?? ""
        guard !key.isEmpty else { return nil }
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let image: NSImage
        if let type = fileType { image = NSWorkspace.shared.icon(for: UTType(filenameExtension: type) ?? .data) }
        else if let path {
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            if let appPath = ApplicationService.bundlePath(forExecutable: path), let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
               let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
               let url = bundle.url(forResource: name, withExtension: nil) ?? bundle.url(forResource: name, withExtension: "icns"),
               let original = NSImage(contentsOf: url) {
                image = original
            } else { image = NSWorkspace.shared.icon(forFile: path) }
        }
        else { return nil }
        // Keep small raster thumbnails instead of retaining every multi-megabyte ICNS representation.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 96, height: 96))
        NSGraphicsContext.restoreGraphicsState()
        let thumbnail = NSImage(size: NSSize(width: 96, height: 96)); thumbnail.addRepresentation(rep); thumbnail.isTemplate = image.isTemplate
        cache.setObject(thumbnail, forKey: key as NSString, cost: 96 * 96 * 4); return thumbnail
    }
}
struct ApplicationIcon: View {
    var path: String?
    var fileType: String? = nil
    var fallback = "app.fill"
    var size: CGFloat = 30
    @ViewState private var icon: NSImage?
    var body: some View {
        Group { if let icon { Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit) } else { Image(systemName: fallback).resizable().scaledToFit().foregroundStyle(.secondary).padding(4) } }
            .frame(width: size, height: size)
            .task(id: (fileType ?? "") + "|" + (path ?? "")) { icon = nil; let loaded = await IconLoader.shared.image(path: path, fileType: fileType); if !Task.isCancelled { icon = loaded } }
            .accessibilityHidden(true)
    }
}
