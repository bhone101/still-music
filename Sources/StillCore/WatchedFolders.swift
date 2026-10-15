import Foundation

public struct WatchedFolders: Codable {
    public private(set) var paths: Set<String> = []
    public var ignoredTrackIDs: Set<String> = []
    public init() {}
    public var urls: [URL] { paths.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) } }
    public mutating func include(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            var directory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &directory)
            let folder = exists && directory.boolValue ? resolved : resolved.deletingLastPathComponent()
            paths.insert(folder.path)
        }
        // Avoid enumerating overlapping directory trees more than once.
        let all = paths
        paths = Set(all.filter { path in
            !all.contains { parent in parent != path && path.hasPrefix(parent == "/" ? parent : parent + "/") }
        })
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
    public static func load(from url: URL) throws -> WatchedFolders {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
