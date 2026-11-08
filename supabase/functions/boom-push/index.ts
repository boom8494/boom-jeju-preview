import { createClient } from "npm:@supabase/supabase-js@2";
import * as webpush from "jsr:@negrel/webpush@0.5.0";

type NotificationRecord = {
  id: string;
  user_id: string;
  title: string;
  body: string;
  link: string;
};

type DatabaseWebhook = {
  type: string;
  table: string;
  schema: string;
  record: NotificationRecord;
};

const cors = {
  "Access-Control-Allow-Origin": "https://boomjeju.co.kr",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const vapidKeysJson = Deno.env.get("VAPID_KEYS");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Server is not configured" }, 503);

  let payload: DatabaseWebhook | { action?: string };
  try {
    payload = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  // The VAPID public key is not secret. The only public operation is returning it.
  if ("action" in payload && payload.action === "public_key") {
    if (!vapidKeysJson) return json({ error: "Push keys are not configured" }, 503);
    try {
      const vapidKeys = await webpush.importVapidKeys(JSON.parse(vapidKeysJson));
      const publicKey = await webpush.exportApplicationServerKey(vapidKeys);
      return json({ publicKey });
    } catch {
      return json({ error: "Push keys are invalid" }, 503);
    }
  }

  // Database Webhooks must send Authorization: Bearer <Supabase service role key>.
  if (request.headers.get("Authorization") !== `Bearer ${serviceRoleKey}`) {
    return json({ error: "Unauthorized" }, 401);
  }
  if (!vapidKeysJson) return json({ error: "Push keys are not configured" }, 503);

  const event = payload as DatabaseWebhook;
  if (event.type !== "INSERT" || event.schema !== "public" || event.table !== "boom_notifications") {
    return json({ ignored: true });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: subscriptions, error: subscriptionError } = await admin
    .from("boom_push_subscriptions")
    .select("id, endpoint, subscription")
    .eq("user_id", event.record.user_id);
  if (subscriptionError) return json({ error: "Could not load subscriptions" }, 500);

  const { count } = await admin
    .from("boom_notifications")
    .select("id", { count: "exact", head: true })
    .eq("user_id", event.record.user_id)
    .is("read_at", null);

  const vapidKeys = await webpush.importVapidKeys(JSON.parse(vapidKeysJson));
  const appServer = await webpush.ApplicationServer.new({
    contactInformation: Deno.env.get("VAPID_SUBJECT") ?? "mailto:info@boomjeju.co.kr",
    vapidKeys,
  });
  const destination = new URL(event.record.link || "/", "https://boomjeju.co.kr");
  destination.searchParams.set("boom_notification", event.record.id);
  const message = JSON.stringify({
    title: event.record.title,
    body: event.record.body,
    unread_count: count ?? 1,
    notification_id: event.record.id,
    url: destination.toString(),
  });

  let sent = 0;
  for (const row of subscriptions ?? []) {
    try {
      await appServer.subscribe(row.subscription).pushTextMessage(message, {
        ttl: 120,
        urgency: webpush.Urgency.High,
      });
      sent++;
    } catch (error) {
      if (error instanceof webpush.PushMessageError && error.isGone()) {
        await admin.from("boom_push_subscriptions").delete().eq("id", row.id);
      } else {
        console.error("Web push delivery failed", error);
      }
    }
  }

  return json({ sent });
});
