-- ============================================================
-- 11_approval_flow_and_attachments.sql
-- Phase 4 — approval workflow roles + file attachments
--
-- Decisions from this session:
--   1. Add a dedicated `cs_supervisor` role — only a CS supervisor (or
--      admin, as a fallback) can approve an evaluation once both QA
--      and CS/MP have submitted their halves.
--   2. Fully retire the word "Supervisor" — the legacy 'supervisor'
--      enum value is relabeled 'Admin' everywhere in the UI already
--      (v06); this migration adds a one-time data migration so any
--      account still literally set to 'supervisor' becomes 'admin',
--      and 'supervisor' stops being offered anywhere going forward
--      (kept in the enum only because Postgres enums can't drop
--      values — see notes).
--   3. CS and MP keep separate logins per person (for audit trail —
--      "who actually typed this"), identical permissions either way.
--      No schema change needed for this — already true.
--   4. Supplier responses come in as file/PDF attachments staff
--      upload to the evaluation or its corrective action, viewable
--      in-app — no supplier login, no new auth surface.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Add 'cs_supervisor' to the department_role enum.
--    (Postgres requires this outside any transaction block that also
--    uses the new value, which is why it's its own numbered step —
--    the Supabase SQL editor runs each statement in the script in one
--    implicit transaction, but a bare ALTER TYPE ... ADD VALUE is
--    fine as long as nothing in the SAME transaction reads the new
--    value before it's committed. If this specific statement ever
--    errors with "unsafe use of new value", just run this ALTER TYPE
--    line by itself first, then run the rest of the file.)
-- ------------------------------------------------------------
alter type department_role add value if not exists 'cs_supervisor';

-- ------------------------------------------------------------
-- 2) Migrate any existing 'supervisor' accounts to 'admin' — the word
--    "Supervisor" is retired from this point on. ('supervisor' stays
--    in the enum's possible values forever — Postgres can't drop enum
--    values — but nothing should be set to it after this.)
-- ------------------------------------------------------------
update user_profiles set department = 'admin' where department = 'supervisor';

-- ------------------------------------------------------------
-- 3) is_admin() / is_cs_supervisor() helpers, and update every RLS
--    policy + trigger that referenced 'supervisor' to stop doing so
--    (they already also checked 'admin', so this is just cleanup —
--    behavior for existing 'admin' users is unchanged).
-- ------------------------------------------------------------
create or replace function public.is_admin()
returns boolean as $$
  select exists (
    select 1 from user_profiles
    where id = auth.uid() and department = 'admin'
  );
$$ language sql stable security definer set search_path = public;

create or replace function public.is_cs_supervisor()
returns boolean as $$
  select exists (
    select 1 from user_profiles
    where id = auth.uid() and department in ('cs_supervisor', 'admin')
  );
$$ language sql stable security definer set search_path = public;

-- enforce_evaluation_edit_permissions (v0.3.0 / v0.4.0): approving now
-- requires is_cs_supervisor() (CS supervisor OR admin), not just any
-- 'supervisor'/'admin' department — and only once BOTH halves are
-- submitted (see step 5's new submitted_at columns).
create or replace function public.enforce_evaluation_edit_permissions()
returns trigger as $$
declare
  dept department_role;
begin
  select department into dept from user_profiles where id = auth.uid();

  if dept is null then
    raise exception 'No user_profiles row found for current user — cannot verify permissions';
  end if;

  if dept = 'admin' then
    -- full access, but still stamp approval metadata below
  else
    if dept = 'qa' then
      if new.delivery_score  is distinct from old.delivery_score
         or new.purchase_score is distinct from old.purchase_score
         or new.delivery_comment is distinct from old.delivery_comment
         or new.shipment_status is distinct from old.shipment_status
         or new.no_shipment_reason is distinct from old.no_shipment_reason then
        raise exception 'QA role can only edit quality fields';
      end if;
    end if;

    if dept in ('cs', 'mp', 'cs_supervisor') then
      if new.quality_score is distinct from old.quality_score
         or new.quality_comment is distinct from old.quality_comment then
        raise exception 'CS/MP role can only edit delivery and purchase fields';
      end if;
    end if;

    if new.status = 'approved' and old.status is distinct from 'approved' then
      if not public.is_cs_supervisor() then
        raise exception 'Only a CS Supervisor or Admin can approve an evaluation';
      end if;
      if new.quality_submitted_at is null or new.delivery_submitted_at is null then
        raise exception 'Cannot approve until both QA and CS/MP have submitted their sections';
      end if;
    end if;
  end if;

  if new.status = 'approved' and old.status is distinct from 'approved' then
    new.approved_by = auth.uid();
    new.approved_at = now();
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- corrective_actions delete policy (v0.5.0) referenced 'supervisor' too
drop policy if exists "only supervisor or admin can delete evaluations" on evaluations;
create policy "cs supervisor or admin can delete evaluations"
  on evaluations for delete
  to authenticated
  using (public.is_cs_supervisor());

-- ------------------------------------------------------------
-- 4) Also relabel any leftover raw_user_meta_data left over from old
--    signups (cosmetic only — doesn't affect permissions, department
--    always comes from user_profiles, not this JSON blob).
-- ------------------------------------------------------------
-- (nothing to do here — see notes)

-- ------------------------------------------------------------
-- 5) Separate submit flags for QA vs CS/MP — approval now requires
--    BOTH to be filled in, not just "someone set status to approved".
-- ------------------------------------------------------------
alter table evaluations
  add column quality_submitted_at timestamptz,
  add column quality_submitted_by uuid references auth.users(id),
  add column delivery_submitted_at timestamptz,
  add column delivery_submitted_by uuid references auth.users(id);

comment on column evaluations.quality_submitted_at is 'Set when QA marks their section (Quality+Environment) as submitted. Required before status can become approved.';
comment on column evaluations.delivery_submitted_at is 'Set when CS/MP marks their section (Delivery+Purchase) as submitted. Required before status can become approved.';

-- ------------------------------------------------------------
-- 6) File attachments — for the evaluation itself (e.g. supplier's
--    PDF response, internal review notes) and for corrective actions
--    (supplier's improvement plan). Uses Supabase Storage; this table
--    just tracks metadata + the storage path, so the app can list and
--    open them. No new auth surface — only existing logged-in staff
--    can upload/view, matching "PDF+Email, no extra security" as
--    decided.
-- ------------------------------------------------------------
create table evaluation_attachments (
  id                uuid primary key default gen_random_uuid(),
  evaluation_id     uuid references evaluations(id) on delete cascade,
  corrective_action_id uuid references corrective_actions(id) on delete cascade,
  file_name         text not null,
  storage_path      text not null,      -- path inside the 'attachments' Storage bucket
  file_size_bytes   bigint,
  content_type      text,
  uploaded_by       uuid references auth.users(id),
  uploaded_at       timestamptz not null default now(),

  check (
    (evaluation_id is not null and corrective_action_id is null)
    or (evaluation_id is null and corrective_action_id is not null)
  )
);

comment on table evaluation_attachments is 'Files attached to an evaluation OR a corrective action (never both) — e.g. supplier''s PDF response, improvement plan evidence. Actual file bytes live in Supabase Storage bucket "attachments"; this table is just metadata + path.';

create index idx_attach_evaluation on evaluation_attachments(evaluation_id);
create index idx_attach_ca on evaluation_attachments(corrective_action_id);

alter table evaluation_attachments enable row level security;

create policy "authenticated can read attachments"
  on evaluation_attachments for select
  to authenticated
  using (true);

create policy "authenticated can insert attachments"
  on evaluation_attachments for insert
  to authenticated
  with check (true);

create policy "authenticated can delete attachments"
  on evaluation_attachments for delete
  to authenticated
  using (true);

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * ONE MANUAL STEP THIS SQL FILE CANNOT DO: create the Storage
--   bucket. In Supabase Dashboard -> Storage -> New bucket, create a
--   bucket named exactly "attachments". You can leave it Private —
--   the app fetches files through the authenticated Supabase client,
--   not a public URL, consistent with "no new security surface".
-- * 'supervisor' cannot be removed from the department_role enum
--   (Postgres limitation — enum values are permanent once added).
--   It's dead going forward: nothing sets it, the UI never offers it,
--   and every permission check now keys off 'admin'/'cs_supervisor'
--   specifically rather than accepting 'supervisor' as a synonym.
-- * Existing admin/cs/mp/qa accounts are unaffected. Any account you
--   want to be able to approve evaluations going forward must be set
--   to 'cs_supervisor' or 'admin' in Master Control -> Users & Roles.
-- ============================================================
