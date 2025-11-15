import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

enum FileAttachmentFilter {
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "js", "ts", "tsx", "jsx", "py", "java",
        "c", "cpp", "h", "hpp", "cs", "php", "rb", "go", "rs", "swift",
        "kt", "scala", "sh", "bash", "zsh", "fish", "html", "htm", "css",
        "scss", "sass", "less", "xml", "json", "yaml", "yml", "toml", "ini",
        "cfg", "conf", "log", "sql", "r", "m", "pl", "lua", "vim",
        "dockerfile", "makefile", "cmake", "gradle", "properties", "env",
    ]

    /// Mirrors pi-tui’s heuristic: allow obvious text/code & common image types; fall back to UTType when available.
    static func isAttachable(url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        if self.textExtensions.contains(pathExtension) { return true }

        #if canImport(UniformTypeIdentifiers)
        if let type = UTType(filenameExtension: pathExtension) {
            if type.conforms(to: .text) || type.conforms(to: .image) {
                return true
            }
        }
        #endif

        // Allow common image extensions even if UTType is unavailable
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
        return imageExtensions.contains(pathExtension)
    }
}
