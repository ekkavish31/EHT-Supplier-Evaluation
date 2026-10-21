-- ============================================================
-- 26_admin_create_user.sql
-- Now that public self-signup is being disabled entirely (both in the
-- app UI, per SELF_SIGNUP_ENABLED=false, AND at the Supabase Auth
-- provider level — see the README section this migration's package
-- adds), the ONLY ways a new auth.users row can ever be created are:
--   1. The new admin-create-user Edge Function (checks the caller is
--      Admin before doing anything, using the caller's own JWT/RLS —
--      see supabase/functions/admin-create-user/index.ts)
--   2. Directly in the Supabase Dashboard (already fully trusted —
--      whoever has dashboard access already has full DB access)
-- The old restriction in handle_new_user() — "self-signup can only
-- ever produce qa/cs/mp, silently downgrade anything else" — existed
-- specifically to stop a public signUp() call from claiming an
-- elevated role. That path no longer exists, so the restriction is
-- now just an obstacle to Admin legitimately creating a Supervisor/
-- Manager/Admin account through the app. Removed.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
declare
  requested_department text := new.raw_user_meta_data->>'department';
  final_department department_role;
begin
  -- Validate against the real enum instead of a hardcoded allow-list —
  -- any of the 7 department_role values is now acceptable, since the
  -- only caller that can reach this point at all (besides the
  -- Dashboard) is the Admin-gated Edge Function.
  begin
    final_department := requested_department::department_role;
  exception when invalid_text_representation then
    final_department := 'qa';
  end;

  insert into public.user_profiles (id, full_name, department)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    final_department
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * This migration alone does NOT disable public signup — that's a
--   Supabase Dashboard setting (Authentication -> Providers -> Email
--   -> "Allow new users to sign up"), which must be turned off
--   manually. This SQL just makes the trigger trust admin-supplied
--   departments once that path is the only one left.
-- * If you ever decide to re-enable public self-signup later (setting
--   SELF_SIGNUP_ENABLED=true in app.js AND re-enabling it in Supabase
--   Dashboard), this trigger would need the qa/cs/mp restriction
--   added back — it's deliberately open now because the calling path
--   is assumed to always be admin-gated.
-- ============================================================
