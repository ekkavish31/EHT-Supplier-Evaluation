-- ============================================================
-- 05_block_admin_selfsignup.sql
--
-- The app's "Create account" form is back, but it must never be able
-- to create a Supervisor/Admin account — the UI dropdown already hides
-- that option, but a dropdown is just client-side; anyone could still
-- call supabase.auth.signUp() directly from the browser console with
-- department: 'admin' in the metadata. This migration closes that gap
-- at the database level, in the same trigger that creates the profile
-- row, so it applies no matter how signUp() was called.
--
-- Run this once in the Supabase SQL editor (safe to re-run).
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
declare
  requested_department text := new.raw_user_meta_data->>'department';
  final_department department_role;
begin
  -- Self-signup can only ever result in qa / cs / mp. Anything else
  -- (including 'admin' or 'supervisor', however it was requested)
  -- is silently downgraded to 'qa'. Admin accounts must be created
  -- directly in Supabase (Dashboard -> Authentication -> Users),
  -- which does not go through this signUp() flow at all.
  if requested_department in ('qa', 'cs', 'mp') then
    final_department := requested_department::department_role;
  else
    final_department := 'qa';
  end if;

  insert into public.user_profiles (id, full_name, department)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    final_department
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- Trigger already exists and points at this function by name, so no
-- need to recreate it — `create or replace function` above is enough.

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * Users created directly in the Supabase Dashboard (Authentication ->
--   Users -> Add user) still go through this same trigger, but they
--   have no 'department' in raw_user_meta_data, so they also default
--   to 'qa' here. That's why 04_simplify_admin_login.sql's instructions
--   say to manually set department = 'admin' in the user_profiles table
--   afterwards for any account you want to have Admin rights — this
--   trigger only restricts what the public sign-up FORM can request,
--   it doesn't stop you (as the DB owner) from setting 'admin' by hand.
-- ============================================================
