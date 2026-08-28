'use client'

import { useEffect, useMemo, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { openMessageMedia, type OpenedMessageMedia } from '@/lib/messageMedia'
import UnavailableAttachmentCard from './UnavailableAttachmentCard'
import styles from './MessageAttachment.module.css'

type MessageAttachmentModel = {
  id: number
  attachment_name?: string | null
  attachment_mime_type?: string | null
  attachment_size_bytes?: number | null
  attachment_status?: string | null
  attachment_bucket?: string | null
  sender?: { id?: number; name?: string } | null
  sender_name?: string | null
}

function senderName(message: MessageAttachmentModel): string {
  return message.sender?.name || message.sender_name || 'the sender'
}

function prettyBytes(value?: number | null): string {
  if (!value || value < 1) return ''
  if (value < 1024) return `${value} B`
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`
  return `${(value / 1024 / 1024).toFixed(1)} MB`
}

export default function MessageAttachment(props: {
  supabase: SupabaseClient
  message: MessageAttachmentModel
  mine: boolean
}) {
  const { supabase, message, mine } = props
  const [media, setMedia] = useState<OpenedMessageMedia | null>(null)
  const [loading, setLoading] = useState(false)
  const [runtimeUnavailable, setRuntimeUnavailable] = useState(false)
  const mime = message.attachment_mime_type || 'application/octet-stream'
  const unavailable =
    message.attachment_status === 'unavailable' ||
    message.attachment_bucket?.startsWith('unavailable') ||
    runtimeUnavailable

  const kind = useMemo(() => {
    if (mime.startsWith('image/')) return 'Photo'
    if (mime.startsWith('video/')) return 'Video'
    if (mime.startsWith('audio/')) return 'Audio'
    return 'Attachment'
  }, [mime])

  useEffect(() => {
    // Realtime DB update changed this message to unavailable: immediately drop
    // the browser blob, even if the preview is currently open.
    if (message.attachment_status === 'unavailable' || message.attachment_bucket?.startsWith('unavailable')) {
      setMedia((old) => {
        if (old?.available) old.revoke()
        return null
      })
      setRuntimeUnavailable(true)
    }
  }, [message.attachment_status, message.attachment_bucket])

  useEffect(() => () => {
    if (media?.available) media.revoke()
  }, [media])

  async function open() {
    if (loading || unavailable) return
    setLoading(true)
    try {
      const opened = await openMessageMedia(supabase, message.id)
      if (!opened.available) {
        setRuntimeUnavailable(true)
        return
      }
      setMedia(opened)
    } finally {
      setLoading(false)
    }
  }

  function close() {
    if (media?.available) media.revoke()
    setMedia(null)
  }

  if (unavailable) {
    return (
      <UnavailableAttachmentCard
        mimeType={mime}
        mine={mine}
        senderName={senderName(message)}
      />
    )
  }

  return (
    <>
      <button type="button" className={styles.card} onClick={open} disabled={loading}>
        <span className={styles.icon} aria-hidden="true">
          {mime.startsWith('image/') ? '▧' : mime.startsWith('video/') ? '▶' : mime.startsWith('audio/') ? '♪' : '↗'}
        </span>
        <span className={styles.meta}>
          <strong>{message.attachment_name || kind}</strong>
          <small>{loading ? 'Loading…' : `${kind}${prettyBytes(message.attachment_size_bytes) ? ` · ${prettyBytes(message.attachment_size_bytes)}` : ''}`}</small>
        </span>
      </button>

      {media?.available && (
        <div className={styles.viewerBackdrop} onMouseDown={(e) => e.target === e.currentTarget && close()}>
          <div className={styles.viewer} role="dialog" aria-modal="true" aria-label={media.name}>
            <div className={styles.viewerTop}>
              <div className={styles.viewerName}>{media.name}</div>
              <button type="button" className={styles.close} onClick={close} aria-label="Close">×</button>
            </div>
            <div className={styles.viewerBody}>
              {media.mimeType.startsWith('image/') ? (
                <img src={media.objectUrl} alt={media.name} className={styles.previewImage} />
              ) : media.mimeType.startsWith('video/') ? (
                <video src={media.objectUrl} controls autoPlay className={styles.previewVideo} />
              ) : media.mimeType.startsWith('audio/') ? (
                <audio src={media.objectUrl} controls autoPlay className={styles.previewAudio} />
              ) : media.mimeType === 'application/pdf' ? (
                <iframe src={media.objectUrl} title={media.name} className={styles.previewFrame} />
              ) : (
                <div className={styles.filePreview}>
                  <div className={styles.fileName}>{media.name}</div>
                  <a href={media.objectUrl} download={media.name} className={styles.openButton}>Open / save file</a>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  )
}
