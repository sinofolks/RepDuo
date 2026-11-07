import Foundation

final class DependencyContainer {
    let preferences: AppPreferences
    let persistence: WorkoutPersistenceStore
    let ghosts: GhostStore
    let cameraAuthorization: CameraAuthorizationService
    let cameraPipeline: CameraVisionPipeline
    let audioRoute: AudioRouteService
    let watchStatus: WatchStatusService
    let feedback: FeedbackService

    init() {
        let preferences = AppPreferences()
        self.preferences = preferences
        self.persistence = WorkoutPersistenceStore()
        self.ghosts = GhostStore()
        self.cameraAuthorization = CameraAuthorizationService()
        self.cameraPipeline = CameraVisionPipeline()
        self.audioRoute = AudioRouteService()
        self.watchStatus = WatchStatusService()
        self.feedback = FeedbackService(preferences: preferences)
    }
}

