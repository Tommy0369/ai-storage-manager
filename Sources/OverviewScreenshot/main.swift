import Foundation
import AIStorageManagerUI
import AppServices

@main
struct OverviewScreenshotTool {
    static func main() async {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let reportDir = cwd.appendingPathComponent("reports/case001")
        let outDir = reportDir.appendingPathComponent("screenshots")
        let p54Dir = outDir.appendingPathComponent("p54")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        do {
            try await OverviewScreenshotExport.exportExplorerScenarios(
                reportDirectory: reportDir,
                outputDirectory: outDir
            )
            try await OverviewScreenshotExport.exportP41ConsumerPolish(
                reportDirectory: reportDir,
                outputDirectory: outDir
            )
            try await OverviewScreenshotExport.exportP54LocalizationMatrix(
                reportDirectory: reportDir,
                outputRoot: p54Dir
            )
            fputs("wrote screenshots under \(outDir.path)\n", stderr)
            fputs("wrote P5.4 matrix under \(p54Dir.path)\n", stderr)
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }
}
