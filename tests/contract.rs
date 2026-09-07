use serde_json::{json, Value};
use tauri_plugin_cloud_storage::{
    validate_file_id, CloudFile, ConnectionState, CreateFileOptions, Error, ErrorCode, FilePage,
    ListFilesOptions, Provider, StorageStatus, UpdateFileOptions, WaitForUploadOptions,
    MAX_FILE_SIZE,
};

#[test]
fn native_responses_use_the_javascript_contract() {
    for (provider, expected) in [
        (Provider::ICloud, "iCloud"),
        (Provider::GoogleDrive, "googleDrive"),
    ] {
        let status = StorageStatus {
            provider,
            state: ConnectionState::Connected,
        };
        assert_eq!(
            serde_json::to_value(status).unwrap(),
            json!({"provider": expected, "state": "connected"})
        );
    }
    let page = FilePage {
        files: vec![CloudFile {
            id: "opaque-id".into(),
            name: "wallet.backup".into(),
            size: 3,
            modified_at: "2026-09-07T00:00:00Z".into(),
        }],
        next_cursor: None,
    };
    assert_eq!(
        serde_json::to_value(&page).unwrap(),
        json!({"files": [{
            "id": "opaque-id", "name": "wallet.backup", "size": 3,
            "modifiedAt": "2026-09-07T00:00:00Z"
        }]})
    );
    let page = FilePage {
        files: vec![],
        next_cursor: Some("next".into()),
    };
    assert_eq!(
        serde_json::to_value(page).unwrap(),
        json!({"files": [], "nextCursor": "next"})
    );
    assert_eq!(
        serde_json::to_value(Error::new(ErrorCode::NotConnected, "Connect first")).unwrap(),
        json!({"code":"notConnected", "message":"Connect first"})
    );
}

#[test]
fn listing_defaults_and_limits_are_explicit() {
    let defaults: ListFilesOptions = serde_json::from_value(json!({})).unwrap();
    assert_eq!(defaults, ListFilesOptions::default());
    assert_eq!(defaults.page_size, 100);
    for page_size in [1, 100, 1000] {
        assert!(ListFilesOptions {
            page_size,
            cursor: None
        }
        .validate()
        .is_ok());
    }
    for page_size in [0, 1001, u16::MAX] {
        assert_eq!(
            ListFilesOptions {
                page_size,
                cursor: None
            }
            .validate()
            .unwrap_err()
            .code,
            ErrorCode::InvalidArgument
        );
    }
    for invalid in [
        json!({"pageSize": -1}),
        json!({"pageSize": 1.5}),
        json!({"page_size": 5}),
    ] {
        assert!(serde_json::from_value::<ListFilesOptions>(invalid).is_err());
    }
    assert!(ListFilesOptions {
        cursor: Some(String::new()),
        ..defaults
    }
    .validate()
    .is_err());
}

#[test]
fn names_are_portable_labels_not_paths() {
    for name in [
        "",
        "  ",
        ".",
        "..",
        "../secret",
        "a/b",
        "a\\b",
        "a\0b",
        "a\nb",
    ] {
        assert_eq!(
            CreateFileOptions {
                name: name.into(),
                data: vec![]
            }
            .validate()
            .unwrap_err()
            .code,
            ErrorCode::InvalidArgument
        );
    }
    for name in ["wallet.backup".to_owned(), "a".repeat(255), "é".repeat(127)] {
        assert!(CreateFileOptions { name, data: vec![] }.validate().is_ok());
    }
    for name in ["a".repeat(256), "é".repeat(128)] {
        assert!(CreateFileOptions { name, data: vec![] }.validate().is_err());
    }
}

#[test]
fn binary_payloads_preserve_zero_and_non_utf8_bytes() {
    let options: CreateFileOptions =
        serde_json::from_value(json!({"name":"binary", "data":[0, 128, 255]})).unwrap();
    assert_eq!(options.data, vec![0, 128, 255]);
    for data in [
        json!([-1]),
        json!([256]),
        json!([1.5]),
        Value::String("text".into()),
    ] {
        assert!(
            serde_json::from_value::<CreateFileOptions>(json!({"name":"binary", "data":data}))
                .is_err()
        );
    }
    assert!(UpdateFileOptions {
        id: String::new(),
        data: vec![]
    }
    .validate()
    .is_err());
    assert!(validate_file_id("opaque:provider-id").is_ok());
    assert!(validate_file_id("id\0").is_err());
}

#[test]
fn payload_and_upload_wait_limits_are_bounded() {
    assert!(CreateFileOptions {
        name: "limit".into(),
        data: vec![0; MAX_FILE_SIZE],
    }
    .validate()
    .is_ok());
    assert_eq!(
        CreateFileOptions {
            name: "limit".into(),
            data: vec![0; MAX_FILE_SIZE + 1],
        }
        .validate()
        .unwrap_err()
        .code,
        ErrorCode::InvalidArgument
    );

    let defaults: WaitForUploadOptions = serde_json::from_value(json!({ "id": "opaque" })).unwrap();
    assert_eq!(defaults.timeout_ms, 60_000);
    for timeout_ms in [1_000, 60_000, 300_000] {
        assert!(WaitForUploadOptions {
            id: "opaque".into(),
            timeout_ms
        }
        .validate()
        .is_ok());
    }
    for timeout_ms in [0, 999, 300_001, u32::MAX] {
        assert!(WaitForUploadOptions {
            id: "opaque".into(),
            timeout_ms
        }
        .validate()
        .is_err());
    }
}
