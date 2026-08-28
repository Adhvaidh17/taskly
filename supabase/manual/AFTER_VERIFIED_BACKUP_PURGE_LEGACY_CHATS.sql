-- DANGER / PHASE 2 ONLY.
--
-- DO NOT RUN THIS DURING INITIAL DEPLOYMENT.
-- Run only after:
-- 1. v6 local migration completed on test/current devices,
-- 2. message counts were verified,
-- 3. attachments that matter exist locally,
-- 4. a Google Drive encrypted backup completed successfully,
-- 5. restore was tested on another phone/test install.
--
-- This removes legacy permanent CHAT CONTENT.
-- It intentionally does not delete profiles, groups/workspaces, membership,
-- tasks, task details or normal task notifications.

begin;

-- Delete dependent chat-only records first.
delete from public.message_reactions;
delete from public.message_receipts;

-- task_suggestions are transient AI review records. Confirmed tasks remain.
-- Preserve rows only if your production schema has a separate reason to keep
-- them. For the privacy model requested for v6, chat-derived suggestions go.
delete from public.task_suggestions
where message_id is not null;

-- Finally delete permanent legacy message history.
delete from public.messages;

commit;

-- Do not DROP the tables yet. Keeping empty legacy tables during rollout
-- makes rollback/schema compatibility safer. Drop them in a later major
-- migration once all released clients are v6+.
