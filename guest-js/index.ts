/**
 * Public contract for the mobile cloud providers.
 *
 * Provider operations are available on supported mobile platforms only.
 */

import { invoke } from '@tauri-apps/api/core'

export type Provider = 'iCloud' | 'googleDrive'
export type ConnectionState = 'unavailable' | 'disconnected' | 'connected'

/** Connection state does not imply network connectivity or completed sync. */
export interface StorageStatus {
  provider: Provider
  state: ConnectionState
}

export interface CloudFile {
  /** Opaque identifier scoped to the current provider, app, and account. */
  id: string
  /** Display name, not a path or unique key. Duplicate names are allowed. */
  name: string
  /** Byte length. */
  size: number
  /** RFC 3339 timestamp in UTC. */
  modifiedAt: string
}

export interface ListFilesOptions {
  /** Maximum results per page, from 1 to 1000. Defaults to 100. */
  pageSize?: number
  /** Opaque cursor from the previous page; omit for the first page. */
  cursor?: string
}

export interface FilePage {
  /** Unordered results. Sort in the application after collecting all pages. */
  files: CloudFile[]
  /** Absent at the end. Continue even if an intermediate page is empty. */
  nextCursor?: string
}

export interface CreateFileOptions {
  /**
   * Nonblank filename, at most 255 UTF-8 bytes; no path separators, control
   * characters, or standalone '.' / '..'. Names do not select filesystem paths.
   */
  name: string
  /** Opaque bytes; encryption and serialization belong to the application. */
  data: Uint8Array
}

export interface UpdateFileOptions {
  id: string
  /** Entire replacement content. Preserves the file ID and display name. */
  data: Uint8Array
}

export interface WaitForUploadOptions {
  /** Opaque identifier returned by createFile or listFiles. */
  id: string
  /** Milliseconds to wait, from 1,000 to 300,000. Defaults to 60,000. */
  timeoutMs?: number
}

export type CloudStorageErrorCode =
  | 'invalidArgument'
  | 'unavailable'
  | 'notConnected'
  | 'cancelled'
  | 'notFound'
  | 'conflict'
  | 'quotaExceeded'
  | 'network'
  | 'timeout'
  | 'busy'
  | 'io'
  | 'provider'
  | 'internal'

/** Native operation rejection. Match the code, not the diagnostic message. */
export interface CloudStorageError {
  code: CloudStorageErrorCode
  message: string
}

/**
 * API contract, also available from Rust. Each method is exported as a named
 * function; importing this module does not create a cloud connection.
 */
export interface CloudStorageApi {
  /** Checks status without presenting authorization UI. */
  getStatus(): Promise<StorageStatus>
  /** Explicit user action; may show Android account selection and consent. */
  connect(): Promise<StorageStatus>
  /**
   * Disables this plugin's local access. Does not delete files, revoke the
   * Google OAuth grant, or sign the device out of its cloud account.
   */
  disconnect(): Promise<void>
  listFiles(options?: ListFilesOptions): Promise<FilePage>
  /** Creates a distinct file, even when another file has the same name. */
  createFile(options: CreateFileOptions): Promise<CloudFile>
  readFile(id: string): Promise<Uint8Array>
  updateFile(options: UpdateFileOptions): Promise<CloudFile>
  /** Permanently deletes a file. A missing file rejects with notFound. */
  deleteFile(id: string): Promise<void>
  /** Waits for provider-confirmed upload; a write resolving is only local confirmation. */
  waitForUpload(options: WaitForUploadOptions): Promise<void>
}

const command = (name: string): string => `plugin:cloud-storage|${name}`

/** Checks provider availability and local connection state without prompting. */
export const getStatus = (): Promise<StorageStatus> => invoke(command('get_status'))

/** Explicitly enables cloud access. iCloud relies on the device's existing account. */
export const connect = (): Promise<StorageStatus> => invoke(command('connect'))

/** Disables local plugin access without deleting cloud files or signing the user out. */
export const disconnect = (): Promise<void> => invoke(command('disconnect'))

/** Lists one unordered page. Follow nextCursor until it is absent. */
export const listFiles = (
  options?: ListFilesOptions
): Promise<FilePage> => invoke(command('list_files'), { options })

/** Creates a distinct file. The payload must not exceed 10 MiB. */
export const createFile = (options: CreateFileOptions): Promise<CloudFile> =>
  invoke(command('create_file'), {
    options: { ...options, data: Array.from(options.data) }
  })

/** Reads an entire file into memory. The first release supports files up to 10 MiB. */
export const readFile = async (id: string): Promise<Uint8Array> =>
  Uint8Array.from(await invoke<number[]>(command('read_file'), { id }))

/** Replaces a file's contents while preserving its identifier and display name. */
export const updateFile = (options: UpdateFileOptions): Promise<CloudFile> =>
  invoke(command('update_file'), {
    options: { ...options, data: Array.from(options.data) }
  })

/** Permanently deletes an existing file. */
export const deleteFile = (id: string): Promise<void> =>
  invoke(command('delete_file'), { id })

/**
 * Waits for remote upload confirmation. A successful createFile or updateFile
 * only confirms that the provider accepted a coordinated local write.
 */
export const waitForUpload = (options: WaitForUploadOptions): Promise<void> =>
  invoke(command('wait_for_upload'), { options })
