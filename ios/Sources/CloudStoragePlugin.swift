import Tauri

/// Native entry point. Provider commands are implemented in subsequent steps.
class CloudStoragePlugin: Plugin {}

@_cdecl("init_plugin_cloud_storage")
func initPlugin() -> Plugin {
  CloudStoragePlugin()
}
