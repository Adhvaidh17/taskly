'use client'

import styles from './MessageAttachment.module.css'

export type UnavailableAttachmentKind = 'image' | 'video' | 'audio' | 'attachment'

export function attachmentKind(mimeType?: string | null): UnavailableAttachmentKind {
  const mime = mimeType || ''
  if (mime.startsWith('image/')) return 'image'
  if (mime.startsWith('video/')) return 'video'
  if (mime.startsWith('audio/')) return 'audio'
  return 'attachment'
}

export function unavailableAttachmentText(params: {
  mimeType?: string | null
  mine: boolean
  senderName: string
}): string {
  const kind = attachmentKind(params.mimeType)
  if (params.mine) return `This ${kind} is not available on this device.`
  return `This ${kind} is not available on ${params.senderName}'s device.`
}

export default function UnavailableAttachmentCard(props: {
  mimeType?: string | null
  mine: boolean
  senderName: string
}) {
  return (
    <div className={styles.unavailable} role="status">
      <div className={styles.unavailableIcon} aria-hidden="true">!</div>
      <div className={styles.unavailableText}>
        {unavailableAttachmentText(props)}
      </div>
    </div>
  )
}
