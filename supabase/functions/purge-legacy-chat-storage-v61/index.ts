import { createClient } from '@supabase/supabase-js';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-taskly-maintenance-secret',
};

type LegacyAttachmentRow = {
  id: number;
  attachment_bucket: string | null;
  attachment_path: string | null;
};

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'POST required' }, 405);

  const expectedSecret = Deno.env.get('TASKLY_MAINTENANCE_SECRET') ?? '';
  const suppliedSecret = request.headers.get('x-taskly-maintenance-secret') ?? '';
  if (!expectedSecret || suppliedSecret !== expectedSecret) return json({ error: 'Unauthorized' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceRoleKey) return json({ error: 'Missing Supabase service configuration' }, 500);

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Never remove server media until every active primary device has verified a
  // complete local copy. This is the backend safety gate for offline phones.
  const { data: readiness, error: readinessError } = await supabase.rpc('taskly_chat_purge_readiness_v63');
  if (readinessError) return json({ error: readinessError.message }, 500);
  if (readiness?.ready !== true) {
    return json({
      purged: false,
      reason: 'devices_not_migrated',
      required: readiness?.required ?? 0,
      ready_devices: readiness?.ready_devices ?? 0,
    }, 409);
  }

  let scanned = 0;
  let removed = 0;
  const failures: Array<{ bucket: string; path: string; error: string }> = [];
  let lastId = 0;
  const pageSize = 250;

  while (true) {
    const { data, error } = await supabase
      .from('messages')
      .select('id,attachment_bucket,attachment_path')
      .gt('id', lastId)
      .not('attachment_path', 'is', null)
      .order('id', { ascending: true })
      .limit(pageSize);
    if (error) return json({ error: error.message, scanned, removed, failures }, 500);

    const rows = (data ?? []) as LegacyAttachmentRow[];
    if (!rows.length) break;
    lastId = rows[rows.length - 1].id;
    scanned += rows.length;

    const byBucket = new Map<string, string[]>();
    for (const row of rows) {
      const bucket = (row.attachment_bucket ?? 'database').trim();
      const path = (row.attachment_path ?? '').trim();
      if (!bucket || !path) continue;
      byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
    }

    for (const [bucket, paths] of byBucket.entries()) {
      for (let start = 0; start < paths.length; start += 100) {
        const chunk = paths.slice(start, start + 100);
        const { data: deleted, error: deleteError } = await supabase.storage.from(bucket).remove(chunk);
        if (deleteError) {
          for (const path of chunk) failures.push({ bucket, path, error: deleteError.message });
          continue;
        }
        removed += deleted?.length ?? chunk.length;
      }
    }
  }

  if (failures.length) {
    return json({ purged: false, reason: 'media_cleanup_failed', scanned, removed, failures }, 500);
  }

  const { data: purgeResult, error: purgeError } = await supabase.rpc('taskly_finalize_local_chat_purge_v63');
  if (purgeError) return json({ error: purgeError.message, scanned, removed }, 500);

  return json({ ok: purgeResult?.purged === true, ...purgeResult, scanned, removed });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
