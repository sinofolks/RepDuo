import CoreData
import Foundation
import os
#if canImport(RepDuoCore)
import RepDuoCore
#endif

@objc(WorkoutRecordMO)
final class WorkoutRecordMO: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var exerciseType: String
    @NSManaged var startedAt: Date
    @NSManaged var endedAt: Date
    @NSManaged var repCount: Int32
    @NSManaged var activeDuration: Double
    @NSManaged var averageHeartRate: NSNumber?
    @NSManaged var maximumHeartRate: NSNumber?
    @NSManaged var lowConfidenceEventCount: Int32
    @NSManaged var algorithmVersion: String
}

final class WorkoutPersistenceStore {
    private let logger = Logger(subsystem: "com.repduo.ios", category: "persistence")
    private let container: NSPersistentContainer

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "RepDuo", managedObjectModel: model)
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            let description = NSPersistentStoreDescription(url: storeURL ?? Self.defaultStoreURL())
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
        }

        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { [weak self] _, error in
            if let error {
                self?.logger.error("Persistent store failed to load: \(error.localizedDescription, privacy: .private(mask: .hash))")
            }
            semaphore.signal()
        }
        semaphore.wait()
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func save(_ summary: WorkoutSummary) throws {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        var capturedError: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<WorkoutRecordMO>(entityName: "WorkoutRecord")
                request.predicate = NSPredicate(format: "id == %@", summary.id as CVarArg)
                request.fetchLimit = 1
                let record: WorkoutRecordMO
                if let existing = try context.fetch(request).first {
                    record = existing
                } else {
                    guard let entity = NSEntityDescription.entity(forEntityName: "WorkoutRecord", in: context) else {
                        throw CocoaError(.persistentStoreInvalidType)
                    }
                    record = WorkoutRecordMO(entity: entity, insertInto: context)
                }
                record.id = summary.id
                record.exerciseType = summary.exercise.rawValue
                record.startedAt = summary.startedAt
                record.endedAt = summary.endedAt
                record.repCount = Int32(summary.repCount)
                record.activeDuration = summary.activeDuration
                record.averageHeartRate = summary.averageHeartRate.map(NSNumber.init(value:))
                record.maximumHeartRate = summary.maximumHeartRate.map(NSNumber.init(value:))
                record.lowConfidenceEventCount = Int32(summary.lowConfidenceEventCount)
                record.algorithmVersion = summary.algorithmVersion
                try context.save()
            } catch {
                capturedError = error
            }
        }
        if let capturedError { throw capturedError }
    }

    func fetchAll() throws -> [WorkoutSummary] {
        let request = NSFetchRequest<WorkoutRecordMO>(entityName: "WorkoutRecord")
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(WorkoutRecordMO.startedAt), ascending: false)]
        return try container.viewContext.fetch(request).compactMap(Self.summary(from:))
    }

    func deleteAll() throws {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        var capturedError: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "WorkoutRecord")
                try context.fetch(request).forEach(context.delete)
                try context.save()
            } catch {
                capturedError = error
            }
        }
        if let capturedError { throw capturedError }
    }

    private static func summary(from record: WorkoutRecordMO) -> WorkoutSummary? {
        guard let exercise = ExerciseType(rawValue: record.exerciseType) else { return nil }
        return WorkoutSummary(
            id: record.id,
            exercise: exercise,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            repCount: Int(record.repCount),
            activeDuration: record.activeDuration,
            averageHeartRate: record.averageHeartRate?.doubleValue,
            maximumHeartRate: record.maximumHeartRate?.doubleValue,
            lowConfidenceEventCount: Int(record.lowConfidenceEventCount),
            algorithmVersion: record.algorithmVersion
        )
    }

    private static func defaultStoreURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("RepDuo", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("RepDuo.sqlite")
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["RepDuoModelV1"]
        let entity = NSEntityDescription()
        entity.name = "WorkoutRecord"
        entity.managedObjectClassName = NSStringFromClass(WorkoutRecordMO.self)

        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = optional
            return attribute
        }

        entity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("exerciseType", .stringAttributeType),
            attribute("startedAt", .dateAttributeType),
            attribute("endedAt", .dateAttributeType),
            attribute("repCount", .integer32AttributeType),
            attribute("activeDuration", .doubleAttributeType),
            attribute("averageHeartRate", .doubleAttributeType, optional: true),
            attribute("maximumHeartRate", .doubleAttributeType, optional: true),
            attribute("lowConfidenceEventCount", .integer32AttributeType),
            attribute("algorithmVersion", .stringAttributeType)
        ]
        entity.uniquenessConstraints = [["id"]]
        model.entities = [entity]
        return model
    }
}
