import Foundation

/// Predefined smart exclusion templates tailored for creative and developer workflows.
public enum ExclusionPreset: String, CaseIterable, Identifiable, Sendable {
    case softwareDeveloper = "developer"
    case videoEditor = "video"
    case audioProducer = "audio"
    case systemCaches = "caches"

    public var id: String { rawValue }

    /// Localized display title.
    public var localizedTitle: String {
        let isHu = LocalizationManager.shared.effectiveLanguage == .hungarian
        switch self {
        case .softwareDeveloper:
            return isHu ? "Szoftverfejlesztő (Kód, Könyvtárak, Build)" : "Software Developer (Code, Deps, Build)"
        case .videoEditor:
            return isHu ? "Videóvágó (Render fájlok, Gyorsítótár)" : "Video Editor (Renders, Scratch, Caches)"
        case .audioProducer:
            return isHu ? "Zenei Producer (Fagyasztott sávok, Undo)" : "Audio Producer (Freeze Files, Undo)"
        case .systemCaches:
            return isHu ? "Rendszer Gyorsítótárak (.DS_Store, Temp)" : "System Caches (.DS_Store, Temp)"
        }
    }

    /// SF Symbol icon name.
    public var iconName: String {
        switch self {
        case .softwareDeveloper: return "hammer.fill"
        case .videoEditor: return "film.fill"
        case .audioProducer: return "waveform"
        case .systemCaches: return "trash"
        }
    }

    /// List of file/folder pattern rules associated with this preset.
    public var patterns: [String] {
        switch self {
        case .softwareDeveloper:
            return [
                "node_modules/", ".build/", "target/", "DerivedData/",
                ".venv/", "venv/", "vendor/", ".gradle/", "Pods/"
            ]
        case .videoEditor:
            return [
                "Render Files/", "Scratch/", "Adobe Premiere Pro Auto-Save/",
                "Final Cut Pro Backups/", ".fcpbundle/**/Analysis Files/"
            ]
        case .audioProducer:
            return [
                "Freeze Files/", "Undo/", "Audio Record Files/Temporary/",
                "Ableton Project Info/"
            ]
        case .systemCaches:
            return [
                ".DS_Store", "Thumbs.db", ".Spotlight-V100", ".Trashes",
                "Cache/", "Caches/", "*.tmp"
            ]
        }
    }
}
