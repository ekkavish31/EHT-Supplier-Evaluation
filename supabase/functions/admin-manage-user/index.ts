// supabase/functions/admin-manage-user/index.ts
//
// Two admin-only actions on an EXISTING user account:
//   - action: "delete"          — permanently removes the auth user
//     (user_profiles row goes with it via ON DELETE CASCADE, see
//     03_phase2_auth_and_roles.sql). If this user is referenced by
//     historical records (e.g. an evaluation's *_by columns) without
//     a cascade there, the delete will fail with a clear FK error —
//     that's intentional, not a bug to route around: it stops an
//     admin from accidentally erasing someone's audit trail.
//   - action: "reset_password"  — sets a NEW password chosen by the
//     admin. There is deliberately no way to recover or display the
//     OLD password: Supabase (like every correctly-built auth
//     system) only ever stores a one-way hash, never anything
//     reversible — that's not a missing feature, it's what makes the
//     hash safe to store at all. Reset is the correct fix for "not
//     sure what the password is," not exposing the old one.
//
// Same security model as admin-create-user: the caller's own JWT is
// verified against user_profiles + permission_rules (master_data_manage)
// using an anon-scoped client BEFORE the service-role client is ever
// touched. The service role key never leaves this function.
//
// Deploy via the Supabase Dashboard: Edge Functions -> Deploy a new
// function -> Via Editor -> name it exactly what you plan to call it
// from the app (see the IMPORTANT note in app.js next to where this
// function is invoked — the dashboard's displayed "Name" can be
// changed after deploying, but that does NOT change the actual
// routing slug in the URL; call the app by whatever slug the URL
// column shows, not the Name column).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization header' }, 401);

    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user: caller }, error: callerErr } = await callerClient.auth.getUser();
    if (callerErr || !caller) return json({ error: 'Invalid or expired session' }, 401);

    const { data: callerProfile } = await callerClient
      .from('user_profiles').select('department').eq('id', caller.id).maybeSingle();
    if (!callerProfile?.department) return json({ error: 'Caller has no profile' }, 403);

    const { data: permRow } = await callerClient
      .from('permission_rules').select('allowed')
      .eq('rule_key', 'master_data_manage').eq('department', callerProfile.department)
      .maybeSingle();
    if (!permRow?.allowed) return json({ error: 'Only Admin can manage user accounts' }, 403);

    // ---- Caller verified as Admin. Now do the privileged part. ----
    const body = await req.json();
    const action = String(body.action || '');
    const targetUserId = String(body.userId || '').trim();
    if (!targetUserId) return json({ error: 'userId is required' }, 400);

    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    if (action === 'delete') {
      if (targetUserId === caller.id) return json({ error: "You can't delete your own account while logged in as it" }, 400);
      const { error: delErr } = await adminClient.auth.admin.deleteUser(targetUserId);
      if (delErr) return json({ error: delErr.message }, 400);
      return json({ ok: true }, 200);
    }

    if (action === 'reset_password') {
      const newPassword = String(body.newPassword || '');
      if (newPassword.length < 6) return json({ error: 'Password must be at least 6 characters' }, 400);
      const { error: updErr } = await adminClient.auth.admin.updateUserById(targetUserId, { password: newPassword });
      if (updErr) return json({ error: updErr.message }, 400);
      return json({ ok: true }, 200);
    }

    return json({ error: `Unknown action: ${action}` }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
