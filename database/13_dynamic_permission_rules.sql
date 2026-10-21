-- ============================================================
-- 13_dynamic_permission_rules.sql
-- Makes permissions actually admin-editable from the app, instead of
-- hardcoded in SQL. Every place that used to check `department in
-- (...)` now checks a `permission_rules` table instead, through one
-- shared function `has_permission(rule_key)`.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1) The rules table itself.
--    Fixed set of (rule_key, department) rows — the app only ever
--    UPDATEs the `allowed` column, never inserts/deletes a row, so
--    the set of things that CAN be configured stays well-defined
--    (no risk of a typo'd rule_key silently doing nothing because
--    no trigger checks it).
-- ------------------------------------------------------------
create table permission_rules (
  id          uuid primary key default gen_random_uuid(),
  rule_key    text not null,
  department  department_role not null,
  allowed     boolean not null default false,
  updated_at  timestamptz not null default now(),
  unique (rule_key, department)
);

comment on table permission_rules is 'Admin-editable permission matrix. rule_key identifies a specific action (see has_permission() callers); department is one of the department_role enum values. Only UPDATE is expected from the app — the row set itself is seeded once here and not meant to grow from the UI.';

create index idx_permission_rules_key on permission_rules(rule_key);

alter table permission_rules enable row level security;

-- Everyone authenticated can READ the rules (the frontend needs this
-- to decide what to show/enable for the current user, not just the
-- database enforcing it after the fact). Only an admin can change one.
create policy "authenticated can read permission rules"
  on permission_rules for select
  to authenticated
  using (true);

create policy "admin can update permission rules"
  on permission_rules for update
  to authenticated
  using (public.is_admin());

-- ------------------------------------------------------------
-- 2) Seed rows — these values reproduce EXACTLY the hardcoded rules
--    from migrations 09/10/11/12, so running this migration changes
--    nothing about current behavior. Admin can change any of it
--    afterward from Master Control -> Permissions.
-- ------------------------------------------------------------
insert into permission_rules (rule_key, department, allowed) values
  -- Evaluations
  ('eval_edit_quality',  'qa',            true),
  ('eval_edit_quality',  'cs',            false),
  ('eval_edit_quality',  'mp',            false),
  ('eval_edit_quality',  'cs_supervisor', false),
  ('eval_edit_quality',  'admin',         true),

  ('eval_edit_delivery', 'qa',            false),
  ('eval_edit_delivery', 'cs',            true),
  ('eval_edit_delivery', 'mp',            true),
  ('eval_edit_delivery', 'cs_supervisor', true),
  ('eval_edit_delivery', 'admin',         true),

  ('eval_approve',       'qa',            false),
  ('eval_approve',       'cs',            false),
  ('eval_approve',       'mp',            false),
  ('eval_approve',       'cs_supervisor', true),
  ('eval_approve',       'admin',         true),

  ('eval_delete',        'qa',            false),
  ('eval_delete',        'cs',            false),
  ('eval_delete',        'mp',            false),
  ('eval_delete',        'cs_supervisor', true),
  ('eval_delete',        'admin',         true),

  -- Corrective Actions
  ('ca_create',          'qa',            false),
  ('ca_create',          'cs',            true),
  ('ca_create',          'mp',            true),
  ('ca_create',          'cs_supervisor', true),
  ('ca_create',          'admin',         true),

  ('ca_edit_full',       'qa',            false),
  ('ca_edit_full',       'cs',            false),
  ('ca_edit_full',       'mp',            false),
  ('ca_edit_full',       'cs_supervisor', true),
  ('ca_edit_full',       'admin',         true),

  ('ca_edit_restricted', 'qa',            true),
  ('ca_edit_restricted', 'cs',            false),
  ('ca_edit_restricted', 'mp',            false),
  ('ca_edit_restricted', 'cs_supervisor', false),
  ('ca_edit_restricted', 'admin',         false), -- moot: admin already has ca_edit_full

  ('ca_delete',          'qa',            false),
  ('ca_delete',          'cs',            false),
  ('ca_delete',          'mp',            false),
  ('ca_delete',          'cs_supervisor', true),
  ('ca_delete',          'admin',         true),

  -- Attachments (shared by evaluations and corrective actions)
  ('attachment_upload',  'qa',            true),
  ('attachment_upload',  'cs',            true),
  ('attachment_upload',  'mp',            true),
  ('attachment_upload',  'cs_supervisor', true),
  ('attachment_upload',  'admin',         true),

  ('attachment_delete',  'qa',            false),
  ('attachment_delete',  'cs',            false),
  ('attachment_delete',  'mp',            false),
  ('attachment_delete',  'cs_supervisor', true),
  ('attachment_delete',  'admin',         true),

  -- Master Data (Suppliers / Evaluation Criteria / Users & Roles / Permissions itself)
  ('master_data_manage', 'qa',            false),
  ('master_data_manage', 'cs',            false),
  ('master_data_manage', 'mp',            false),
  ('master_data_manage', 'cs_supervisor', false),
  ('master_data_manage', 'admin',         true)
on conflict (rule_key, department) do nothing;

-- ------------------------------------------------------------
-- 3) has_permission() — the one function every policy/trigger below
--    calls. Looks up the CURRENT user's department, then checks the
--    rules table for that (rule_key, department).
-- ------------------------------------------------------------
create or replace function public.has_permission(p_rule_key text)
returns boolean as $$
  select coalesce((
    select pr.allowed
    from permission_rules pr
    join user_profiles up on up.department = pr.department
    where up.id = auth.uid() and pr.rule_key = p_rule_key
  ), false);
$$ language sql stable security definer set search_path = public;

-- ------------------------------------------------------------
-- 4) Redefine is_admin() to delegate to has_permission() — every
--    existing policy that already calls is_admin() (suppliers,
--    evaluation_criteria, user_profiles from 09_master_control.sql)
--    becomes dynamic automatically, no need to touch those policies.
-- ------------------------------------------------------------
create or replace function public.is_admin()
returns boolean as $$
  select public.has_permission('master_data_manage');
$$ language sql stable security definer set search_path = public;

-- is_cs_supervisor() is superseded by more specific rule_keys below
-- (eval_delete / ca_delete / eval_approve are no longer all the same
-- toggle) — kept only so nothing that still references it by name
-- breaks; nothing new should call it.
create or replace function public.is_cs_supervisor()
returns boolean as $$
  select public.has_permission('ca_edit_full');
$$ language sql stable security definer set search_path = public;

-- ------------------------------------------------------------
-- 5) evaluations: rewrite the edit/approve trigger and the delete
--    policy to use has_permission() instead of hardcoded department
--    checks.
--
--    Side-effect bug fix: the old version's `if dept = 'admin'` early
--    branch skipped the "both sections submitted" requirement for
--    admins specifically (inconsistent — cs_supervisor still had to
--    go through it). That special case is gone now; the check is
--    uniform for anyone with eval_approve.
-- ------------------------------------------------------------
create or replace function public.enforce_evaluation_edit_permissions()
returns trigger as $$
declare
  can_edit_quality  boolean;
  can_edit_delivery boolean;
  can_approve       boolean;
begin
  if not exists (select 1 from user_profiles where id = auth.uid()) then
    raise exception 'No user_profiles row found for current user — cannot verify permissions';
  end if;

  can_edit_quality  := public.has_permission('eval_edit_quality');
  can_edit_delivery := public.has_permission('eval_edit_delivery');
  can_approve       := public.has_permission('eval_approve');

  if not can_edit_quality then
    if new.quality_score is distinct from old.quality_score
       or new.quality_comment is distinct from old.quality_comment then
      raise exception 'You do not have permission to edit Quality fields';
    end if;
  end if;

  if not can_edit_delivery then
    if new.delivery_score is distinct from old.delivery_score
       or new.purchase_score is distinct from old.purchase_score
       or new.delivery_comment is distinct from old.delivery_comment
       or new.shipment_status is distinct from old.shipment_status
       or new.no_shipment_reason is distinct from old.no_shipment_reason then
      raise exception 'You do not have permission to edit Delivery/Purchase fields';
    end if;
  end if;

  if new.status = 'approved' and old.status is distinct from 'approved' then
    if not can_approve then
      raise exception 'You do not have permission to approve an evaluation';
    end if;
    if new.quality_submitted_at is null or new.delivery_submitted_at is null then
      raise exception 'Cannot approve until both QA and CS/MP have submitted their sections';
    end if;
    new.approved_by = auth.uid();
    new.approved_at = now();
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop policy if exists "cs supervisor or admin can delete evaluations" on evaluations;
create policy "authorized can delete evaluations"
  on evaluations for delete
  to authenticated
  using (public.has_permission('eval_delete'));

-- ------------------------------------------------------------
-- 6) corrective_actions: rewrite create-permission helper, the edit
--    trigger, and the delete policy.
-- ------------------------------------------------------------
create or replace function public.can_create_ca()
returns boolean as $$
  select public.has_permission('ca_create');
$$ language sql stable security definer set search_path = public;

create or replace function public.enforce_ca_edit_permissions()
returns trigger as $$
declare
  full_edit       boolean;
  restricted_edit boolean;
begin
  if not exists (select 1 from user_profiles where id = auth.uid()) then
    raise exception 'No user_profiles row found for current user — cannot verify permissions';
  end if;

  full_edit := public.has_permission('ca_edit_full');
  if full_edit then
    return new;
  end if;

  restricted_edit := public.has_permission('ca_edit_restricted');
  if restricted_edit then
    if new.evaluation_id        is distinct from old.evaluation_id
       or new.seq_no            is distinct from old.seq_no
       or new.problem           is distinct from old.problem
       or new.responsible_person is distinct from old.responsible_person
       or new.start_date        is distinct from old.start_date
       or new.due_date          is distinct from old.due_date
       or new.finished_date     is distinct from old.finished_date
       or new.status            is distinct from old.status then
      raise exception 'You can only edit Root Cause and Corrective Action on an existing corrective action';
    end if;
    return new;
  end if;

  raise exception 'You do not have permission to edit an existing corrective action';
end;
$$ language plpgsql security definer set search_path = public;

drop policy if exists "cs supervisor or admin can delete corrective actions" on corrective_actions;
create policy "authorized can delete corrective actions"
  on corrective_actions for delete
  to authenticated
  using (public.has_permission('ca_delete'));

-- ------------------------------------------------------------
-- 7) evaluation_attachments: delete policy.
-- ------------------------------------------------------------
drop policy if exists "cs supervisor or admin can delete attachments" on evaluation_attachments;
create policy "authorized can delete attachments"
  on evaluation_attachments for delete
  to authenticated
  using (public.has_permission('attachment_delete'));

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * The department_role enum still has the dead 'supervisor' value
--   (see v0.7.0 notes) — it's not seeded here, so it effectively has
--   no permissions at all. Nothing should ever have that department
--   after v0.7.0's migration, so this doesn't matter in practice.
-- * If a NEW department value is ever added to the enum in the
--   future, remember to insert 5 (or however many rule_keys exist by
--   then) rows for it here too — has_permission() returns false
--   (i.e. no access) for any (rule_key, department) pair that has no
--   row, which is a safe default but easy to forget.
-- ============================================================
