import Foundation
import CryptoKit
import ZIPFoundation
import RayNeoArchive
import Darwin

enum PortableArchiveError: LocalizedError {
    case invalidSnapshot, changed, capacity
    var errorDescription: String? {
        switch self {
        case .invalidSnapshot: return "내보내기 사본 구조가 유효하지 않아 ZIP을 생성하지 않았습니다."
        case .changed: return "사본 또는 ZIP 검증 실패 · 원본은 유지하며 공유 파일을 만들지 않았습니다."
        case .capacity: return "내보내기 사본이 20개 한도에 도달했습니다. ZIP 사본 화면에서 정리하세요. 기존 파일은 자동 삭제하지 않습니다."
        }
    }
}

/// Runs on the repository actor. Uses a verified independent snapshot, never zips the live archive root.
enum PortableArchiveZIP {
    struct Expected { let path: String; let size: Int64; let hash: String }
    static func create(_ snapshot: ArchiveSnapshotReceipt) throws -> URL {
        guard snapshot.manifest.schemaVersion == 1, snapshot.manifest.files.count <= 101,
              snapshot.totalByteCount > 0, snapshot.totalByteCount <= 1_073_741_824 else { throw PortableArchiveError.invalidSnapshot }
        let base = snapshot.directoryURL
        let folder = "RayNeo-" + snapshot.snapshotID.uuidString.lowercased()
        let partial = base.deletingLastPathComponent().appendingPathComponent(folder + ".zip.partial")
        let output = base.deletingLastPathComponent().appendingPathComponent(folder + ".zip")
        guard !FileManager.default.fileExists(atPath:partial.path), !FileManager.default.fileExists(atPath:output.path) else { throw PortableArchiveError.invalidSnapshot }
        var expected = snapshot.manifest.files.map { Expected(path:$0.relativePath,size:$0.byteCount,hash:$0.sha256) }
        let metadataSize = try snapshot.manifestURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        expected.append(Expected(path:"snapshot-manifest.json",size:Int64(metadataSize),hash:snapshot.manifestSHA256))
        guard expected.allSatisfy({ validPath($0.path) && $0.size > 0 }), Set(expected.map(\.path)).count == expected.count else { throw PortableArchiveError.invalidSnapshot }
        // Unique private path is retained on failure for inspection, never offered to the share sheet.
        try write(partial,base:base,folder:folder,expected:expected)
        let verifiedEntries = expected + [Expected(path:"README.md",size:Int64(readme.count),hash:hex(SHA256.hash(data:readme)))]
        try verify(partial,folder:folder,expected:verifiedEntries)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at:partial,to:output) // Exclusive destination, no replacement.
        return output
    }
    static func validPath(_ path: String) -> Bool {
        let parts = path.split(separator:"/",omittingEmptySubsequences:false)
        return !path.isEmpty && path.utf8.count <= 512 && !path.contains("\\") && !path.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains)
            && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func write(_ url: URL, base: URL, folder: String, expected: [Expected]) throws {
        let zip = try ZIPFoundation.Archive(url:url,accessMode:.create)
        try FileManager.default.setAttributes([.posixPermissions:0o600,.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:url.path)
        for item in expected {
            try Task.checkCancellation()
            let source = base.appendingPathComponent(item.path)
            let fd = open(source.path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK)
            guard fd >= 0 else { throw PortableArchiveError.changed }
            let input = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
            defer { try? input.close() }
            var st = stat()
            guard fstat(fd,&st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_size == item.size else { throw PortableArchiveError.changed }
            var hash = SHA256(), consumed: Int64 = 0
            try zip.addEntry(with:folder + "/" + item.path,type:.file,uncompressedSize:item.size,permissions:0o600,
                             compressionMethod:.none,bufferSize:65_536) { position,size in
                try Task.checkCancellation()
                guard position == consumed, size <= 65_536, Int64(size) <= item.size - consumed else { throw PortableArchiveError.changed }
                let chunk = try input.read(upToCount:size) ?? Data()
                guard chunk.count == size else { throw PortableArchiveError.changed }
                hash.update(data:chunk); consumed += Int64(chunk.count)
                return chunk
            }
            guard consumed == item.size, hex(hash.finalize()) == item.hash else { throw PortableArchiveError.changed }
        }
        try zip.addEntry(with:folder + "/README.md",type:.file,uncompressedSize:Int64(readme.count),permissions:0o600) { position,size in
            try Task.checkCancellation(); return readme.subdata(in:Int(position)..<(Int(position)+size))
        }
    }
    private static let readme = Data("""
        # Turbo IO 휴대용 보관 파일

        압축 해제 후 RayNeo 폴더 전체를 Obsidian 보관함에 복사하고 notes/와 audio/를 같은 위치에 유지하세요.
        Markdown의 ../audio/ 링크에는 해당 오디오가 필요합니다. 메모만 복사하지 마세요.
        snapshot-manifest.json의 길이와 SHA-256으로 NAS에서 별도 검증할 수 있습니다.
        선택한 녹음과 수정본만 포함합니다. 다른 대화, API 키, 기기 등록 정보, 실시간 녹음 캐시는 포함하지 않습니다.
        패키지 검증은 오디오 재생, 무선 무손실, 텍스트 정확성, 서버 수신 또는 Obsidian 인덱싱을 보장하지 않습니다.
        네트워크, 자동 인식 또는 원본 삭제는 하지 않았습니다. 대상 기기에서 파일을 확인한 뒤 사본을 정리하세요.
        """.utf8)
    static func verify(_ url: URL, folder: String, expected: [Expected]) throws {
        let zip = try ZIPFoundation.Archive(url:url,accessMode:.read)
        let names = zip.map(\.path)
        let required = Set(expected.map { folder + "/" + $0.path })
        guard Set(names) == required, names.count == required.count else { throw PortableArchiveError.changed }
        for item in expected {
            try Task.checkCancellation()
            guard let entry = zip[folder + "/" + item.path], entry.type == .file, entry.uncompressedSize == item.size else { throw PortableArchiveError.changed }
            var count: Int64 = 0, hash = SHA256()
            let crc = try zip.extract(entry,bufferSize:65_536) { chunk in
                try Task.checkCancellation()
                guard count <= item.size - Int64(chunk.count) else { throw PortableArchiveError.changed }
                count += Int64(chunk.count); hash.update(data:chunk)
            }
            guard crc == entry.checksum, count == item.size, hex(hash.finalize()) == item.hash else { throw PortableArchiveError.changed }
        }
    }
    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format:"%02x",$0) }.joined() }
}
