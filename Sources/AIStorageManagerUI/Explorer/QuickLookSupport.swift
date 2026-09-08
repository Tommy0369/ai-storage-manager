import AppKit
import Quartz
import SwiftUI
import AppServices
import SafetyCore

enum QuickLookSupport {
    enum Outcome: Equatable {
        case previewable
        case unsupported
        case missing
        case restricted
    }

    static func classify(path: String) -> Outcome {
        if HardSafetyGates.isHardBlocked(path: path) { return .restricted }
        let expanded = PathGlob.expandHome(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) else {
            return .missing
        }
        if isDir.boolValue { return .unsupported }
        let ext = (expanded as NSString).pathExtension.lowercased()
        let supported: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "pdf",
            "txt", "md", "json", "swift", "csv", "mp4", "mov", "m4v", "mp3",
        ]
        return supported.contains(ext) ? .previewable : .unsupported
    }

    static func revealInFinder(path: String) {
        let expanded = PathGlob.expandHome(path)
        let url = URL(fileURLWithPath: expanded)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private var url: URL?

    func present(path: String) -> QuickLookSupport.Outcome {
        let outcome = QuickLookSupport.classify(path: path)
        guard outcome == .previewable else { return outcome }
        url = URL(fileURLWithPath: PathGlob.expandHome(path))
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
        }
        return outcome
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        (url ?? URL(fileURLWithPath: "/dev/null")) as QLPreviewItem
    }
}
