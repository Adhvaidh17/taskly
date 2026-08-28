import { createClient } from "@supabase/supabase-js";

type Json = Record<string, unknown>;
const HEADERS = { "content-type": "application/json; charset=utf-8" };

function json(status: number, body: Json) {
  return new Response(JSON.stringify(body), { status, headers: HEADERS });
}
function record(value: unknown): Json {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Json : {};
}
function int(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}
function b64url(bytes: Uint8Array): string {
  let value = "";
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
function pemBytes(pem: string): Uint8Array {
  const raw = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
}

let cached: { token: string; expiresAt: number; email: string; projectId: string } | null = null;
async function firebaseToken(account: Json): Promise<string> {
  const email = `${account.client_email ?? ""}`;
  const privateKey = `${account.private_key ?? ""}`;
  const projectId = `${account.project_id ?? ""}`;
  if (!email || !privateKey || !projectId) throw new Error("invalid_firebase_service_account");
  if (cached && cached.email === email && cached.projectId === projectId && cached.expiresAt > Date.now() + 60_000) {
    return cached.token;
  }
  const now = Math.floor(Date.now() / 1000);
  const enc = (value: Json) => b64url(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({
    iss: email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBytes(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const assertion = `${unsigned}.${b64url(new Uint8Array(signature))}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const payload = record(await response.json().catch(() => ({})));
  if (!response.ok || !payload.access_token) throw new Error(`firebase_oauth_${response.status}`);
  const token = `${payload.access_token}`;
  cached = { token, expiresAt: Date.now() + Math.max(300, Number(payload.expires_in ?? 3600)) * 1000, email, projectId };
  return token;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { ok: false, error: "method_not_allowed" });
  const secret = request.headers.get("x-taskly-push-secret") ?? "";
  let body: Json;
  try { body = record(await request.json()); } catch { return json(400, { ok: false, error: "invalid_json" }); }
  const notificationId = int(body.notification_id);
  if (!notificationId || secret.length < 32) return json(401, { ok: false, error: "invalid_request" });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceKey) return json(500, { ok: false, error: "supabase_not_configured" });
  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const verify = await service.rpc("taskly_verify_push_webhook_v42", { p_secret: secret });
  if (verify.error || verify.data !== true) return json(401, { ok: false, error: "invalid_secret" });

  const notificationResult = await service
    .from("notifications")
    .select("id,profile_id,type,title,body,workspace_id,channel_id,message_id,task_id,push_dispatched_at")
    .eq("id", notificationId)
    .maybeSingle();
  if (notificationResult.error) return json(500, { ok: false, error: notificationResult.error.message });
  const notification = record(notificationResult.data);
  if (!notification.id) return json(404, { ok: false, error: "notification_not_found" });
  if (notification.push_dispatched_at) return json(200, { ok: true, skipped: "already_dispatched" });

  const profileId = int(notification.profile_id);
  if (!profileId) return json(400, { ok: false, error: "invalid_recipient" });
  const tokensResult = await service
    .from("device_tokens")
    .select("token,platform")
    .eq("profile_id", profileId)
    .eq("is_enabled", true);
  if (tokensResult.error) return json(500, { ok: false, error: tokensResult.error.message });
  const tokens = tokensResult.data ?? [];
  if (tokens.length === 0) {
    await service.from("notifications").update({
      push_attempts: 1,
      push_last_error: "no_device_tokens",
    }).eq("id", notificationId);
    return json(200, { ok: true, delivered: 0, reason: "no_device_tokens" });
  }

  const serviceAccountRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
  if (!serviceAccountRaw) {
    await service.from("notifications").update({ push_attempts: 1, push_last_error: "firebase_not_configured" }).eq("id", notificationId);
    return json(200, { ok: false, delivered: 0, error: "firebase_not_configured" });
  }
  const account = record(JSON.parse(serviceAccountRaw));
  const projectId = `${account.project_id ?? ""}`;
  const accessToken = await firebaseToken(account);
  const title = `${notification.title ?? "Taskly"}`;
  const bodyText = `${notification.body ?? ""}`;
  const type = `${notification.type ?? "system"}`;
  const isTask = type.startsWith("task_") || notification.task_id != null;
  const data: Record<string, string> = {
    type,
    title,
    body: bodyText,
    notification_id: `${notificationId}`,
  };
  for (const key of ["workspace_id", "channel_id", "message_id", "task_id"] as const) {
    if (notification[key] != null) data[key] = `${notification[key]}`;
  }

  let delivered = 0;
  const invalidTokens: string[] = [];
  for (let offset = 0; offset < tokens.length; offset += 20) {
    await Promise.all(tokens.slice(offset, offset + 20).map(async (row: Json) => {
      const token = `${row.token ?? ""}`;
      if (!token) return;
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
        {
          method: "POST",
          headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body: bodyText },
              data,
              android: {
                priority: "high",
                notification: { channel_id: isTask ? "taskly_tasks" : "taskly_messages", sound: "default" },
              },
              apns: {
                headers: { "apns-priority": "10" },
                payload: { aps: { sound: "default", badge: 1, "content-available": 1 } },
              },
            },
          }),
        },
      );
      if (response.ok) { delivered += 1; return; }
      const failure = record(await response.json().catch(() => ({})));
      const error = record(failure.error);
      const details = Array.isArray(error.details) ? error.details : [];
      const codes = details.map((value) => `${record(value).errorCode ?? ""}`);
      if (codes.includes("UNREGISTERED") || codes.includes("SENDER_ID_MISMATCH")) invalidTokens.push(token);
    }));
  }
  if (invalidTokens.length > 0) await service.from("device_tokens").delete().in("token", invalidTokens);
  await service.from("notifications").update({
    push_dispatched_at: delivered > 0 ? new Date().toISOString() : null,
    push_attempts: 1,
    push_last_error: delivered > 0 ? null : "delivery_failed",
  }).eq("id", notificationId);
  return json(200, { ok: true, delivered, tokens: tokens.length, invalid_tokens_removed: invalidTokens.length });
});
