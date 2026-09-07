use serde::{de::DeserializeOwned, Serialize};
use tauri::{
    plugin::{PluginApi, PluginHandle},
    AppHandle, Runtime,
};

use crate::{
    CloudFile, CreateFileOptions, FilePage, ListFilesOptions, Result, StorageStatus,
    UpdateFileOptions, WaitForUploadOptions,
};

#[cfg(target_os = "android")]
const PLUGIN_IDENTIFIER: &str = "app.tauri.cloudstorage";

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_cloud_storage);

pub fn init<R: Runtime, C: DeserializeOwned>(
    _app: &AppHandle<R>,
    api: PluginApi<R, C>,
) -> Result<CloudStorage<R>> {
    #[cfg(target_os = "android")]
    let handle = api.register_android_plugin(PLUGIN_IDENTIFIER, "CloudStoragePlugin")?;
    #[cfg(target_os = "ios")]
    let handle = api.register_ios_plugin(init_plugin_cloud_storage)?;
    Ok(CloudStorage(handle))
}

/// Access to the mobile provider. Calls are asynchronous to avoid blocking the
/// command executor while the native provider performs I/O or waits for iCloud.
pub struct CloudStorage<R: Runtime>(PluginHandle<R>);

impl<R: Runtime> CloudStorage<R> {
    pub async fn get_status(&self) -> Result<StorageStatus> {
        self.0
            .run_mobile_plugin_async("getStatus", ())
            .await
            .map_err(Into::into)
    }

    pub async fn connect(&self) -> Result<StorageStatus> {
        self.0
            .run_mobile_plugin_async("connect", ())
            .await
            .map_err(Into::into)
    }

    pub async fn disconnect(&self) -> Result<()> {
        self.0
            .run_mobile_plugin_async("disconnect", ())
            .await
            .map_err(Into::into)
    }

    pub async fn list_files(&self, options: ListFilesOptions) -> Result<FilePage> {
        options.validate()?;
        self.0
            .run_mobile_plugin_async("listFiles", options)
            .await
            .map_err(Into::into)
    }

    pub async fn create_file(&self, options: CreateFileOptions) -> Result<CloudFile> {
        options.validate()?;
        self.0
            .run_mobile_plugin_async("createFile", options)
            .await
            .map_err(Into::into)
    }

    pub async fn read_file(&self, id: String) -> Result<Vec<u8>> {
        let request = FileIdRequest::new(id)?;
        self.0
            .run_mobile_plugin_async("readFile", request)
            .await
            .map_err(Into::into)
    }

    pub async fn update_file(&self, options: UpdateFileOptions) -> Result<CloudFile> {
        options.validate()?;
        self.0
            .run_mobile_plugin_async("updateFile", options)
            .await
            .map_err(Into::into)
    }

    pub async fn delete_file(&self, id: String) -> Result<()> {
        let request = FileIdRequest::new(id)?;
        self.0
            .run_mobile_plugin_async("deleteFile", request)
            .await
            .map_err(Into::into)
    }

    pub async fn wait_for_upload(&self, options: WaitForUploadOptions) -> Result<()> {
        options.validate()?;
        self.0
            .run_mobile_plugin_async("waitForUpload", options)
            .await
            .map_err(Into::into)
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FileIdRequest {
    id: String,
}

impl FileIdRequest {
    fn new(id: String) -> Result<Self> {
        crate::validate_file_id(&id)?;
        Ok(Self { id })
    }
}
