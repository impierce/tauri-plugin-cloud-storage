import Foundation

public let cloudStorageMaximumFileSize = 10 * 1024 * 1024

public struct ICloudConfiguration: Decodable, Equatable {
  public let containerIdentifier: String?

  public init(containerIdentifier: String? = nil) {
    self.containerIdentifier = containerIdentifier
  }
}

public struct NativeStorageStatus: Encodable, Equatable {
  public let provider = "iCloud"
  public let state: String
}

public struct NativeCloudFile: Codable, Equatable {
  public let id: String
  public let name: String
  public let size: Int64
  public let modifiedAt: String
}

public struct NativeFilePage: Encodable, Equatable {
  public let files: [NativeCloudFile]
  public let nextCursor: String?
}

public struct NativeListFilesOptions: Decodable {
  public let pageSize: Int?
  public let cursor: String?
}

public struct NativeCreateFileOptions: Decodable {
  public let name: String
  public let data: [UInt8]
}

public struct NativeUpdateFileOptions: Decodable {
  public let id: String
  public let data: [UInt8]
}

public struct NativeFileIdOptions: Decodable {
  public let id: String
}

public struct NativeWaitForUploadOptions: Decodable {
  public let id: String
  public let timeoutMs: UInt32?
}

public struct CloudStorageFailure: Swift.Error, Equatable {
  public let code: String
  public let message: String

  public init(_ code: String, _ message: String) {
    self.code = code
    self.message = message
  }
}

/// Native validation mirrors the Rust contract because native commands can be
/// reached without a JavaScript caller passing through the shared Rust API.
public enum ICloudValidation {
  public static func file(name: String, data: [UInt8]) throws {
    guard isValidName(name) else {
      throw CloudStorageFailure(
        "invalidArgument",
        "name must be a nonblank filename of at most 255 UTF-8 bytes, without path separators or control characters"
      )
    }
    try payload(data)
  }

  public static func payload(_ data: [UInt8]) throws {
    guard data.count <= cloudStorageMaximumFileSize else {
      throw CloudStorageFailure("invalidArgument", "data must not exceed \(cloudStorageMaximumFileSize) bytes")
    }
  }

  public static func fileId(_ id: String) throws {
    guard UUID(uuidString: id) != nil else {
      throw CloudStorageFailure("invalidArgument", "id must be a cloud file identifier")
    }
  }

  public static func pageSize(_ pageSize: Int) throws {
    guard (1...1000).contains(pageSize) else {
      throw CloudStorageFailure("invalidArgument", "pageSize must be between 1 and 1000")
    }
  }

  public static func timeout(_ timeoutMilliseconds: UInt32) throws {
    guard (1_000...300_000).contains(timeoutMilliseconds) else {
      throw CloudStorageFailure("invalidArgument", "timeoutMs must be between 1000 and 300000")
    }
  }

  private static func isValidName(_ name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && name.utf8.count <= 255
      && name != "."
      && name != ".."
      && !name.contains("/")
      && !name.contains("\\")
      && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
  }
}

private struct EntryMetadata: Codable, Equatable {
  let version: Int
  let id: String
  let name: String
}

private struct PageCursor: Codable, Equatable {
  let version: Int
  let connectionId: String
  let lastId: String
}

private struct EntryURLs {
  let directory: URL
  let metadata: URL
  let payload: URL
}

/// iCloud Documents provider implementation. Its caller must serialize calls;
/// `CloudStoragePlugin` does this on a dedicated serial queue.
public final class ICloudProvider {
  private static let formatVersion = 1
  private static let pluginDirectory = "tauri-plugin-cloud-storage"
  private static let entriesDirectory = "files"
  private static let metadataFilename = "metadata.json"
  private static let payloadFilename = "payload.bin"
  private static let uploadTimeoutMilliseconds: UInt32 = 60_000

  private let configuration: ICloudConfiguration
  private let fileManager: FileManager
  private var root: URL?
  private var activeIdentityToken: NSObject?
  private var connectionId: UUID?
  private var identityObserver: NSObjectProtocol?
  private let identityChangeLock = NSLock()
  private var identityChanged = false

  public init(configuration: ICloudConfiguration, fileManager: FileManager = .default) {
    self.configuration = configuration
    self.fileManager = fileManager
    self.identityObserver = NotificationCenter.default.addObserver(
      forName: NSNotification.Name.NSUbiquityIdentityDidChange,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.markIdentityChanged()
    }
  }

  deinit {
    if let identityObserver {
      NotificationCenter.default.removeObserver(identityObserver)
    }
  }

  public func getStatus() -> NativeStorageStatus {
    guard availability() != nil else {
      return NativeStorageStatus(state: "unavailable")
    }
    guard isConnected else {
      return NativeStorageStatus(state: "disconnected")
    }
    return NativeStorageStatus(state: "connected")
  }

  public func connect() throws -> NativeStorageStatus {
    let (container, identityToken) = try requireAvailability()
    let root = container
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent(Self.pluginDirectory, isDirectory: true)
      .appendingPathComponent("v\(Self.formatVersion)", isDirectory: true)
      .appendingPathComponent(Self.entriesDirectory, isDirectory: true)

    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try assertSafeDirectory(root, mustExist: true)
    self.root = root.standardizedFileURL
    self.activeIdentityToken = identityToken
    self.connectionId = UUID()
    try removeAbandonedTemporaryEntries()
    return NativeStorageStatus(state: "connected")
  }

  public func disconnect() {
    clearConnection()
  }

  public func listFiles(_ options: NativeListFilesOptions?) throws -> NativeFilePage {
    let root = try requireConnection()
    let pageSize = options?.pageSize ?? 100
    try ICloudValidation.pageSize(pageSize)

    let cursor = try decodeCursor(options?.cursor)
    let metadataURLs = try metadataURLs(in: root)
    let entries = try metadataURLs.compactMap { metadataURL -> NativeCloudFile? in
      guard isContained(metadataURL, in: root) else { return nil }
      let entryURL = metadataURL.deletingLastPathComponent()
      guard entryURL.deletingLastPathComponent().standardizedFileURL == root else { return nil }
      try assertSafeDirectory(entryURL, mustExist: true)
      let metadata = try readMetadata(at: metadataURL, expectedDirectory: entryURL)
      let urls = try urls(for: metadata.id, in: root)
      return try cloudFile(from: metadata, urls: urls)
    }.sorted { $0.id < $1.id }

    let afterCursor: [NativeCloudFile]
    if let cursor {
      afterCursor = entries.filter { $0.id > cursor.lastId }
    } else {
      afterCursor = entries
    }
    let page = Array(afterCursor.prefix(pageSize))
    let nextCursor = afterCursor.count > page.count ? try encodeCursor(lastId: page.last!.id) : nil
    return NativeFilePage(files: page, nextCursor: nextCursor)
  }

  public func createFile(_ options: NativeCreateFileOptions) throws -> NativeCloudFile {
    let root = try requireConnection()
    try ICloudValidation.file(name: options.name, data: options.data)
    let id = UUID()
    let urls = try urls(for: id.uuidString, in: root)
    guard !fileManager.fileExists(atPath: urls.directory.path) else {
      throw CloudStorageFailure("conflict", "The generated file identifier already exists")
    }

    let metadata = EntryMetadata(version: Self.formatVersion, id: id.uuidString, name: options.name)
    let temporary = try temporaryURLs(for: id, in: root)
    do {
      try writeEntry(metadata: metadata, data: Data(options.data), to: temporary)
      try coordinateWrite(root, options: []) { coordinatedRoot in
        let destination = try self.urls(for: id.uuidString, in: coordinatedRoot)
        guard !self.fileManager.fileExists(atPath: destination.directory.path) else {
          throw CloudStorageFailure("conflict", "The generated file identifier already exists")
        }
        try self.fileManager.moveItem(at: temporary.directory, to: destination.directory)
      }
      return try cloudFile(from: metadata, urls: urls)
    } catch {
      try? fileManager.removeItem(at: temporary.directory)
      throw map(error)
    }
  }

  public func readFile(_ options: NativeFileIdOptions) throws -> [UInt8] {
    let root = try requireConnection()
    let urls = try urls(for: options.id, in: root)
    try assertExistingEntry(urls)
    _ = try readMetadata(at: urls.metadata, expectedDirectory: urls.directory)
    try ensureDownloaded(urls.payload, timeoutMilliseconds: Self.uploadTimeoutMilliseconds)
    let data = try coordinateRead(urls.payload) { try Data(contentsOf: $0) }
    guard data.count <= cloudStorageMaximumFileSize else {
      throw CloudStorageFailure("provider", "The stored file exceeds the 10 MiB plugin limit")
    }
    return Array(data)
  }

  public func updateFile(_ options: NativeUpdateFileOptions) throws -> NativeCloudFile {
    let root = try requireConnection()
    try ICloudValidation.fileId(options.id)
    try ICloudValidation.payload(options.data)
    let current = try urls(for: options.id, in: root)
    try assertExistingEntry(current)
    let metadata = try readMetadata(at: current.metadata, expectedDirectory: current.directory)
    let temporary = try temporaryURLs(for: UUID(), in: root)
    do {
      try writeEntry(metadata: metadata, data: Data(options.data), to: temporary)
      try coordinateWrite(current.directory, options: .forReplacing) { coordinatedCurrent in
        guard self.fileManager.fileExists(atPath: coordinatedCurrent.path) else {
          throw CloudStorageFailure("notFound", "The requested file no longer exists")
        }
        _ = try self.fileManager.replaceItemAt(
          coordinatedCurrent,
          withItemAt: temporary.directory,
          backupItemName: nil,
          options: []
        )
      }
      return try cloudFile(from: metadata, urls: current)
    } catch {
      try? fileManager.removeItem(at: temporary.directory)
      throw map(error)
    }
  }

  public func deleteFile(_ options: NativeFileIdOptions) throws {
    let root = try requireConnection()
    let urls = try urls(for: options.id, in: root)
    try assertExistingEntry(urls)
    try coordinateWrite(urls.directory, options: .forDeleting) { coordinatedDirectory in
      guard self.fileManager.fileExists(atPath: coordinatedDirectory.path) else {
        throw CloudStorageFailure("notFound", "The requested file no longer exists")
      }
      try self.fileManager.removeItem(at: coordinatedDirectory)
    }
  }

  public func waitForUpload(_ options: NativeWaitForUploadOptions) throws {
    let root = try requireConnection()
    try ICloudValidation.fileId(options.id)
    let urls = try urls(for: options.id, in: root)
    try assertExistingEntry(urls)
    let timeout = options.timeoutMs ?? Self.uploadTimeoutMilliseconds
    try ICloudValidation.timeout(timeout)
    try waitForMetadataUpload(of: urls.payload, timeoutMilliseconds: timeout)
  }

  private var isConnected: Bool {
    if consumeIdentityChange() {
      clearConnection()
      return false
    }
    guard let identityToken = currentIdentityToken(),
      let activeIdentityToken,
      let root,
      connectionId != nil,
      activeIdentityToken.isEqual(identityToken),
      fileManager.fileExists(atPath: root.path)
    else {
      clearConnection()
      return false
    }
    return true
  }

  private func availability() -> (URL, NSObject)? {
    guard let identityToken = currentIdentityToken(),
      let container = fileManager.url(forUbiquityContainerIdentifier: configuration.containerIdentifier)
    else {
      return nil
    }
    return (container, identityToken)
  }

  private func requireAvailability() throws -> (URL, NSObject) {
    guard let available = availability() else {
      throw CloudStorageFailure(
        "unavailable",
        "iCloud is unavailable. Check the device account and this app's iCloud container entitlement."
      )
    }
    return available
  }

  private func requireConnection() throws -> URL {
    guard isConnected, let root else {
      throw CloudStorageFailure("notConnected", "Call connect before accessing cloud files")
    }
    return root
  }

  private func currentIdentityToken() -> NSObject? {
    fileManager.ubiquityIdentityToken as? NSObject
  }

  private func clearConnection() {
    root = nil
    activeIdentityToken = nil
    connectionId = nil
  }

  private func markIdentityChanged() {
    identityChangeLock.lock()
    identityChanged = true
    identityChangeLock.unlock()
  }

  private func consumeIdentityChange() -> Bool {
    identityChangeLock.lock()
    defer { identityChangeLock.unlock() }
    let changed = identityChanged
    identityChanged = false
    return changed
  }

  private func urls(for id: String, in root: URL) throws -> EntryURLs {
    guard let uuid = UUID(uuidString: id) else {
      throw CloudStorageFailure("invalidArgument", "id must be a cloud file identifier")
    }
    let directory = root.appendingPathComponent(uuid.uuidString, isDirectory: true).standardizedFileURL
    guard isContained(directory, in: root) else {
      throw CloudStorageFailure("invalidArgument", "id resolves outside the cloud storage namespace")
    }
    return EntryURLs(
      directory: directory,
      metadata: directory.appendingPathComponent(Self.metadataFilename),
      payload: directory.appendingPathComponent(Self.payloadFilename)
    )
  }

  private func temporaryURLs(for id: UUID, in root: URL) throws -> EntryURLs {
    let temporaryRoot = root.appendingPathComponent(".temporary", isDirectory: true)
    try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    let directory = temporaryRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    guard isContained(directory, in: root) else {
      throw CloudStorageFailure("internal", "Temporary storage resolved outside the plugin namespace")
    }
    return EntryURLs(
      directory: directory,
      metadata: directory.appendingPathComponent(Self.metadataFilename),
      payload: directory.appendingPathComponent(Self.payloadFilename)
    )
  }

  private func writeEntry(metadata: EntryMetadata, data: Data, to urls: EntryURLs) throws {
    try fileManager.createDirectory(at: urls.directory, withIntermediateDirectories: false)
    let encoder = JSONEncoder()
    try encoder.encode(metadata).write(to: urls.metadata, options: .atomic)
    try data.write(to: urls.payload, options: .atomic)
    try assertExistingEntry(urls)
  }

  private func readMetadata(at url: URL, expectedDirectory: URL) throws -> EntryMetadata {
    try ensureDownloaded(url, timeoutMilliseconds: Self.uploadTimeoutMilliseconds)
    let data = try coordinateRead(url) { try Data(contentsOf: $0) }
    let metadata: EntryMetadata
    do {
      metadata = try JSONDecoder().decode(EntryMetadata.self, from: data)
    } catch {
      throw CloudStorageFailure("provider", "A cloud storage entry has invalid metadata")
    }
    guard metadata.version == Self.formatVersion,
      UUID(uuidString: metadata.id) != nil,
      expectedDirectory.lastPathComponent == metadata.id
    else {
      throw CloudStorageFailure("provider", "A cloud storage entry has invalid metadata")
    }
    do {
      try ICloudValidation.file(name: metadata.name, data: [])
    } catch {
      throw CloudStorageFailure("provider", "A cloud storage entry has invalid metadata")
    }
    return metadata
  }

  private func cloudFile(from metadata: EntryMetadata, urls: EntryURLs) throws -> NativeCloudFile {
    try assertExistingEntry(urls)
    let values = try urls.payload.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    guard let size = values.fileSize, let modifiedAt = values.contentModificationDate else {
      throw CloudStorageFailure("provider", "Unable to read cloud file metadata")
    }
    return NativeCloudFile(
      id: metadata.id,
      name: metadata.name,
      size: Int64(size),
      modifiedAt: Self.iso8601.string(from: modifiedAt)
    )
  }

  private static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private func metadataURLs(in root: URL) throws -> [URL] {
    let query = NSMetadataQuery()
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    query.operationQueue = queue
    query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    query.predicate = NSPredicate(
      format: "%K BEGINSWITH %@ AND %K == %@",
      NSMetadataItemPathKey,
      root.path,
      NSMetadataItemFSNameKey,
      Self.metadataFilename
    )

    let semaphore = DispatchSemaphore(value: 0)
    let observer = NotificationCenter.default.addObserver(
      forName: .NSMetadataQueryDidFinishGathering,
      object: query,
      queue: queue
    ) { _ in semaphore.signal() }
    defer {
      NotificationCenter.default.removeObserver(observer)
      query.stop()
    }
    guard query.start() else {
      throw CloudStorageFailure("provider", "Unable to start the iCloud metadata query")
    }
    guard semaphore.wait(timeout: .now() + 30) == .success else {
      throw CloudStorageFailure("timeout", "Timed out while listing iCloud files")
    }
    query.disableUpdates()
    defer { query.enableUpdates() }
    return (0..<query.resultCount).compactMap { index in
      guard let item = query.result(at: index) as? NSMetadataItem else { return nil }
      return item.value(forAttribute: NSMetadataItemURLKey) as? URL
    }
  }

  private func waitForMetadataUpload(of url: URL, timeoutMilliseconds: UInt32) throws {
    let query = NSMetadataQuery()
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    query.operationQueue = queue
    query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, url.path)

    let lock = NSLock()
    let semaphore = DispatchSemaphore(value: 0)
    var outcome: Result<Void, CloudStorageFailure>?
    func inspect() {
      query.disableUpdates()
      defer { query.enableUpdates() }
      for index in 0..<query.resultCount {
        guard let item = query.result(at: index) as? NSMetadataItem,
          let itemURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
          itemURL.standardizedFileURL == url.standardizedFileURL
        else { continue }
        if let error = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError {
          lock.lock()
          outcome = .failure(CloudStorageFailure("provider", error.localizedDescription))
          lock.unlock()
          semaphore.signal()
          return
        }
        if (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) == true {
          lock.lock()
          outcome = .success(())
          lock.unlock()
          semaphore.signal()
          return
        }
      }
    }
    let center = NotificationCenter.default
    let finished = center.addObserver(
      forName: .NSMetadataQueryDidFinishGathering,
      object: query,
      queue: queue
    ) { _ in inspect() }
    let updated = center.addObserver(
      forName: .NSMetadataQueryDidUpdate,
      object: query,
      queue: queue
    ) { _ in inspect() }
    defer {
      center.removeObserver(finished)
      center.removeObserver(updated)
      query.stop()
    }
    guard query.start() else {
      throw CloudStorageFailure("provider", "Unable to observe iCloud upload status")
    }
    guard semaphore.wait(timeout: .now() + .milliseconds(Int(timeoutMilliseconds))) == .success else {
      throw CloudStorageFailure("timeout", "Timed out waiting for iCloud upload")
    }
    lock.lock()
    let completed = outcome
    lock.unlock()
    guard let completed else {
      throw CloudStorageFailure("internal", "iCloud upload observer completed without a result")
    }
    try completed.get()
  }

  private func decodeCursor(_ value: String?) throws -> PageCursor? {
    guard let value else { return nil }
    guard !value.isEmpty,
      let data = base64URLDecode(value),
      let cursor = try? JSONDecoder().decode(PageCursor.self, from: data),
      cursor.version == Self.formatVersion,
      cursor.connectionId == connectionId?.uuidString,
      UUID(uuidString: cursor.lastId) != nil
    else {
      throw CloudStorageFailure("invalidArgument", "cursor is invalid for this connection")
    }
    return cursor
  }

  private func encodeCursor(lastId: String) throws -> String {
    guard let connectionId else {
      throw CloudStorageFailure("notConnected", "Call connect before accessing cloud files")
    }
    let cursor = PageCursor(
      version: Self.formatVersion,
      connectionId: connectionId.uuidString,
      lastId: lastId
    )
    return base64URLEncode(try JSONEncoder().encode(cursor))
  }

  private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private func base64URLDecode(_ value: String) -> Data? {
    let base64 = value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padding = String(repeating: "=", count: (4 - base64.count % 4) % 4)
    return Data(base64Encoded: base64 + padding)
  }

  private func ensureDownloaded(_ url: URL, timeoutMilliseconds: UInt32) throws {
    let initial = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
    guard initial.ubiquitousItemDownloadingStatus == .notDownloaded else { return }
    try fileManager.startDownloadingUbiquitousItem(at: url)
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutMilliseconds) / 1_000)
    while Date() < deadline {
      let values = try url.resourceValues(forKeys: [
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemDownloadingErrorKey,
      ])
      if let error = values.ubiquitousItemDownloadingError {
        throw CloudStorageFailure("provider", error.localizedDescription)
      }
      if values.ubiquitousItemDownloadingStatus == .current { return }
      Thread.sleep(forTimeInterval: 0.2)
    }
    throw CloudStorageFailure("timeout", "Timed out downloading an iCloud file")
  }

  private func coordinateRead<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
    let coordinator = NSFileCoordinator()
    var coordinatorError: NSError?
    var result: Result<T, Swift.Error>?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
      result = Result { try body(coordinatedURL) }
    }
    if let coordinatorError { throw coordinatorError }
    guard let result else {
      throw CloudStorageFailure("io", "Coordinated iCloud read did not complete")
    }
    return try result.get()
  }

  private func coordinateWrite(
    _ url: URL,
    options: NSFileCoordinator.WritingOptions,
    _ body: (URL) throws -> Void
  ) throws {
    let coordinator = NSFileCoordinator()
    var coordinatorError: NSError?
    var result: Result<Void, Swift.Error>?
    coordinator.coordinate(writingItemAt: url, options: options, error: &coordinatorError) { coordinatedURL in
      result = Result { try body(coordinatedURL) }
    }
    if let coordinatorError { throw coordinatorError }
    guard let result else {
      throw CloudStorageFailure("io", "Coordinated iCloud write did not complete")
    }
    try result.get()
  }

  private func assertExistingEntry(_ urls: EntryURLs) throws {
    try assertSafeDirectory(urls.directory, mustExist: true)
    try assertSafeFile(urls.metadata, mustExist: true)
    try assertSafeFile(urls.payload, mustExist: true)
  }

  private func assertSafeDirectory(_ url: URL, mustExist: Bool) throws {
    guard fileManager.fileExists(atPath: url.path) else {
      if mustExist { throw CloudStorageFailure("notFound", "The requested file does not exist") }
      return
    }
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw CloudStorageFailure("provider", "Cloud storage contains an unsafe directory entry")
    }
  }

  private func assertSafeFile(_ url: URL, mustExist: Bool) throws {
    guard fileManager.fileExists(atPath: url.path) else {
      if mustExist { throw CloudStorageFailure("notFound", "The requested file does not exist") }
      return
    }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw CloudStorageFailure("provider", "Cloud storage contains an unsafe file entry")
    }
  }

  private func isContained(_ child: URL, in root: URL) -> Bool {
    let rootPath = root.standardizedFileURL.path.hasSuffix("/")
      ? root.standardizedFileURL.path
      : root.standardizedFileURL.path + "/"
    return child.standardizedFileURL.path.hasPrefix(rootPath)
  }

  private func removeAbandonedTemporaryEntries() throws {
    guard let root else { return }
    let temporary = root.appendingPathComponent(".temporary", isDirectory: true)
    guard fileManager.fileExists(atPath: temporary.path) else { return }
    try assertSafeDirectory(temporary, mustExist: true)
    let entries = try fileManager.contentsOfDirectory(
      at: temporary,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles]
    )
    for entry in entries where isContained(entry, in: root) {
      try assertSafeDirectory(entry, mustExist: true)
      try fileManager.removeItem(at: entry)
    }
  }

  private func map(_ error: Swift.Error) -> CloudStorageFailure {
    if let failure = error as? CloudStorageFailure { return failure }
    let error = error as NSError
    switch error.code {
    case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
      return CloudStorageFailure("notFound", error.localizedDescription)
    case NSFileWriteOutOfSpaceError:
      return CloudStorageFailure("quotaExceeded", error.localizedDescription)
    case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
      return CloudStorageFailure("unavailable", error.localizedDescription)
    default:
      return CloudStorageFailure("io", error.localizedDescription)
    }
  }
}
