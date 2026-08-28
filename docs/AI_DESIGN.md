# AI task-detection design

## Where the AI runs

The Flutter app never calls OpenAI directly. After a message is stored, Flutter invokes the authenticated Supabase Edge Function `analyse-task-message`.

The Edge Function receives only:

- the new message;
- explicit `@mentions`;
- conversation member IDs/names/roles;
- up to 24 recent messages from that conversation;
- up to 20 relevant open tasks from that conversation;
- the current time and conversation type.

It does not send the user's entire database or unrelated chats.

## When a popup appears

There are two gates:

1. A local/server pre-filter checks for an addressee, mention or action/request wording.
2. The OpenAI model returns a strict structured decision with a confidence score.

Taskly stores a suggestion only when:

- `is_task` is true;
- confidence is at least `0.72`;
- the assignee is a real member of the conversation;
- an explicitly mentioned assignee matches the selected assignee;
- any target task is a real open task in that conversation.

The review card is visible only to the sender. Nothing becomes a task until the sender confirms it.

## Supported AI actions

- Create a task.
- Suggest edits to an existing task.
- Suggest a status change for an existing task.

Database permissions remain authoritative. The AI cannot bypass task ownership or workspace security.
