import { createClient } from "@supabase/supabase-js";

const headers = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json; charset=utf-8",
};

type Json = Record<string, unknown>;

function json(status: number, body: Json) {
  return new Response(JSON.stringify(body), { status, headers });
}

function asRecord(value: unknown): Json {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Json
    : {};
}

function asInt(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function b64url(bytes: Uint8Array): string {
  let value = "";
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function pemToBytes(pem: string): Uint8Array {
  const value = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

let cachedFirebaseToken: {
  token: string;
  expiresAtMs: number;
  clientEmail: string;
  projectId: string;
} | null = null;

async function firebaseAccessToken(account: Json): Promise<string> {
  const clientEmail = `${account.client_email ?? ""}`;
  const privateKey = `${account.private_key ?? ""}`;
  const projectId = `${account.project_id ?? ""}`;
  if (!clientEmail || !privateKey || !projectId) {
    throw new Error("Invalid Firebase service account");
  }
  if (
    cachedFirebaseToken !== null &&
    cachedFirebaseToken.clientEmail === clientEmail &&
    cachedFirebaseToken.projectId === projectId &&
    cachedFirebaseToken.expiresAtMs > Date.now() + 60_000
  ) {
    return cachedFirebaseToken.token;
  }

  const now = Math.floor(Date.now() / 1000);
  const encode = (value: Json) => b64url(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${b64url(new Uint8Array(signature))}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const payload = asRecord(await response.json().catch(() => ({})));
  if (!response.ok || !payload.access_token) {
    throw new Error(`Firebase OAuth failed: ${response.status}`);
  }
  const token = `${payload.access_token}`;
  const expiresInSeconds = Math.max(300, Number(payload.expires_in ?? 3600));
  cachedFirebaseToken = {
    token,
    expiresAtMs: Date.now() + expiresInSeconds * 1000,
    clientEmail,
    projectId,
  };
  return token;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json(405, { delivered: 0, error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authorization = request.headers.get("authorization") ?? "";
  if (!supabaseUrl || !serviceRole || !authorization.toLowerCase().startsWith("bearer ")) {
    return json(401, { delivered: 0, error: "not_authenticated" });
  }

  let body: Json;
  try {
    body = asRecord(await request.json());
  } catch {
    return json(400, { delivered: 0, error: "invalid_json" });
  }
  const messageId = asInt(body.message_id);
  if (messageId === null) return json(400, { delivered: 0, error: "invalid_message_id" });

  const service = createClient(supabaseUrl, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const jwt = authorization.replace(/^Bearer\s+/i, "");
  const userResult = await service.auth.getUser(jwt);
  const user = userResult.data.user;
  if (!user) return json(401, { delivered: 0, error: "invalid_session" });

  const profileResult = await service
    .from("profiles")
    .select("id,name")
    .eq("auth_user_id", user.id)
    .maybeSingle();
  const profile = asRecord(profileResult.data);
  const senderId = asInt(profile.id);
  if (senderId === null) return json(404, { delivered: 0, error: "profile_not_found" });

  const messageResult = await service
    .from("messages")
    .select("id,workspace_id,channel_id,sender_profile_id,body,type,attachment_name,shared_contact_name,channel:channels!messages_channel_id_fkey(name,type)")
    .eq("id", messageId)
    .maybeSingle();
  if (messageResult.error) return json(500, { delivered: 0, error: messageResult.error.message });
  const message = asRecord(messageResult.data);
  if (asInt(message.sender_profile_id) !== senderId) {
    return json(403, { delivered: 0, error: "message_not_owned" });
  }

  const channel = asRecord(message.channel);
  const channelName = `${channel.name ?? "Taskly"}`;
  const messageType = `${message.type ?? "text"}`;
  const preview = messageType === "contact"
    ? `Contact: ${message.shared_contact_name ?? message.body ?? "Shared contact"}`
    : messageType === "image"
    ? "📷 Photo"
    : message.attachment_name
    ? `📎 ${message.attachment_name}`
    : `${message.body ?? "New message"}`.trim().slice(0, 180);
  const title = channel.type === "direct"
    ? `${profile.name ?? "Taskly user"}`
    : `${profile.name ?? "Taskly user"} · ${channelName}`;

  const membersResult = await service
    .from("channel_members")
    .select("profile_id")
    .eq("channel_id", asInt(message.channel_id)!);
  if (membersResult.error) return json(500, { delivered: 0, error: membersResult.error.message });
  const recipientIds = (membersResult.data ?? [])
    .map((item: Json) => asInt(item.profile_id))
    .filter((id: number | null): id is number => id !== null && id !== senderId);
  if (recipientIds.length === 0) return json(200, { delivered: 0, recipients: 0 });

  const existingResult = await service
    .from("notifications")
    .select("profile_id")
    .eq("message_id", messageId)
    .in("profile_id", recipientIds);
  if (existingResult.error) {
    return json(500, { delivered: 0, error: existingResult.error.message });
  }
  const existingProfiles = new Set(
    (existingResult.data ?? [])
      .map((item: Json) => asInt(item.profile_id))
      .filter((id: number | null): id is number => id !== null),
  );
  const notificationRows = recipientIds
    .filter((profileId: number) => !existingProfiles.has(profileId))
    .map((profileId: number) => ({
      profile_id: profileId,
      actor_profile_id: senderId,
      workspace_id: asInt(message.workspace_id),
      channel_id: asInt(message.channel_id),
      message_id: messageId,
      type: "message",
      title,
      body: preview,
      is_read: false,
    }));
  if (notificationRows.length > 0) {
    const notificationInsert = await service
      .from("notifications")
      .insert(notificationRows);
    if (notificationInsert.error) {
      console.error("Notification insert failed", notificationInsert.error.message);
    }
  }

  const tokensResult = await service
    .from("device_tokens")
    .select("token,profile_id,platform")
    .in("profile_id", recipientIds)
    .eq("is_enabled", true);
  if (tokensResult.error) {
    return json(500, { delivered: 0, error: tokensResult.error.message });
  }
  const tokens = tokensResult.data ?? [];
  if (tokens.length === 0) return json(200, { delivered: 0, recipients: recipientIds.length, push: "no_tokens" });

  const rawServiceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
  if (!rawServiceAccount) {
    return json(200, { delivered: 0, recipients: recipientIds.length, push: "firebase_not_configured" });
  }

  let account: Json;
  try {
    account = asRecord(JSON.parse(rawServiceAccount));
  } catch {
    return json(200, { delivered: 0, recipients: recipientIds.length, push: "invalid_firebase_secret" });
  }
  const projectId = `${account.project_id ?? ""}`;
  if (!projectId) return json(200, { delivered: 0, recipients: recipientIds.length, push: "missing_project_id" });

  const accessToken = await firebaseAccessToken(account);
  const invalidTokens = new Set<string>();
  let delivered = 0;
  let failed = 0;

  async function sendPush(row: Json): Promise<void> {
    const token = `${row.token ?? ""}`;
    if (!token) return;
    const pushResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body: preview },
            data: {
              type: "message",
              title,
              body: preview,
              message_id: `${messageId}`,
              channel_id: `${message.channel_id}`,
              workspace_id: `${message.workspace_id}`,
              conversation_name: channelName,
            },
            android: {
              priority: "high",
              notification: { channel_id: "taskly_messages", sound: "default" },
            },
            apns: {
              headers: { "apns-priority": "10" },
              payload: { aps: { sound: "default", "content-available": 1 } },
            },
          },
        }),
      },
    );
    if (pushResponse.ok) {
      delivered += 1;
      return;
    }

    failed += 1;
    const failure = asRecord(await pushResponse.json().catch(() => ({})));
    const firebaseError = asRecord(failure.error);
    const details = Array.isArray(firebaseError.details) ? firebaseError.details : [];
    const errorCodes = details.map((value) => `${asRecord(value).errorCode ?? ""}`);
    if (errorCodes.includes("UNREGISTERED") || errorCodes.includes("SENDER_ID_MISMATCH")) {
      invalidTokens.add(token);
    }
    console.error(
      "FCM delivery failed",
      JSON.stringify({ status: pushResponse.status, error_codes: errorCodes }),
    );
  }

  // Small batches keep group notifications fast without overwhelming FCM.
  for (let offset = 0; offset < tokens.length; offset += 10) {
    await Promise.all(tokens.slice(offset, offset + 10).map((row: Json) => sendPush(row)));
  }
  if (invalidTokens.size > 0) {
    await service.from("device_tokens").delete().in("token", [...invalidTokens]);
  }
  return json(200, {
    delivered,
    failed,
    recipients: recipientIds.length,
    tokens: tokens.length,
    invalid_tokens_removed: invalidTokens.size,
  });
});
