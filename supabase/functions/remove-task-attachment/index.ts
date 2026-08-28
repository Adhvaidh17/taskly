import { createClient } from "@supabase/supabase-js";

const headers = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json; charset=utf-8",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ ok: false, error: "method_not_allowed" }), { status: 405, headers });
  }

  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return new Response(JSON.stringify({ ok: false, error: "not_authenticated" }), { status: 401, headers });
  }

  let payload: Record<string, unknown> = {};
  try {
    const value = await request.json();
    if (value && typeof value === "object" && !Array.isArray(value)) payload = value as Record<string, unknown>;
  } catch (_) {
    return new Response(JSON.stringify({ ok: false, error: "invalid_json" }), { status: 400, headers });
  }
  const attachmentId = Number(payload.attachment_id);
  if (!Number.isFinite(attachmentId) || attachmentId <= 0) {
    return new Response(JSON.stringify({ ok: false, error: "invalid_attachment_id" }), { status: 400, headers });
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_KEY") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !anon || !serviceRole) {
    return new Response(JSON.stringify({ ok: false, error: "server_not_configured" }), { status: 500, headers });
  }

  const userClient = createClient(url, anon, {
    global: { headers: { authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const service = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // The RPC performs all workspace/uploader/creator/admin authorization and
  // creates the tombstone. Only after that succeeds does service-role storage
  // cleanup run, so an unauthorized caller can never delete an object.
  const tombstone = await userClient.rpc("taskly_remove_task_attachment_v43", {
    p_attachment_id: Math.trunc(attachmentId),
  });
  if (tombstone.error) {
    return new Response(
      JSON.stringify({ ok: false, error: tombstone.error.message }),
      { status: 403, headers },
    );
  }

  const row = await service
    .from("attachments")
    .select("bucket,path")
    .eq("id", Math.trunc(attachmentId))
    .single();
  if (!row.error && row.data) {
    const bucket = `${row.data.bucket ?? ""}`.trim();
    const path = `${row.data.path ?? ""}`.trim();
    if (bucket && path) {
      const removal = await service.storage.from(bucket).remove([path]);
      if (removal.error) console.warn("Taskly attachment storage cleanup", removal.error.message);
    }
  }

  return new Response(JSON.stringify({ ok: true, attachment_id: Math.trunc(attachmentId) }), { status: 200, headers });
});
