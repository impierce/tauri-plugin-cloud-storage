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

#[cfg(mobile)]
impl From<tauri::plugin::mobile::PluginInvokeError> for Error {
    fn from(error: tauri::plugin::mobile::PluginInvokeError) -> Self {
        match error {
            tauri::plugin::mobile::PluginInvokeError::InvokeRejected(response) => {
                let code = response
                    .code
                    .as_deref()
                    .and_then(native_error_code)
                    .unwrap_or(ErrorCode::Provider);
                Error::new(
                    code,
                    response
                        .message
                        .unwrap_or_else(|| "The native provider rejected the operation".into()),
                )
            }
            error => Error::new(ErrorCode::Internal, error.to_string()),
        }
    }
}

#[cfg(mobile)]
fn native_error_code(value: &str) -> Option<ErrorCode> {
    Some(match value {
        "invalidArgument" => ErrorCode::InvalidArgument,
        "unavailable" => ErrorCode::Unavailable,
        "notConnected" => ErrorCode::NotConnected,
        "cancelled" => ErrorCode::Cancelled,
        "notFound" => ErrorCode::NotFound,
        "conflict" => ErrorCode::Conflict,
        "quotaExceeded" => ErrorCode::QuotaExceeded,
        "network" => ErrorCode::Network,
        "timeout" => ErrorCode::Timeout,
        "busy" => ErrorCode::Busy,
        "io" => ErrorCode::Io,
        "provider" => ErrorCode::Provider,
        "internal" => ErrorCode::Internal,
        _ => return None,
    })
}
