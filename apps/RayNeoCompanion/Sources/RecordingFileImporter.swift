import Foundation

enum RecordingImportError: LocalizedError {
    case alreadyImporting, notRegularFile, emptyFile, tooLarge, sourceChanged
    var errorDescription: String? {
        switch self {
        case .alreadyImporting: return "다른 오디오를 가져오는 중입니다. 잠시 기다리세요."
        case .notRegularFile: return "일반 오디오 파일만 가져올 수 있습니다. 폴더나 심볼릭 링크는 지원하지 않습니다."
        case .emptyFile: return "선택한 파일이 비어 있습니다."
        case .tooLarge: return "파일 하나는 최대 512 MB까지 지원합니다. 큰 녹음은 나누세요."
        case .sourceChanged: return "가져오는 중 원본 파일이 변경되어 취소했습니다."
        }
    }
}

enum RecordingFileImporter {
    static let maximumBytes = 512 * 1024 * 1024

    /// Called off the main actor while the caller keeps security-scoped access alive.
    /// Only this invocation's UUID paths may be removed on failure; the source is never altered.
    static func copy(source: URL, to directory: URL, maximumBytes: Int = maximumBytes) throws -> LocalRecording {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let before = try source.resourceValues(forKeys: keys)
        guard before.isRegularFile == true, before.isSymbolicLink != true else { throw RecordingImportError.notRegularFile }
        let count = before.fileSize ?? 0
        guard count > 0 else { throw RecordingImportError.emptyFile }
        guard count <= maximumBytes else { throw RecordingImportError.tooLarge }
        let ext = source.pathExtension.lowercased()
        let filename = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        let staging = directory.appendingPathComponent(filename + ".partial")
        let target = directory.appendingPathComponent(filename)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var ownsStaging = false
        do {
            // UUID paths are checked before copying, never used to overwrite an existing file.
            guard !manager.fileExists(atPath: staging.path), !manager.fileExists(atPath: target.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try Data().write(to: staging, options: .withoutOverwriting)
            ownsStaging = true
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: staging)
            defer { try? output.close() }
            var total = 0
            while let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty {
                try Task.checkCancellation()
                guard total <= maximumBytes - chunk.count else { throw RecordingImportError.tooLarge }
                total += chunk.count
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
            var refreshedSource = source
            refreshedSource.removeAllCachedResourceValues()
            let after = try refreshedSource.resourceValues(forKeys: keys)
            let copied = try staging.resourceValues(forKeys: [.fileSizeKey])
            guard after.fileSize == before.fileSize, after.contentModificationDate == before.contentModificationDate,
                  copied.fileSize == before.fileSize, total == count else { throw RecordingImportError.sourceChanged }
            try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: staging.path)
            try manager.moveItem(at: staging, to: target)
            ownsStaging = false
            let recording = LocalRecording(name: source.deletingPathExtension().lastPathComponent, storedFilename: filename, byteCount: Int64(count))
            return recording
        } catch {
            if ownsStaging { try? manager.removeItem(at: staging) }
            throw error
        }
    }
}
