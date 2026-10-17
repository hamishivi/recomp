import Foundation
import PDFKit
import CryptoKit

struct DXAImportedReport: Sendable {
    var data: Data
    var filename: String
    var sha256: String
    var text: String
    var textTruncated: Bool
}

enum DXAImportError: LocalizedError {
    case size, invalidPDF, locked, pages
    var errorDescription: String? {
        switch self {
        case .size: return "Choose a PDF no larger than 12 MB, or enter the results manually."
        case .invalidPDF: return "This file could not be opened as a PDF. Your existing draft has not changed."
        case .locked: return "This PDF is password-protected. Unlock a copy on your device first, or enter the report values manually."
        case .pages: return "Choose a report with 1–30 pages, or enter its values manually."
        }
    }
}

/// Called off the main actor. File access and PDF text extraction are local only.
/// No OCR, external API, automatic URL fetch, or server upload is used.
enum DXAReportReader {
    static func read(_ url: URL) throws -> DXAImportedReport {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var result: Result<DXAImportedReport, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { localURL in
            result = Result {
                let handle = try FileHandle(forReadingFrom: localURL)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: DXAScan.maxPDFBytes + 1) ?? Data()
                guard data.count <= DXAScan.maxPDFBytes else { throw DXAImportError.size }
                guard data.starts(with: Data("%PDF-".utf8)), let document = PDFDocument(data: data) else { throw DXAImportError.invalidPDF }
                guard !document.isLocked else { throw DXAImportError.locked }
                guard (1...30).contains(document.pageCount) else { throw DXAImportError.pages }
                var text = ""
                var truncated = false
                for i in 0..<document.pageCount {
                    let page = document.page(at: i)?.string ?? ""
                    let available = DXATextParser.maxCharacters - text.count
                    if page.count + 1 > available { truncated = true; break }
                    text += page + "\n"
                }
                return DXAImportedReport(data: data, filename: String(url.lastPathComponent.prefix(250)),
                    sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                    text: text, textTruncated: truncated)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw DXAImportError.invalidPDF }
        return try result.get()
    }
}
