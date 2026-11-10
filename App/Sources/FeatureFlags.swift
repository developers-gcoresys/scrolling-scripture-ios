import Foundation

enum AppFeatureFlags {
    /// Keep false until the scripture content rights, source edition, and model
    /// output have been reviewed. The backend also keeps each app's
    /// explanations disabled until `SCRIPTURE_EXPLAIN_<APP>=true`.
    static let explanationsEnabled = false
}
