import { invoke } from '@tauri-apps/api/core'

export async function ping(value: string): Promise<string | null> {
  return await invoke<{value?: string}>('plugin:cloud-storage|ping', {
    payload: {
      value,
    },
  }).then((r) => (r.value ? r.value : null));
}
