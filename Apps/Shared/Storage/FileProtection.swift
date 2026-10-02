import Foundation
public enum ProtectedFile {
    public static func write(_ data: Data, to file: URL) throws {
        let fm = FileManager.default
        let directory = file.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var noBackup = URLResourceValues(); noBackup.isExcludedFromBackup = true
        var protectedDirectory = directory; try protectedDirectory.setResourceValues(noBackup)
        var protectedFile = file; try protectedFile.setResourceValues(noBackup)
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }
}
