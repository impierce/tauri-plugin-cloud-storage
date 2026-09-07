/**
 * Public contract for the mobile cloud providers.
 *
 * This step exports types only. Runtime functions will be added with the native
 * providers; there is no working cloud-storage implementation yet.
 */

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
 * API contract for the upcoming runtime functions, also available from Rust.
 * Each method will be exported as a named function; no client construction is
 * required. Importing this interface does not create a cloud connection.
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
}
