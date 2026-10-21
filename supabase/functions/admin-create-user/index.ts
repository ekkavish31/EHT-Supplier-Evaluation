// supabase/functions/admin-create-user/index.ts
//
// Creates a new Supabase Auth user + user_profiles row on behalf of an
// Admin, from inside the app — without ever exposing the service role
// key to the browser. This function IS the only place the service
// role key is used.
//
// Deploy with the Supabase CLI (see database/README section this
// package adds, or the deployment notes at the bottom of this file).
// The SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY
// env vars are provided automatically by the Supabase platform for
// every Edge Function — nothing to configure manually for those three.

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

const VALID_DEPARTMENTS = ['qa', 'cs', 'mp', 'cs_supervisor', 'mp_supervisor', 'opd_manager', 'admin'];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization header' }, 401);

    // Client scoped to the CALLER's own JWT — used only to verify who
    // is asking and whether they're Admin, via the same RLS-protected
    // tables the app itself reads (user_profiles + permission_rules).
    // This client is never given the service role key.
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
    if (!permRow?.allowed) return json({ error: 'Only Admin can create user accounts' }, 403);

    // ---- Caller verified as Admin. Now do the privileged part. ----
    const body = await req.json();
    const userId = String(body.userId || '').trim();
    const password = String(body.password || '');
    const fullName = String(body.fullName || '').trim();
    const department = String(body.department || '');

    if (!userId || !password || !department) {
      return json({ error: 'userId, password, and department are all required' }, 400);
    }
    if (!VALID_DEPARTMENTS.includes(department)) {
      return json({ error: `department must be one of: ${VALID_DEPARTMENTS.join(', ')}` }, 400);
    }
    if (password.length < 6) {
      return json({ error: 'Password must be at least 6 characters' }, 400);
    }

    const email = `${userId}@eht.local`; // same convention as LOGIN_EMAIL_DOMAIN in app.js

    // Service-role client — the only place in this whole project this
    // key is used, and it never leaves this server-side function.
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true, // admin-created accounts don't need an email confirmation step
      user_metadata: { full_name: fullName, department },
    });

    if (createErr) return json({ error: createErr.message }, 400);

    // handle_new_user() (see database/26_admin_create_user.sql) fires
    // automatically on this insert and creates the user_profiles row.
    return json({ id: created.user?.id, email }, 200);
  } catch (e) {
    console.error(e);
    return json({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});

/* ============================================================
   Deployment (one-time, from a terminal with the Supabase CLI):

   1. supabase login
   2. supabase link --project-ref <your-project-ref>
   3. supabase functions deploy admin-create-user

   That's it — SUPABASE_URL, SUPABASE_ANON_KEY, and
   SUPABASE_SERVICE_ROLE_KEY are injected automatically, no `supabase
   secrets set` needed for this function.

   Test it directly (optional, replace <ADMIN_JWT> with a real logged
   in Admin's access token, found via supabase.auth.getSession() in
   the browser console while logged in as Admin):

   curl -i --location --request POST \
     'https://<project-ref>.supabase.co/functions/v1/admin-create-user' \
     --header 'Authorization: Bearer <ADMIN_JWT>' \
     --header 'Content-Type: application/json' \
     --data '{"userId":"test01","password":"testpass123","fullName":"Test User","department":"qa"}'
   ============================================================ */
