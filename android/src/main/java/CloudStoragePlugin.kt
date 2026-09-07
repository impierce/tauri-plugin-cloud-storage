package app.tauri.cloudstorage

import android.app.Activity
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Plugin

/** Native entry point. Provider commands are implemented in subsequent steps. */
@TauriPlugin
class CloudStoragePlugin(activity: Activity) : Plugin(activity)
