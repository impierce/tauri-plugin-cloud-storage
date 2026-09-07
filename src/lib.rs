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
mod mobile;

/// Registers the native mobile plugin.
#[cfg(mobile)]
pub fn init<R: tauri::Runtime>() -> tauri::plugin::TauriPlugin<R> {
    tauri::plugin::Builder::new("cloud-storage")
        .setup(|_app, api| mobile::register(api))
        .build()
}
