// Supabase Edge Function: send-notification
//
// Triggered by Database Webhooks on incident/unit-dispatch changes. It works
// out who should be notified, looks up their FCM device tokens, and sends a
// push via the Firebase Cloud Messaging HTTP v1 API.
//
// Events handled:
//   * incidents UPDATE  status -> 'Assigned'  → notify the citizen (reporter)
//   * incidents UPDATE  status -> 'Resolved'  → notify the citizen ("rate")
//   * incident_dispatches INSERT              → notify the dispatched unit
//
// Required secret:  FCM_SERVICE_ACCOUNT  = the full Firebase service-account
// JSON (Project Settings → Service accounts → Generate new private key).
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://esm.sh/jose@5";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const serviceAccount = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);

// --- FCM auth: mint a short-lived OAuth token from the service account -------
async function getAccessToken(): Promise<string> {
  const key = await importPKCS8(
    serviceAccount.private_key.replace(/\\n/g, "\n"),
    "RS256",
  );
  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(serviceAccount.client_email)
    .setSubject(serviceAccount.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const data = await res.json();
  return data.access_token;
}

async function tokensForUser(userId: string): Promise<string[]> {
  const { data } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", userId);
  return (data ?? []).map((r: { token: string }) => r.token);
}

async function send(
  userId: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const tokens = await tokensForUser(userId);
  if (tokens.length === 0) return;

  const accessToken = await getAccessToken();
  const projectId = serviceAccount.project_id;

  for (const token of tokens) {
    const resp = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data,
            android: { priority: "high" },
          },
        }),
      },
    );
    if (!resp.ok) {
      const errText = await resp.text();
      console.error(`FCM failed (${resp.status}): ${errText}`);
      // Token no longer valid → clean it up so we don't keep retrying.
      if (resp.status === 404) {
        await supabase.from("device_tokens").delete().eq("token", token);
      }
    }
  }
}

Deno.serve(async (req) => {
  try {
    const { type, table, record, old_record } = await req.json();

    // Citizen notifications on incident status changes.
    if (table === "incidents" && type === "UPDATE" && record?.reporter_id) {
      const changed = old_record?.status !== record?.status;
      if (changed && record.status === "Assigned") {
        await send(
          record.reporter_id,
          "Help is on the way 🚑",
          "A response unit has been dispatched to your location.",
          { type: "incident_assigned", incident_id: String(record.id) },
        );
      } else if (changed && record.status === "Resolved") {
        await send(
          record.reporter_id,
          "How was your experience? ⭐",
          "Your incident is resolved. Tap to rate the response.",
          { type: "rate_incident", incident_id: String(record.id) },
        );
      }
    }

    // Unit notification when it gets dispatched to an incident.
    if (table === "incident_dispatches" && type === "INSERT" && record?.unit_id) {
      const { data: unit } = await supabase
        .from("units")
        .select("auth_user_id")
        .eq("id", record.unit_id)
        .maybeSingle();
      if (unit?.auth_user_id) {
        await send(
          unit.auth_user_id,
          "New assignment 🚨",
          "You have been dispatched to an incident. Tap for details.",
          { type: "new_assignment", incident_id: String(record.incident_id) },
        );
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("send-notification error:", e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
