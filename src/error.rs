use serde::{Deserialize, Serialize};

pub type Result<T> = std::result::Result<T, Error>;

/// Portable error categories. Provider messages are diagnostic, not API codes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ErrorCode {
    InvalidArgument,
    Unavailable,
    NotConnected,
    Cancelled,
    NotFound,
    Conflict,
    QuotaExceeded,
    Network,
    Timeout,
    Busy,
    Io,
    Provider,
    Internal,
}

/// Serializable error shared by the Rust API and JavaScript rejections.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, thiserror::Error)]
#[error("{message}")]
#[serde(rename_all = "camelCase")]
pub struct Error {
    pub code: ErrorCode,
    pub message: String,
}

impl Error {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}
