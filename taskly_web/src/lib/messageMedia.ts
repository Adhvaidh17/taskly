import type { SupabaseClient } from '@supabase/supabase-js'

type MediaActionResponse = {
  ok?: boolean
  error?: string
  available?: boolean
  uploadId?: string
  uploadUrl?: string
  messageId?: number
  url?: string
  name?: string | null
  mimeType?: string | null
  sizeBytes?: number | null
}


function browserSourceDeviceId(): string {
  if (typeof window === 'undefined') return 'web:ssr-disabled'
  const key = 'taskly_source_device_id_v1'
  const existing = window.localStorage.getItem(key)?.trim()
  if (existing && existing.length >= 8) return existing
  const created = `web:${crypto.randomUUID()}`
  window.localStorage.setItem(key, created)
  return created
}

function browserSourceDeviceProof(): string {
  if (typeof window === 'undefined') return 'proof:ssr-disabled:0000000000000000000000000000000000000000'
  const key = 'taskly_source_device_proof_v1'
  const existing = window.localStorage.getItem(key)?.trim()
  if (existing && existing.length >= 40) return existing
  const created = `proof:${crypto.randomUUID()}:${crypto.randomUUID()}`
  window.localStorage.setItem(key, created)
  return created
}

async function invokeMedia(
  supabase: SupabaseClient,
  body: Record<string, unknown>,
): Promise<MediaActionResponse> {
  const { data, error } = await supabase.functions.invoke('message-media', { body })
  if (error) throw error
  const result = (data ?? {}) as MediaActionResponse
  if (result.error) throw new Error(result.error)
  return result
}

export async function uploadMessageAttachment(params: {
  supabase: SupabaseClient
  workspaceId: number
  channelId: number
  file: File
  replyToMessageId?: number | null
}): Promise<number> {
  const { supabase, workspaceId, channelId, file, replyToMessageId = null } = params
  const mimeType = file.type || 'application/octet-stream'

  const prepared = await invokeMedia(supabase, {
    action: 'prepare-upload',
    workspaceId,
    channelId,
    replyToMessageId,
    fileName: file.name || 'attachment',
    mimeType,
    sizeBytes: file.size,
    sourceDeviceId: browserSourceDeviceId(),
    sourceDeviceProof: browserSourceDeviceProof(),
  })

  if (!prepared.uploadId || !prepared.uploadUrl) {
    throw new Error('Taskly did not return an upload URL')
  }

  try {
    const upload = await fetch(prepared.uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': mimeType },
      body: file,
    })
    if (!upload.ok) throw new Error(`R2 upload failed (${upload.status})`)

    const finalized = await invokeMedia(supabase, {
      action: 'finalize-upload',
      uploadId: prepared.uploadId,
    })
    if (!finalized.messageId) throw new Error('Taskly did not create the message')
    return finalized.messageId
  } catch (error) {
    await invokeMedia(supabase, {
      action: 'abort-upload',
      uploadId: prepared.uploadId,
    }).catch(() => undefined)
    throw error
  }
}

export type OpenedMessageMedia = {
  available: true
  objectUrl: string
  name: string
  mimeType: string
  sizeBytes: number | null
  revoke: () => void
} | {
  available: false
}

export async function openMessageMedia(
  supabase: SupabaseClient,
  messageId: number,
): Promise<OpenedMessageMedia> {
  const ticket = await invokeMedia(supabase, {
    action: 'download',
    messageId,
  })

  if (!ticket.available || !ticket.url) return { available: false }

  const response = await fetch(ticket.url, { cache: 'no-store' })
  if (response.status === 404 || response.status === 410) return { available: false }
  if (!response.ok) throw new Error(`Attachment download failed (${response.status})`)

  const blob = await response.blob()
  const objectUrl = URL.createObjectURL(blob)
  let revoked = false

  return {
    available: true,
    objectUrl,
    name: ticket.name || 'attachment',
    mimeType: ticket.mimeType || blob.type || 'application/octet-stream',
    sizeBytes: ticket.sizeBytes ?? blob.size,
    revoke: () => {
      if (revoked) return
      revoked = true
      URL.revokeObjectURL(objectUrl)
    },
  }
}

export async function markMessageMediaUnavailable(
  supabase: SupabaseClient,
  messageId: number,
): Promise<void> {
  await invokeMedia(supabase, {
    action: 'mark-unavailable',
    messageId,
    reason: 'source_device_missing',
    sourceDeviceId: browserSourceDeviceId(),
    sourceDeviceProof: browserSourceDeviceProof(),
  })
}
