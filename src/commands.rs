use tauri::{command, AppHandle, Runtime};

use crate::{
    CloudFile, CloudStorageExt, CreateFileOptions, FilePage, ListFilesOptions, Result,
    StorageStatus, UpdateFileOptions, WaitForUploadOptions,
};

#[command]
pub(crate) async fn get_status<R: Runtime>(app: AppHandle<R>) -> Result<StorageStatus> {
    app.cloud_storage().get_status().await
}

#[command]
pub(crate) async fn connect<R: Runtime>(app: AppHandle<R>) -> Result<StorageStatus> {
    app.cloud_storage().connect().await
}

#[command]
pub(crate) async fn disconnect<R: Runtime>(app: AppHandle<R>) -> Result<()> {
    app.cloud_storage().disconnect().await
}

#[command]
pub(crate) async fn list_files<R: Runtime>(
    app: AppHandle<R>,
    options: Option<ListFilesOptions>,
) -> Result<FilePage> {
    app.cloud_storage()
        .list_files(options.unwrap_or_default())
        .await
}

#[command]
pub(crate) async fn create_file<R: Runtime>(
    app: AppHandle<R>,
    options: CreateFileOptions,
) -> Result<CloudFile> {
    app.cloud_storage().create_file(options).await
}

#[command]
pub(crate) async fn read_file<R: Runtime>(app: AppHandle<R>, id: String) -> Result<Vec<u8>> {
    app.cloud_storage().read_file(id).await
}

#[command]
pub(crate) async fn update_file<R: Runtime>(
    app: AppHandle<R>,
    options: UpdateFileOptions,
) -> Result<CloudFile> {
    app.cloud_storage().update_file(options).await
}

#[command]
pub(crate) async fn delete_file<R: Runtime>(app: AppHandle<R>, id: String) -> Result<()> {
    app.cloud_storage().delete_file(id).await
}

#[command]
pub(crate) async fn wait_for_upload<R: Runtime>(
    app: AppHandle<R>,
    options: WaitForUploadOptions,
) -> Result<()> {
    app.cloud_storage().wait_for_upload(options).await
}
