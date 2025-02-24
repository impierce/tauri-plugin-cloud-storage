use tauri::{AppHandle, command, Runtime};

use crate::models::*;
use crate::Result;
use crate::CloudStorageExt;

#[command]
pub(crate) async fn ping<R: Runtime>(
    app: AppHandle<R>,
    payload: PingRequest,
) -> Result<PingResponse> {
    app.cloud_storage().ping(payload)
}
