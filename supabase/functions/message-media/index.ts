import { createClient } from '@supabase/supabase-js'
import {
  CopyObjectCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3'
import { getSignedUrl } from '@aws-sdk/s3-request-presigner'

type Json = Record<string, unknown>

const env = (name: string): string => {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new Error(`Missing environment variable: ${name}`)
  return value
}

const SUPABASE_URL = env('SUPABASE_URL')
const SERVICE_ROLE_KEY = (() => {
  const modern = Deno.env.get('SUPABASE_SECRET_KEYS')?.trim()
  if (modern) {
    const parsed = JSON.parse(modern) as Record<string, string>
    if (parsed.default) return parsed.default
  }
  return env('SUPABASE_SERVICE_ROLE_KEY')
})()
const PUBLISHABLE_KEY = (() => {
  const modern = Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')?.trim()
  if (modern) {
    const parsed = JSON.parse(modern) as Record<string, string>
    if (parsed.default) return parsed.default
  }
  return env('SUPABASE_ANON_KEY')
})()
const R2_ACCOUNT_ID = env('R2_ACCOUNT_ID')
const R2_ACCESS_KEY_ID = env('R2_ACCESS_KEY_ID')
const R2_SECRET_ACCESS_KEY = env('R2_SECRET_ACCESS_KEY')
const R2_BUCKET = env('R2_BUCKET')
const MAX_BYTES = Number(Deno.env.get('TASKLY_MAX_ATTACHMENT_BYTES') ?? 104857600)
const ALLOWED_ORIGINS = (Deno.env.get('TASKLY_ALLOWED_ORIGINS') ?? '')
  .split(',')
  .map((v) => v.trim())
  .filter(Boolean)

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const r2 = new S3Client({
  region: 'auto',
  endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: R2_ACCESS_KEY_ID,
    secretAccessKey: R2_SECRET_ACCESS_KEY,
  },
})

function cors(req: Request): HeadersInit {
  const origin = req.headers.get('origin') ?? ''
  const allowOrigin = ALLOWED_ORIGINS.length === 0
    ? '*'
    : ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]
  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

function json(req: Request, body: Json, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors(req),
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  })
}

function safeDeviceId(input: unknown): string {
  const value = String(input ?? '').trim().slice(0, 120)
  if (!/^[A-Za-z0-9:_\-.]{8,120}$/.test(value)) throw new Error('Invalid sourceDeviceId')
  return value
}

function safeDeviceProof(input: unknown): string {
  const value = String(input ?? '').trim()
  if (value.length < 40 || value.length > 220 || !/^[A-Za-z0-9:_\-.]+$/.test(value)) {
    throw new Error('Invalid sourceDeviceProof')
  }
  return value
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function safeFileName(input: unknown): string {
  const raw = String(input ?? 'attachment').trim().slice(0, 180)
  const cleaned = raw.replace(/[\\/\u0000-\u001f\u007f]+/g, '_')
  return cleaned || 'attachment'
}

function int(input: unknown, name: string): number {
  const value = Number(input)
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error(`Invalid ${name}`)
  return value
}

async function caller(req: Request) {
  const authHeader = req.headers.get('authorization') ?? ''
  const token = authHeader.replace(/^Bearer\s+/i, '').trim()
  if (!token) throw new Error('Unauthenticated')

  const { data: authData, error: authError } = await admin.auth.getUser(token)
  if (authError || !authData.user) throw new Error('Unauthenticated')

  const { data: profile, error: profileError } = await admin
    .from('profiles')
    .select('id,name')
    .eq('auth_user_id', authData.user.id)
    .single()
  if (profileError || !profile) throw new Error('Profile not found')

  return { token, user: authData.user, profile }
}

function userClient(token: string) {
  // Secret key is used only as the gateway API key. The caller JWT remains the
  // Authorization bearer, so Postgres sees auth.uid()/authenticated and RLS is
  // still enforced for user-owned writes.
  return createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

async function assertChannelMember(profileId: number, workspaceId: number, channelId: number) {
  const { data: channel, error: channelError } = await admin
    .from('channels')
    .select('id,workspace_id')
    .eq('id', channelId)
    .single()
  if (channelError || !channel || Number(channel.workspace_id) !== workspaceId) {
    throw new Error('Conversation not found')
  }

  const { data: membership, error: memberError } = await admin
    .from('channel_members')
    .select('profile_id')
    .eq('channel_id', channelId)
    .eq('profile_id', profileId)
    .maybeSingle()
  if (memberError || !membership) throw new Error('Not a conversation member')
}

async function prepareUpload(req: Request, body: Json) {
  const { profile } = await caller(req)
  const workspaceId = int(body.workspaceId, 'workspaceId')
  const channelId = int(body.channelId, 'channelId')
  const sizeBytes = int(body.sizeBytes, 'sizeBytes')
  const replyToMessageId = body.replyToMessageId == null
    ? null
    : int(body.replyToMessageId, 'replyToMessageId')
  const fileName = safeFileName(body.fileName)
  const sourceDeviceId = safeDeviceId(body.sourceDeviceId)
  const sourceDeviceProof = safeDeviceProof(body.sourceDeviceProof)
  const sourceDeviceProofHash = await sha256Hex(sourceDeviceProof)
  const mimeType = String(body.mimeType ?? 'application/octet-stream').trim().slice(0, 160)

  if (sizeBytes > MAX_BYTES) throw new Error(`Attachment exceeds ${MAX_BYTES} bytes`)
  await assertChannelMember(Number(profile.id), workspaceId, channelId)

  if (replyToMessageId != null) {
    const { data: reply } = await admin
      .from('messages')
      .select('id,channel_id')
      .eq('id', replyToMessageId)
      .maybeSingle()
    if (!reply || Number(reply.channel_id) !== channelId) throw new Error('Reply message not found')
  }

  // Keep the tiny upload-intent table bounded without needing a scheduler.
  // Finalized/expired intents older than a day are safe to discard.
  const cleanupBefore = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
  await admin.from('message_media_uploads').delete().lt('expires_at', cleanupBefore)

  const uploadId = crypto.randomUUID()
  const objectId = crypto.randomUUID()
  const tempKey = `tmp/${profile.id}/${uploadId}/${fileName}`
  const finalKey = `messages/${workspaceId}/${channelId}/${profile.id}/${objectId}/${fileName}`
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString()

  const { error: insertError } = await admin.from('message_media_uploads').insert({
    id: uploadId,
    profile_id: profile.id,
    workspace_id: workspaceId,
    channel_id: channelId,
    reply_to_message_id: replyToMessageId,
    temp_object_key: tempKey,
    final_object_key: finalKey,
    original_name: fileName,
    source_device_id: sourceDeviceId,
    source_device_proof_hash: sourceDeviceProofHash,
    mime_type: mimeType,
    size_bytes: sizeBytes,
    expires_at: expiresAt,
  })
  if (insertError) throw insertError

  const uploadUrl = await getSignedUrl(
    r2,
    new PutObjectCommand({
      Bucket: R2_BUCKET,
      Key: tempKey,
      ContentType: mimeType,
    }),
    { expiresIn: 10 * 60, signableHeaders: new Set(['content-type']) },
  )

  return json(req, { ok: true, uploadId, uploadUrl, expiresAt })
}

async function finalizeUpload(req: Request, body: Json) {
  const { token, profile } = await caller(req)
  const uploadId = String(body.uploadId ?? '').trim()
  if (!uploadId) throw new Error('Missing uploadId')

  const { data: pending, error: pendingError } = await admin
    .from('message_media_uploads')
    .select('*')
    .eq('id', uploadId)
    .eq('profile_id', profile.id)
    .maybeSingle()
  if (pendingError || !pending) throw new Error('Upload intent not found')
  if (pending.finalized_at && pending.message_id) {
    return json(req, { ok: true, messageId: pending.message_id })
  }
  if (pending.finalized_at) throw new Error('Upload already finalized')
  if (Date.parse(pending.expires_at) < Date.now()) throw new Error('Upload intent expired')

  await assertChannelMember(Number(profile.id), Number(pending.workspace_id), Number(pending.channel_id))

  const head = await r2.send(new HeadObjectCommand({
    Bucket: R2_BUCKET,
    Key: pending.temp_object_key,
  }))
  if (Number(head.ContentLength ?? -1) !== Number(pending.size_bytes)) {
    await r2.send(new DeleteObjectCommand({ Bucket: R2_BUCKET, Key: pending.temp_object_key }))
    throw new Error('Uploaded file size does not match')
  }

  await r2.send(new CopyObjectCommand({
    Bucket: R2_BUCKET,
    Key: pending.final_object_key,
    CopySource: `${R2_BUCKET}/${encodeURIComponent(pending.temp_object_key).replaceAll('%2F', '/')}`,
    ContentType: pending.mime_type,
    MetadataDirective: 'REPLACE',
  }))
  await r2.send(new DeleteObjectCommand({ Bucket: R2_BUCKET, Key: pending.temp_object_key }))

  const type = String(pending.mime_type).startsWith('image/') ? 'image' : 'file'
  const db = userClient(token)
  const { data: message, error: messageError } = await db
    .from('messages')
    .insert({
      workspace_id: pending.workspace_id,
      channel_id: pending.channel_id,
      sender_profile_id: profile.id,
      body: pending.original_name,
      type,
      reply_to_message_id: pending.reply_to_message_id,
      attachment_bucket: `r2@${pending.source_device_id}`,
      attachment_path: pending.final_object_key,
      attachment_object_key: pending.final_object_key,
      attachment_source_device_id: pending.source_device_id,
      attachment_source_device_proof_hash: pending.source_device_proof_hash,
      attachment_name: pending.original_name,
      attachment_mime_type: pending.mime_type,
      attachment_size_bytes: pending.size_bytes,
      attachment_status: 'available',
    })
    .select('id')
    .single()

  if (messageError || !message) {
    await r2.send(new DeleteObjectCommand({ Bucket: R2_BUCKET, Key: pending.final_object_key }))
    throw messageError ?? new Error('Could not create message')
  }

  await admin
    .from('message_media_uploads')
    .update({ finalized_at: new Date().toISOString(), message_id: message.id })
    .eq('id', uploadId)

  return json(req, { ok: true, messageId: message.id })
}

async function download(req: Request, body: Json) {
  const { profile } = await caller(req)
  const messageId = int(body.messageId, 'messageId')

  const { data: message, error } = await admin
    .from('messages')
    .select('id,channel_id,attachment_status,attachment_object_key,attachment_source_device_id,attachment_bucket,attachment_path,attachment_name,attachment_mime_type,attachment_size_bytes')
    .eq('id', messageId)
    .maybeSingle()
  if (error || !message) throw new Error('Message not found')

  const { data: membership } = await admin
    .from('channel_members')
    .select('profile_id')
    .eq('channel_id', message.channel_id)
    .eq('profile_id', profile.id)
    .maybeSingle()
  if (!membership) throw new Error('Not a conversation member')

  if (message.attachment_status === 'unavailable') {
    return json(req, { ok: true, available: false })
  }

  // New R2 attachments.
  if (message.attachment_object_key) {
    try {
      await r2.send(new HeadObjectCommand({
        Bucket: R2_BUCKET,
        Key: message.attachment_object_key,
      }))
    } catch {
      await admin.from('messages').update({
        attachment_status: 'unavailable',
        attachment_object_key: null,
        attachment_bucket: message.attachment_source_device_id
          ? `unavailable@${message.attachment_source_device_id}`
          : 'unavailable',
        attachment_path: null,
        attachment_unavailable_at: new Date().toISOString(),
        attachment_unavailable_reason: 'remote_object_missing',
      }).eq('id', messageId)
      return json(req, { ok: true, available: false })
    }

    const url = await getSignedUrl(
      r2,
      new GetObjectCommand({ Bucket: R2_BUCKET, Key: message.attachment_object_key }),
      { expiresIn: 90 },
    )
    return json(req, {
      ok: true,
      available: true,
      url,
      name: message.attachment_name,
      mimeType: message.attachment_mime_type,
      sizeBytes: message.attachment_size_bytes,
    })
  }

  // Backward-compatible bridge for existing Supabase Storage attachments.
  if (message.attachment_bucket && message.attachment_path && message.attachment_bucket !== 'r2' && !String(message.attachment_bucket).startsWith('r2@') && !String(message.attachment_bucket).startsWith('unavailable')) {
    const { data, error: signedError } = await admin.storage
      .from(message.attachment_bucket)
      .createSignedUrl(message.attachment_path, 90)
    if (signedError || !data?.signedUrl) {
      return json(req, { ok: true, available: false })
    }
    return json(req, {
      ok: true,
      available: true,
      url: data.signedUrl,
      name: message.attachment_name,
      mimeType: message.attachment_mime_type,
      sizeBytes: message.attachment_size_bytes,
    })
  }

  return json(req, { ok: true, available: false })
}

async function markUnavailable(req: Request, body: Json) {
  const { token, profile } = await caller(req)
  const messageId = int(body.messageId, 'messageId')

  const { data: message, error } = await admin
    .from('messages')
    .select('id,sender_profile_id,attachment_status,attachment_object_key,attachment_source_device_id,attachment_source_device_proof_hash,attachment_bucket,attachment_path')
    .eq('id', messageId)
    .maybeSingle()
  if (error || !message) throw new Error('Message not found')
  if (Number(message.sender_profile_id) !== Number(profile.id)) {
    throw new Error('Only the sender can mark this attachment unavailable')
  }
  const sourceDeviceId = safeDeviceId(body.sourceDeviceId)
  const sourceDeviceProof = safeDeviceProof(body.sourceDeviceProof)
  const sourceDeviceProofHash = await sha256Hex(sourceDeviceProof)
  if (message.attachment_source_device_id && message.attachment_source_device_id !== sourceDeviceId) {
    throw new Error('Only the source device can mark this attachment unavailable')
  }
  if (message.attachment_source_device_proof_hash && message.attachment_source_device_proof_hash !== sourceDeviceProofHash) {
    throw new Error('Invalid source-device proof')
  }
  if (message.attachment_status === 'unavailable') {
    return json(req, { ok: true, alreadyUnavailable: true })
  }

  if (message.attachment_object_key) {
    await r2.send(new DeleteObjectCommand({
      Bucket: R2_BUCKET,
      Key: message.attachment_object_key,
    }))
  } else if (message.attachment_bucket && message.attachment_path && message.attachment_bucket !== 'r2' && !String(message.attachment_bucket).startsWith('r2@') && !String(message.attachment_bucket).startsWith('unavailable')) {
    await admin.storage.from(message.attachment_bucket).remove([message.attachment_path])
  }

  // Use the caller JWT so the sender + source-device RPC remains an independent safety check.
  const db = userClient(token)
  const { error: rpcError } = await db.rpc('taskly_mark_attachment_unavailable_v51', {
    p_message_id: messageId,
    p_source_device_id: sourceDeviceId,
    p_source_device_proof: sourceDeviceProof,
    p_reason: String(body.reason ?? 'source_device_missing').slice(0, 80),
  })
  if (rpcError) throw rpcError

  return json(req, { ok: true })
}

async function abortUpload(req: Request, body: Json) {
  const { profile } = await caller(req)
  const uploadId = String(body.uploadId ?? '').trim()
  if (!uploadId) return json(req, { ok: true })

  const { data: pending } = await admin
    .from('message_media_uploads')
    .select('id,temp_object_key,finalized_at')
    .eq('id', uploadId)
    .eq('profile_id', profile.id)
    .maybeSingle()
  if (!pending || pending.finalized_at) return json(req, { ok: true })

  try {
    await r2.send(new DeleteObjectCommand({ Bucket: R2_BUCKET, Key: pending.temp_object_key }))
  } catch { /* object may never have been uploaded */ }
  await admin.from('message_media_uploads').delete().eq('id', uploadId).eq('profile_id', profile.id)
  return json(req, { ok: true })
}

export default {
  async fetch(req: Request): Promise<Response> {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(req) })
    if (req.method !== 'POST') return json(req, { error: 'Method not allowed' }, 405)

    try {
      const body = await req.json() as Json
      const action = String(body.action ?? '')
      if (action === 'prepare-upload') return await prepareUpload(req, body)
      if (action === 'finalize-upload') return await finalizeUpload(req, body)
      if (action === 'abort-upload') return await abortUpload(req, body)
      if (action === 'download') return await download(req, body)
      if (action === 'mark-unavailable') return await markUnavailable(req, body)
      return json(req, { error: 'Unknown action' }, 400)
    } catch (error) {
      console.error('TASKLY_MESSAGE_MEDIA_ERROR', error)
      const message = error instanceof Error ? error.message : 'Media request failed'
      const status = message === 'Unauthenticated' ? 401
        : message.includes('member') || message.includes('sender') ? 403
        : 400
      return json(req, { error: message }, status)
    }
  },
}
