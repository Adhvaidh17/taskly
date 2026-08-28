import { createClient } from "@supabase/supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type TaskDetection = {
  is_task: boolean;
  confidence: number;
  action_type: "create" | "update" | "status_change";
  title: string;
  description: string;
  assignee_profile_id: number;
  deadline_iso: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization) {
      return json({ error: "Unauthorized" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey =
      Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
      "";
    const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    const model =
      Deno.env.get("OPENAI_TASK_MODEL") ??
      Deno.env.get("OPENAI_TASK_FAST_MODEL") ??
      "gpt-5-mini";

    if (!supabaseUrl || !anonKey || !openAiKey) {
      return json({ error: "Task analysis is not configured." }, 503);
    }

    const client = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });

    const { data: auth, error: authError } = await client.auth.getUser();
    if (authError || !auth.user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const body = await req.json();
    const text = String(body?.text ?? "").trim().slice(0, 6000);
    const workspaceId = Number(body?.workspace_id ?? 0);
    const channelId = Number(body?.channel_id ?? 0);
    const timezoneOffsetMinutes = Number(
      body?.timezone_offset_minutes ?? 0,
    );

    if (!text || !workspaceId || !channelId) {
      return json({ is_task: false, confidence: 0 }, 200);
    }

    const { data: profile, error: profileError } = await client
      .from("profiles")
      .select("id,name")
      .eq("auth_user_id", auth.user.id)
      .single();
    if (profileError || !profile) {
      return json({ error: "Profile not found." }, 403);
    }

    const { data: membership } = await client
      .from("channel_members")
      .select("profile_id")
      .eq("channel_id", channelId)
      .eq("profile_id", profile.id)
      .maybeSingle();
    if (!membership) {
      return json({ error: "Not a channel member." }, 403);
    }

    const { data: memberRows } = await client
      .from("channel_members")
      .select("profile_id,profiles!channel_members_profile_id_fkey(id,name)")
      .eq("channel_id", channelId)
      .limit(100);

    const members = (memberRows ?? []).map((row: any) => ({
      id: Number(row.profile_id),
      name: String(row.profiles?.name ?? ""),
    }));

    // Task rows are allowed server-side by the requested architecture.
    // They give the classifier enough context for "mark that as done" style
    // updates without storing chat history.
    const { data: taskRows } = await client
      .from("tasks")
      .select("id,title,status,assignee_profile_id,due_at")
      .eq("workspace_id", workspaceId)
      .neq("status", "completed")
      .order("updated_at", { ascending: false })
      .limit(30);

    const inputContext = {
      sender: { id: Number(profile.id), name: String(profile.name ?? "") },
      members,
      open_tasks: taskRows ?? [],
      timezone_offset_minutes: timezoneOffsetMinutes,
      message: text,
    };

    const schema = {
      type: "object",
      properties: {
        is_task: { type: "boolean" },
        confidence: { type: "number", minimum: 0, maximum: 1 },
        action_type: {
          type: "string",
          enum: ["create", "update", "status_change"],
        },
        title: { type: "string", maxLength: 160 },
        description: { type: "string", maxLength: 1000 },
        assignee_profile_id: { type: "integer", minimum: 0 },
        deadline_iso: { type: "string", maxLength: 64 },
      },
      required: [
        "is_task",
        "confidence",
        "action_type",
        "title",
        "description",
        "assignee_profile_id",
        "deadline_iso",
      ],
      additionalProperties: false,
    };

    const aiResponse = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        store: false,
        max_output_tokens: 500,
        input: [
          {
            role: "system",
            content: [
              {
                type: "input_text",
                text:
                  "Classify whether the sender's current message creates, " +
                  "updates, or changes the status of a real task. Understand " +
                  "natural English, Tanglish, Hinglish, transliteration, " +
                  "code-switching, dialect, slang, shorthand and spelling " +
                  "mistakes. Do not turn ordinary statements, greetings, " +
                  "questions without action intent, jokes, or past completed " +
                  "events into tasks. Infer the assignee only from the sender, " +
                  "channel members and wording. Use assignee_profile_id 0 if " +
                  "uncertain. deadline_iso must be ISO-8601 when a deadline is " +
                  "clear, otherwise an empty string. description must contain " +
                  "only useful task detail, never a copy of the original chat. " +
                  "Return only the requested JSON schema.",
              },
            ],
          },
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text:
                  "JSON context for classification:\n" +
                  JSON.stringify(inputContext),
              },
            ],
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "taskly_local_task_detection",
            strict: true,
            schema,
          },
        },
      }),
    });

    if (!aiResponse.ok) {
      const detail = await aiResponse.text();
      console.error("OpenAI task analysis failed", aiResponse.status, detail);
      return json({ error: "Task analysis unavailable." }, 502);
    }

    const raw = await aiResponse.json();
    const outputText = extractOutputText(raw);
    const parsed = JSON.parse(outputText) as TaskDetection;

    if (!parsed.is_task || parsed.confidence < 0.72) {
      return json(
        {
          is_task: false,
          confidence: Number(parsed.confidence ?? 0),
        },
        200,
      );
    }

    const memberIds = new Set(members.map((m) => m.id));
    if (
      parsed.assignee_profile_id !== 0 &&
      !memberIds.has(Number(parsed.assignee_profile_id))
    ) {
      parsed.assignee_profile_id = 0;
    }

    // IMPORTANT: nothing is inserted here. Raw chat stays transient.
    return json(parsed, 200);
  } catch (error) {
    console.error(error);
    return json({ error: "Task analysis failed." }, 500);
  }
});

function extractOutputText(response: any): string {
  if (typeof response?.output_text === "string" && response.output_text) {
    return response.output_text;
  }

  const parts: string[] = [];
  for (const item of response?.output ?? []) {
    for (const content of item?.content ?? []) {
      if (
        (content?.type === "output_text" || content?.type === "text") &&
        typeof content?.text === "string"
      ) {
        parts.push(content.text);
      }
    }
  }

  if (!parts.length) {
    throw new Error("OpenAI response contained no structured text.");
  }
  return parts.join("");
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
