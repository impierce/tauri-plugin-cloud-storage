package app.tauri.cloudstorage

import android.app.Activity
import app.tauri.annotation.Command
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin

/**
 * Google Drive support is implemented in the next step. Shared commands are
 * deliberately explicit here so Android never reports a fake successful state.
 */
@TauriPlugin
class CloudStoragePlugin(activity: Activity) : Plugin(activity) {
    @Command
    fun getStatus(invoke: Invoke) {
        invoke.resolve(JSObject().apply {
            put("provider", "googleDrive")
            put("state", "unavailable")
        })
    }

    @Command fun connect(invoke: Invoke) = unavailable(invoke)
    @Command fun disconnect(invoke: Invoke) = unavailable(invoke)
    @Command fun listFiles(invoke: Invoke) = unavailable(invoke)
    @Command fun createFile(invoke: Invoke) = unavailable(invoke)
    @Command fun readFile(invoke: Invoke) = unavailable(invoke)
    @Command fun updateFile(invoke: Invoke) = unavailable(invoke)
    @Command fun deleteFile(invoke: Invoke) = unavailable(invoke)
    @Command fun waitForUpload(invoke: Invoke) = unavailable(invoke)

    private fun unavailable(invoke: Invoke) {
        invoke.reject("Google Drive support is not implemented yet", "unavailable")
    }
}
