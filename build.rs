const COMMANDS: &[&str] = &[
    "get_status",
    "connect",
    "disconnect",
    "list_files",
    "create_file",
    "read_file",
    "update_file",
    "delete_file",
    "wait_for_upload",
];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .ios_path("ios")
        .build();
}
