import AVFoundation
import UIKit

actor PreviewThumbnailService {
    static let shared = PreviewThumbnailService()

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("channel-previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func cachedImage(for streamURL: String) -> UIImage? {
        let path = cacheURL.appendingPathComponent(cacheKey(streamURL) + ".jpg")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }

    func generate(for streamURL: String, timeout: TimeInterval = 8) async -> UIImage? {
        if let cached = cachedImage(for: streamURL) { return cached }
        guard let url = URL(string: streamURL) else { return nil }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)

        do {
            let cg = try await withThrowingTaskGroup(of: CGImage.self) { group in
                group.addTask {
                    let time = CMTime(seconds: 1, preferredTimescale: 600)
                    return try await generator.image(at: time).image
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let image = UIImage(cgImage: cg)
            if let data = image.jpegData(compressionQuality: 0.7) {
                try? data.write(to: cacheURL.appendingPathComponent(cacheKey(streamURL) + ".jpg"))
            }
            return image
        } catch {
            return nil
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    }

    private func cacheKey(_ url: String) -> String {
        String(url.hashValue)
    }
}
