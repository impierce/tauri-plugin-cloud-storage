//! App-scoped cloud file storage for iOS and Android.
//!
//! The public data contract can be used on any target. Plugin registration and
//! native cloud access are available only on mobile targets.
//! Provider operations are under development; this crate is not release-ready.

mod error;
mod models;

pub use error::{Error, ErrorCode, Result};
pub use models::*;

#[cfg(mobile)]
mod commands;
#[cfg(mobile)]
mod mobile;

#[cfg(mobile)]
use tauri::{Manager, Runtime};

#[cfg(mobile)]
pub use mobile::CloudStorage;

/// Access to the native cloud-storage provider from Rust.
#[cfg(mobile)]
pub trait CloudStorageExt<R: Runtime> {
    fn cloud_storage(&self) -> &CloudStorage<R>;
}

#[cfg(mobile)]
impl<R: Runtime, T: Manager<R>> CloudStorageExt<R> for T {
    fn cloud_storage(&self) -> &CloudStorage<R> {
        self.state::<CloudStorage<R>>().inner()
    }
}

/// Registers the native mobile plugin.
#[cfg(mobile)]
pub fn init<R: tauri::Runtime>() -> tauri::plugin::TauriPlugin<R> {
    tauri::plugin::Builder::new("cloud-storage")
        .invoke_handler(tauri::generate_handler![
            commands::get_status,
            commands::connect,
            commands::disconnect,
            commands::list_files,
            commands::create_file,
            commands::read_file,
            commands::update_file,
            commands::delete_file,
            commands::wait_for_upload,
        ])
        .setup(|app, api| {
            app.manage(mobile::init(app, api)?);
            Ok(())
        })
        .build()
}
