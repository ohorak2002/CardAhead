import SwiftUI
import UIKit
import os
import CardKit

/// Turns a `PlacePhoto` handle into pixels, as few times as possible.
///
/// **The caching here is not an optimisation, it is the feature.** Every image
/// fetched is a separately billed request against the Places key — twenty rows
/// of map results is twenty of them — and without a cache, scrolling a list
/// down and back up again would buy the same forty photographs twice. So there
/// are three layers, and a photograph should only ever be paid for by the
/// first person to look at it:
///
/// 1. **Memory.** An `NSCache`, so iOS empties it under pressure rather than
///    the app being killed for holding images nobody is looking at.
/// 2. **Disk.** Thirty days, which is the limit the provider's terms allow for
///    caching this content and also about how often a shop changes its
///    photograph. Survives a relaunch, which memory does not.
/// 3. **Coalescing.** Ten rows of the same chain, or a row and the detail
///    screen it opens, ask at the same instant; one request is made and every
///    caller waits on it. Without this the *first* screenful is the expensive
///    one, every time.
///
/// **Not an actor, deliberately.** The state that needs protecting is an
/// `NSCache`, which is already thread-safe, and a small dictionary of
/// in-flight tasks behind a lock. An actor would additionally require every
/// `UIImage` to cross an isolation boundary, which in Swift 5.9 means
/// fighting `Sendable` for no benefit.
final class PlacePhotoLoader: @unchecked Sendable {

    /// What the app installs when there is no Places key, and what previews
    /// and the seeded screenshot run get: a loader that never returns an
    /// image, so every screen draws its fallback. **That is the path CI
    /// photographs**, which is the argument for the fallback being designed
    /// rather than apologetic.
    static let unavailable = PlacePhotoLoader(source: EmptyPlaceSearchSource())

    private let source: PlaceSearchSource
    private let transport: HTTPTransport
    private let log = Logger(subsystem: AppLog.subsystem, category: "photos")

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Roughly forty hero-sized images, in bytes rather than a count: one
        // hero is worth thirty thumbnails and a count limit cannot tell.
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var hasPruned = false

    private let directory: URL?

    init(
        source: PlaceSearchSource,
        transport: HTTPTransport = URLSessionTransport(),
        directory: URL? = PlacePhotoLoader.defaultDirectory()
    ) {
        self.source = source
        self.transport = transport
        self.directory = directory
    }

    /// Whether this loader could ever produce an image. Screens use it to
    /// decide between "waiting for a photo" and "there are no photos here",
    /// which look identical and are not.
    var canLoadPhotos: Bool {
        !(source is EmptyPlaceSearchSource)
    }

    // MARK: - The one entry point

    /// The image for this photo at this size, or nil.
    ///
    /// **Nil is ordinary and always means the same thing to a caller: draw the
    /// fallback.** No key, no photo, no network, a 403 because billing lapsed,
    /// bytes that are not an image — every one of them ends here, because the
    /// difference matters to the log and not to the person holding the phone.
    func image(for photo: PlacePhoto, use: PlacePhotoUse) async -> UIImage? {
        let key = photo.cacheKey(for: use)

        if let cached = memory.object(forKey: key as NSString) { return cached }

        // **The whole check-and-insert is inside one lock.** Two rows asking
        // a microsecond apart must not each find "no task in flight" and then
        // each start one; that is the exact race this class exists to avoid,
        // and it costs real money rather than a wasted cycle.
        let task: Task<UIImage?, Never> = {
            lock.lock()
            defer { lock.unlock() }
            if let existing = inFlight[key] { return existing }
            let created = Task<UIImage?, Never> { [weak self] in
                guard let self else { return nil }
                let image = await self.fetch(photo, use: use, key: key)
                self.lock.lock()
                self.inFlight[key] = nil
                self.lock.unlock()
                return image
            }
            inFlight[key] = created
            return created
        }()

        return await task.value
    }

    // MARK: - Getting the bytes

    private func fetch(_ photo: PlacePhoto, use: PlacePhotoUse, key: String) async -> UIImage? {
        pruneOnce()

        if let onDisk = readFromDisk(key: key), let image = UIImage(data: onDisk) {
            remember(image, forKey: key)
            return image
        }

        guard let request = source.photoRequest(for: photo, use: use) else { return nil }

        do {
            let response = try await transport.send(request)
            guard response.isSuccess else {
                // Worth a line in the log and nothing on screen. A 403 here is
                // almost always the Places key having lost Photos permission
                // or hit its budget cap, and that is invisible otherwise.
                log.notice("place photo refused: status \(response.statusCode, privacy: .public)")
                return nil
            }
            guard let image = UIImage(data: response.body) else {
                log.notice("place photo was not an image")
                return nil
            }
            writeToDisk(response.body, key: key)
            remember(image, forKey: key)
            return image
        } catch {
            // Offline, cancelled, timed out. All ordinary.
            return nil
        }
    }

    private func remember(_ image: UIImage, forKey key: String) {
        // Cost in bytes rather than the default 0, or the limit means nothing.
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    // MARK: - Disk

    private func fileURL(forKey key: String) -> URL? {
        directory?.appendingPathComponent(key)
    }

    private func readFromDisk(key: String) -> Data? {
        guard let url = fileURL(forKey: key),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date
        else { return nil }

        guard Date().timeIntervalSince(modified) < PlacePhotoUse.cacheLifetime else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func writeToDisk(_ data: Data, key: String) {
        guard let directory, let url = fileURL(forKey: key) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Clears out what has expired, once per launch, off the main thread.
    ///
    /// **Age only, not size.** The directory is under `Caches`, which iOS
    /// empties itself when the disk is under pressure — adding a second,
    /// stricter policy on top would mostly mean throwing away images that are
    /// about to be paid for again.
    private func pruneOnce() {
        lock.lock()
        let shouldPrune = !hasPruned
        hasPruned = true
        lock.unlock()
        guard shouldPrune, let directory else { return }

        let cutoff = Date().addingTimeInterval(-PlacePhotoUse.cacheLifetime)
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? manager.removeItem(at: entry)
            }
        }
    }

    /// `Caches`, not `Application Support`: these are bytes that can always be
    /// bought again, and marking them as such is what lets iOS reclaim the
    /// space instead of killing the app for using it.
    private static func defaultDirectory() -> URL? {
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return caches.appendingPathComponent("place-photos", isDirectory: true)
    }
}

// MARK: - Reaching it from a view

private struct PlacePhotoLoaderKey: EnvironmentKey {
    /// A loader that produces nothing, so a view that somehow never got a real
    /// one draws fallbacks rather than crashing or showing a spinner forever.
    static let defaultValue = PlacePhotoLoader.unavailable
}

extension EnvironmentValues {
    /// **An environment value rather than an `@Observable` in `.environment`,
    /// because nothing here is observable.** The loader has no published state
    /// — a view asks it for an image and awaits the answer. Making it
    /// observable would invite views to redraw on a cache write.
    var placePhotos: PlacePhotoLoader {
        get { self[PlacePhotoLoaderKey.self] }
        set { self[PlacePhotoLoaderKey.self] = newValue }
    }
}
