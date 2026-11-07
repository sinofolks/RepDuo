import Foundation
import os
#if canImport(RepDuoCore)
import RepDuoCore
#endif

/// Keeps one ghost per exercise, the best set so far, as a small JSON file.
/// Ghosts hold sampled joint positions, so they live apart from the history store.
final class GhostStore {
    private let logger = Logger(subsystem: "com.repduo.ios", category: "ghost")
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ghosts", isDirectory: true)
    }

    func ghost(for exercise: ExerciseType) -> GhostTrack? {
        guard let data = try? Data(contentsOf: url(for: exercise)) else { return nil }
        do {
            return try decoder.decode(GhostTrack.self, from: data)
        } catch {
            logger.error("Ghost for \(exercise.rawValue, privacy: .public) could not be read: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Stores `track` when it beats the current ghost. Returns true when it was kept.
    @discardableResult
    func keepIfBest(_ track: GhostTrack) -> Bool {
        guard track.beats(ghost(for: track.exercise)) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(track).write(to: url(for: track.exercise), options: [.atomic, .completeFileProtection])
            return true
        } catch {
            logger.error("Ghost save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(for exercise: ExerciseType) -> URL {
        directory.appendingPathComponent("\(exercise.rawValue).json")
    }
}
