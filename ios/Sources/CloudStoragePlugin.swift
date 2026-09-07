import Foundation
import Tauri
import CloudStorageCore

class CloudStoragePlugin: Plugin {
  private let workQueue = DispatchQueue(label: "app.tauri.cloudstorage.icloud")
  private var provider: ICloudProvider?
  private var configurationFailure: CloudStorageFailure?

  private func configuredProvider() throws -> ICloudProvider {
    if let provider { return provider }
    if let configurationFailure { throw configurationFailure }
    do {
      let configuration = try parseConfig(ICloudConfiguration.self)
      let provider = ICloudProvider(configuration: configuration)
      self.provider = provider
      return provider
    } catch let failure as CloudStorageFailure {
      configurationFailure = failure
      throw failure
    } catch {
      let failure = CloudStorageFailure(
        "invalidArgument",
        "Invalid cloud-storage plugin configuration: \(error.localizedDescription)"
      )
      configurationFailure = failure
      throw failure
    }
  }

  private func execute<T: Encodable>(_ invoke: Invoke, _ operation: @escaping (ICloudProvider) throws -> T) {
    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        invoke.resolve(try operation(self.configuredProvider()))
      } catch let failure as CloudStorageFailure {
        invoke.reject(failure.message, code: failure.code)
      } catch {
        invoke.reject(error.localizedDescription, code: "internal")
      }
    }
  }

  private func execute(_ invoke: Invoke, _ operation: @escaping (ICloudProvider) throws -> Void) {
    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        try operation(self.configuredProvider())
        invoke.resolve()
      } catch let failure as CloudStorageFailure {
        invoke.reject(failure.message, code: failure.code)
      } catch {
        invoke.reject(error.localizedDescription, code: "internal")
      }
    }
  }

  @objc func getStatus(_ invoke: Invoke) {
    execute(invoke) { $0.getStatus() }
  }

  @objc func connect(_ invoke: Invoke) {
    execute(invoke) { try $0.connect() }
  }

  @objc func disconnect(_ invoke: Invoke) {
    execute(invoke) { $0.disconnect() }
  }

  @objc func listFiles(_ invoke: Invoke) throws {
    let options = try invoke.parseArgs(NativeListFilesOptions.self)
    execute(invoke) { try $0.listFiles(options) }
  }

  @objc func createFile(_ invoke: Invoke) throws {
    let options = try invoke.parseArgs(NativeCreateFileOptions.self)
    execute(invoke) { try $0.createFile(options) }
  }

  @objc func readFile(_ invoke: Invoke) throws {
    let options = try invoke.parseArgs(NativeFileIdOptions.self)
    execute(invoke) { try $0.readFile(options) }
  }

  @objc func updateFile(_ invoke: Invoke) throws {
    let options = try invoke.parseArgs(NativeUpdateFileOptions.self)
    execute(invoke) { try $0.updateFile(options) }
  }

  @objc func deleteFile(_ invoke: Invoke) throws {
    let options = try invoke.parseArgs(NativeFileIdOptions.self)
    execute(invoke) { try $0.deleteFile(options) }
  }

  @objc func waitForUpload(_ invoke: Invoke) throws {
    let options = try invoke.parseArgs(NativeWaitForUploadOptions.self)
    execute(invoke) { try $0.waitForUpload(options) }
  }
}

@_cdecl("init_plugin_cloud_storage")
func initPlugin() -> Plugin {
  CloudStoragePlugin()
}
