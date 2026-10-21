-- ============================================================
-- 09_master_control.sql
-- Master Control — admin-only CRUD for master data
--
-- Two more of the same latent bug class as corrective_actions (v14):
--   - `evaluation_criteria` has RLS enabled since v0.1.0 but ZERO
--     policies at all — it has been 100% inaccessible (can't even
--     SELECT) from the app since day one.
--   - `suppliers` has a SELECT policy but no INSERT/UPDATE/DELETE
--     policy — suppliers can be viewed but never added, edited, or
--     deactivated from the app.
--   - `user_profiles` has a SELECT policy but no UPDATE policy —
--     an admin cannot change anyone's department from the app; the
--     only way has been editing the table directly in Supabase.
-- This migration fixes all three, admin/supervisor-only for writes.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- Helper: is the current user an admin/supervisor?
-- Small security-definer function so RLS policies stay short and
-- consistent, and so this one place is the only thing to change if
-- the "supervisor" legacy value is ever fully retired (see v06 notes
-- — 'supervisor' and 'admin' have identical rights everywhere).
-- ------------------------------------------------------------
create or replace function public.is_admin()
returns boolean as $$
  select exists (
    select 1 from user_profiles
    where id = auth.uid() and department in ('admin', 'supervisor')
  );
$$ language sql stable security definer set search_path = public;

-- ------------------------------------------------------------
-- 1) SUPPLIERS — admin-only write, everyone (authenticated) still reads
-- ------------------------------------------------------------
create policy "admin can insert suppliers"
  on suppliers for insert
  to authenticated
  with check (public.is_admin());

create policy "admin can update suppliers"
  on suppliers for update
  to authenticated
  using (public.is_admin());

create policy "admin can delete suppliers"
  on suppliers for delete
  to authenticated
  using (public.is_admin());

-- ------------------------------------------------------------
-- 2) EVALUATION_CRITERIA — was completely inaccessible; now readable
--    by everyone (needed for Phase 3's itemized checklist), writable
--    by admin only.
-- ------------------------------------------------------------
create policy "authenticated can read evaluation criteria"
  on evaluation_criteria for select
  to authenticated
  using (true);

create policy "admin can insert evaluation criteria"
  on evaluation_criteria for insert
  to authenticated
  with check (public.is_admin());

create policy "admin can update evaluation criteria"
  on evaluation_criteria for update
  to authenticated
  using (public.is_admin());

create policy "admin can delete evaluation criteria"
  on evaluation_criteria for delete
  to authenticated
  using (public.is_admin());

-- ------------------------------------------------------------
-- 3) USER_PROFILES — admin can now update department/full_name for
--    any user directly from the app (previously SQL-editor only).
--    Still no INSERT/DELETE policy for normal use — profiles are
--    only ever created by the handle_new_user trigger (security
--    definer, bypasses RLS) when someone signs up or is added in
--    Supabase Auth directly.
-- ------------------------------------------------------------
create policy "admin can update any profile"
  on user_profiles for update
  to authenticated
  using (public.is_admin());

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * is_admin() is STABLE (safe to use multiple times per query) and
--   SECURITY DEFINER (so it can read user_profiles regardless of the
--   caller's own row-level access — it only ever returns a boolean,
--   never row data, so this doesn't leak anything).
-- * The app's own UI additionally hides the "Master Control" tab for
--   non-admins, but that's just a UX nicety — these RLS policies are
--   the actual enforcement, exactly like every other locked area in
--   this app.
-- ============================================================
