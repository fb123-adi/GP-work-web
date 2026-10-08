// Emails the admin when someone signs up for the first time, with a one-click unsubscribe.
// Triggered by a Supabase Database Webhook on INSERT into public.records.
// Secrets: RESEND_API_KEY, ADMIN_EMAIL, WEBHOOK_SECRET, UNSUBSCRIBE_TOKEN, optional ALERT_FROM.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const esc = (s: unknown) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!));
const page = (msg: string) => new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><body style="font-family:system-ui;padding:40px;max-width:520px;margin:auto;color:#22271F"><h2>SIDADI Workspace</h2><p>${msg}</p></body>`, { headers: { 'content-type': 'text/html; charset=utf-8' } });

async function setAlerts(on: boolean) {
  await db.from('records').upsert({ collection: 'settings', id: 'alerts', emp_id: null, data: { id: 'alerts', newSignupEmails: on } });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const unsub = url.searchParams.get('unsubscribe');
  if (unsub !== null) {
    if (unsub !== Deno.env.get('UNSUBSCRIBE_TOKEN')) return page('This unsubscribe link is not valid.');
    await setAlerts(false);
    return page('You will no longer receive new sign-up emails. You can turn them back on in the app under <b>Admin login → Email alerts</b>.');
  }

  const secret = Deno.env.get('WEBHOOK_SECRET');
  if (secret && req.headers.get('x-webhook-secret') !== secret) return new Response('forbidden', { status: 403 });

  const body = await req.json();
  const r = body.record;
  if (body.type !== 'INSERT' || !r || r.collection !== 'employees' || !r.data?.joinedAt) return new Response('ignored');

  const { data: s } = await db.from('records').select('data').eq('collection', 'settings').eq('id', 'alerts').maybeSingle();
  if (s?.data?.newSignupEmails === false) return new Response('alerts off');

  const unsubUrl = `${url.origin}${url.pathname}?unsubscribe=${encodeURIComponent(Deno.env.get('UNSUBSCRIBE_TOKEN') ?? '')}`;
  const d = r.data;
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${Deno.env.get('RESEND_API_KEY')}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: Deno.env.get('ALERT_FROM') ?? 'SIDADI Workspace <onboarding@resend.dev>',
      to: [Deno.env.get('ADMIN_EMAIL')],
      subject: `New sign-up: ${d.name}`,
      headers: { 'List-Unsubscribe': `<${unsubUrl}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' },
      html: `<p><b>${esc(d.name)}</b> (${esc(d.email)}) just joined SIDADI Workspace as <b>${esc(d.userId)}</b>.</p>
             <p>Open the app → <b>Sign-ins</b> to place them in a department and assign work.</p>
             <hr style="border:none;border-top:1px solid #ddd;margin:24px 0">
             <p style="font-size:12px;color:#555">You get this email because you are the SIDADI Workspace admin.
             <a href="${unsubUrl}">Unsubscribe from new sign-up emails</a>.</p>`,
    }),
  });
  return new Response(await res.text(), { status: res.status });
});
