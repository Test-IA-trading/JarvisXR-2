import Foundation

/// Parts of Jarvis switched on or off for a phase of development, in one place, so that
/// bringing one back is a one-line change (with its tests and docs/DECISIONS.md).
enum JarvisFeatures {
    /// The camera (Vision, the AR cube, their welcome screen) is set aside while the
    /// intelligence, the memory and the conversation are rebuilt (docs/VISION_JARVIS.md §22).
    /// Its code and resources stay in the app and in Git; its screens still open in the CI's
    /// UI tests. Set to true to bring it back.
    static let cameraEnabled = false

    static let cameraPausedMessage = "La caméra est mise de côté pour le moment, Monsieur : je me consacre d'abord à la conversation et à la mémoire. Elle reviendra ensuite."
}
