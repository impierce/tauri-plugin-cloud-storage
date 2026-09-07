use serde::de::DeserializeOwned;
use tauri::{plugin::PluginApi, Runtime};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_cloud_storage);

pub fn register<R: Runtime, C: DeserializeOwned>(
    api: PluginApi<R, C>,
) -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "android")]
    api.register_android_plugin("app.tauri.cloudstorage", "CloudStoragePlugin")?;
    #[cfg(target_os = "ios")]
    api.register_ios_plugin(init_plugin_cloud_storage)?;
    Ok(())
}
