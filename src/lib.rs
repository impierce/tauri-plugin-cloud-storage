use tauri::{
  plugin::{Builder, TauriPlugin},
  Manager, Runtime,
};

pub use models::*;

#[cfg(desktop)]
mod desktop;
#[cfg(mobile)]
mod mobile;

mod commands;
mod error;
mod models;

pub use error::{Error, Result};

#[cfg(desktop)]
use desktop::CloudStorage;
#[cfg(mobile)]
use mobile::CloudStorage;

/// Extensions to [`tauri::App`], [`tauri::AppHandle`] and [`tauri::Window`] to access the cloud-storage APIs.
pub trait CloudStorageExt<R: Runtime> {
  fn cloud_storage(&self) -> &CloudStorage<R>;
}

impl<R: Runtime, T: Manager<R>> crate::CloudStorageExt<R> for T {
  fn cloud_storage(&self) -> &CloudStorage<R> {
    self.state::<CloudStorage<R>>().inner()
  }
}

/// Initializes the plugin.
pub fn init<R: Runtime>() -> TauriPlugin<R> {
  Builder::new("cloud-storage")
    .invoke_handler(tauri::generate_handler![commands::ping])
    .setup(|app, api| {
      #[cfg(mobile)]
      let cloud_storage = mobile::init(app, api)?;
      #[cfg(desktop)]
      let cloud_storage = desktop::init(app, api)?;
      app.manage(cloud_storage);
      Ok(())
    })
    .build()
}
