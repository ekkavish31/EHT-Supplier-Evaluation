-- ============================================================
-- Phase 2 — Auth & Department-based Permissions
-- Run this AFTER supplier_evaluation_schema.sql and seed_data.sql
-- ============================================================

-- ------------------------------------------------------------
-- 0) Remove the temporary anon policies from Phase 1
--    (the app now authenticates real users instead)
-- ------------------------------------------------------------
drop policy if exists "temp anon read suppliers" on suppliers;
drop policy if exists "temp anon read evaluations" on evaluations;
drop policy if exists "temp anon write evaluations" on evaluations;
drop policy if exists "temp anon update evaluations" on evaluations;
drop policy if exists "temp anon delete evaluations" on evaluations;

-- ------------------------------------------------------------
-- 1) Department enum + user_profiles table
-- ------------------------------------------------------------
create type department_role as enum ('qa', 'cs', 'mp', 'supervisor', 'admin');

create table user_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  department  department_role not null default 'qa',
  created_at  timestamptz not null default now()
);

comment on table user_profiles is 'One row per login user. department controls which fields they can edit on evaluations.';

alter table user_profiles enable row level security;

create policy "authenticated can read all profiles"
  on user_profiles for select
  to authenticated
  using (true);

-- No insert/update policy for normal users on purpose:
-- profile rows are created automatically by the trigger below (security definer),
-- and department changes should go through an admin editing the table directly
-- (or you can add an "admin can update any profile" policy later once Phase 4 roles settle).

-- ------------------------------------------------------------
-- 2) Auto-create a profile row whenever someone signs up
--    Reads `full_name` / `department` from the signUp() metadata
--    sent by the frontend (see app.js signUp call).
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.user_profiles (id, full_name, department)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce((new.raw_user_meta_data->>'department')::department_role, 'qa')
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- 3) Restrict DELETE on evaluations to supervisor/admin only
--    (SELECT / INSERT / UPDATE policies for `authenticated` already
--    exist from Phase 1 — column-level restriction is handled by
--    the trigger in step 4, since RLS alone can't do column-level checks)
-- ------------------------------------------------------------
create policy "only supervisor or admin can delete evaluations"
  on evaluations for delete
  to authenticated
  using (
    exists (
      select 1 from user_profiles p
      where p.id = auth.uid() and p.department in ('supervisor', 'admin')
    )
  );

-- ------------------------------------------------------------
-- 4) Column-level enforcement (BEFORE UPDATE trigger)
--    QA can only touch quality_* fields.
--    CS/MP can only touch delivery_*/purchase_* fields.
--    Only supervisor/admin can set status = 'approved'.
--    supervisor/admin can edit everything.
-- ------------------------------------------------------------
create or replace function public.enforce_evaluation_edit_permissions()
returns trigger as $$
declare
  dept department_role;
begin
  select department into dept from user_profiles where id = auth.uid();

  if dept is null then
    raise exception 'No user_profiles row found for current user — cannot verify permissions';
  end if;

  if dept in ('supervisor', 'admin') then
    -- full access, but still stamp approval metadata below
  else
    if dept = 'qa' then
      if new.delivery_score  is distinct from old.delivery_score
         or new.purchase_score is distinct from old.purchase_score
         or new.delivery_comment is distinct from old.delivery_comment then
        raise exception 'QA role can only edit quality fields';
      end if;
    end if;

    if dept in ('cs', 'mp') then
      if new.quality_score is distinct from old.quality_score
         or new.quality_comment is distinct from old.quality_comment then
        raise exception 'CS/MP role can only edit delivery and purchase fields';
      end if;
    end if;

    if new.status = 'approved' and old.status is distinct from 'approved' then
      raise exception 'Only supervisor or admin can approve an evaluation';
    end if;
  end if;

  -- stamp approval metadata whenever status newly becomes 'approved'
  if new.status = 'approved' and old.status is distinct from 'approved' then
    new.approved_by = auth.uid();
    new.approved_at = now();
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_enforce_evaluation_edit
  before update on evaluations
  for each row execute function public.enforce_evaluation_edit_permissions();

-- ------------------------------------------------------------
-- 5) Stamp who submitted a new evaluation row
-- ------------------------------------------------------------
create or replace function public.set_evaluation_submitter()
returns trigger as $$
begin
  if new.submitted_by is null then
    new.submitted_by = auth.uid();
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_set_evaluation_submitter
  before insert on evaluations
  for each row execute function public.set_evaluation_submitter();

-- ============================================================
-- Notes:
-- - New INSERTs are still open to any authenticated department
--   (someone has to create the row before others can fill their part).
--   Tighten this later if you want QA to be the only one who can
--   create the first row for a month.
-- - The trigger uses `is distinct from` so unchanged columns never
--   trip the check — the frontend only needs to disable inputs the
--   user's role isn't allowed to touch (already done in app.js).
-- - Email confirmation: if your Supabase project has "Confirm email"
--   turned on (Auth → Providers → Email), new users must click the
--   confirmation link before they can log in. Turn it off for faster
--   internal testing, or keep it on for real deployment.
-- ============================================================
