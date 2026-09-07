use serde::{Deserialize, Serialize};

use crate::{Error, ErrorCode, Result};

/// The OS-specific provider used for this app's cloud files.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Provider {
    ICloud,
    GoogleDrive,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ConnectionState {
    Unavailable,
    Disconnected,
    Connected,
}

/// Connection state, not a guarantee of network connectivity or remote sync.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageStatus {
    pub provider: Provider,
    pub state: ConnectionState,
}

/// A file identifier is opaque and scoped to the provider, app, and account.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudFile {
    pub id: String,
    pub name: String,
    /// Byte length, represented as a JSON number.
    pub size: u64,
    /// Last modification time in RFC 3339 format, in UTC.
    pub modified_at: String,
}

/// A page does not represent an atomic snapshot across concurrent writes.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FilePage {
    pub files: Vec<CloudFile>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}

/// Listing is unordered. A cursor is opaque and must not be parsed or modified.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ListFilesOptions {
    #[serde(default = "default_page_size")]
    pub page_size: u16,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cursor: Option<String>,
}

const fn default_page_size() -> u16 {
    100
}

impl Default for ListFilesOptions {
    fn default() -> Self {
        Self {
            page_size: default_page_size(),
            cursor: None,
        }
    }
}

impl ListFilesOptions {
    pub fn validate(&self) -> Result<()> {
        if !(1..=1000).contains(&self.page_size) {
            return Err(Error::new(
                ErrorCode::InvalidArgument,
                "pageSize must be between 1 and 1000",
            ));
        }
        if self.cursor.as_ref().is_some_and(|cursor| cursor.is_empty()) {
            return Err(Error::new(
                ErrorCode::InvalidArgument,
                "cursor must not be empty",
            ));
        }
        Ok(())
    }
}

/// Creates a new file. Names are display labels; duplicate names are allowed.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateFileOptions {
    pub name: String,
    pub data: Vec<u8>,
}

impl CreateFileOptions {
    pub fn validate(&self) -> Result<()> {
        // A portable single filename, never a filesystem path. Byte length
        // ensures multibyte names fit the same limit on both platforms.
        if self.name.trim().is_empty()
            || self.name.len() > 255
            || matches!(self.name.as_str(), "." | "..")
            || self
                .name
                .chars()
                .any(|c| c == '/' || c == '\\' || c.is_control())
        {
            return Err(Error::new(
                ErrorCode::InvalidArgument,
                "name must be a nonblank filename of at most 255 UTF-8 bytes, without path separators or control characters",
            ));
        }
        Ok(())
    }
}

/// Replaces the contents of an existing file, preserving its ID and name.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateFileOptions {
    pub id: String,
    pub data: Vec<u8>,
}

impl UpdateFileOptions {
    pub fn validate(&self) -> Result<()> {
        validate_file_id(&self.id)
    }
}

/// Checks presence only. Providers must also check ownership and containment.
pub fn validate_file_id(id: &str) -> Result<()> {
    if id.is_empty() || id.chars().any(char::is_control) {
        return Err(Error::new(
            ErrorCode::InvalidArgument,
            "id must not be empty or contain control characters",
        ));
    }
    Ok(())
}
