-- ============================================================
-- 20_two_tier_approval.sql
-- Restructures approval into two explicit steps and moves
-- corrective-action ownership from QA to CS/MP, per this session's
-- workflow discussion.
--
-- ⚠️ RUN IN TWO PARTS — same Postgres limitation as before (v0.7.0):
-- new enum values can't be used in the same transaction they're added
-- in. Run PART 1 alone first, wait for it to say Success, THEN run
-- PART 2 (everything else in this file).
-- ============================================================

-- ============================================================
-- PART 1 — run this alone first, nothing else in this file.
-- ============================================================
alter type department_role add value if not exists 'mp_supervisor';
alter type department_role add value if not exists 'opd_manager';
alter type eval_status add value if not exists 'sup_approved';
alter type eval_status add value if not exists 'mgr_approved';

-- ============================================================
-- PART 2 — run everything below this line AFTER Part 1 succeeded.
-- ============================================================

-- ------------------------------------------------------------
-- 1) New audit columns — separate stamps for each approval tier,
--    kept alongside (not replacing) the original approved_by/
--    approved_at, which are no longer set going forward (same
--    "leave dead things alone" pattern as the retired 'supervisor'
--    department value from v0.7.0).
-- ------------------------------------------------------------
alter table evaluations
  add column sup_approved_by  uuid references auth.users(id),
  add column sup_approved_at  timestamptz,
  add column mgr_approved_by  uuid references auth.users(id),
  add column mgr_approved_at  timestamptz;

-- ------------------------------------------------------------
-- 2) Permission rules — mp_supervisor mirrors cs_supervisor on every
--    existing rule_key (same rights, different department value so
--    the audit trail shows which supervisor actually acted).
--    opd_manager gets its own narrow set: only the two new approve
--    rule_keys, nothing else (not master data, not CA, not scores).
-- ------------------------------------------------------------
insert into permission_rules (rule_key, department, allowed)
select rule_key, 'mp_supervisor', allowed
from permission_rules where department = 'cs_supervisor'
on conflict (rule_key, department) do nothing;

insert into permission_rules (rule_key, department, allowed) values
  ('eval_edit_quality',  'opd_manager', false),
  ('eval_edit_delivery', 'opd_manager', false),
  ('eval_delete',        'opd_manager', false),
  ('ca_create',          'opd_manager', false),
  ('ca_edit_full',       'opd_manager', false),
  ('ca_edit_restricted', 'opd_manager', false),
  ('ca_close',           'opd_manager', false),
  ('ca_delete',          'opd_manager', false),
  ('attachment_upload',  'opd_manager', true),
  ('attachment_delete',  'opd_manager', false),
  ('master_data_manage', 'opd_manager', false)
on conflict (rule_key, department) do nothing;

-- New rule_keys for the two approval tiers, replacing the old
-- 'eval_approve' (left in the table, unused — nothing reads it
-- anymore after this migration, same retire-in-place pattern).
insert into permission_rules (rule_key, department, allowed) values
  ('eval_sup_approve', 'qa',            false),
  ('eval_sup_approve', 'cs',            false),
  ('eval_sup_approve', 'mp',            false),
  ('eval_sup_approve', 'cs_supervisor', true),
  ('eval_sup_approve', 'mp_supervisor', true),
  ('eval_sup_approve', 'opd_manager',   false),
  ('eval_sup_approve', 'admin',         true),

  ('eval_mgr_approve', 'qa',            false),
  ('eval_mgr_approve', 'cs',            false),
  ('eval_mgr_approve', 'mp',            false),
  ('eval_mgr_approve', 'cs_supervisor', false),
  ('eval_mgr_approve', 'mp_supervisor', false),
  ('eval_mgr_approve', 'opd_manager',   true),
  ('eval_mgr_approve', 'admin',         true)
on conflict (rule_key, department) do nothing;

-- CA ownership moves to CS/MP: full edit rights for cs/mp now (was
-- QA-restricted before), QA drops out of CA entirely. ca_delete stays
-- supervisor/admin-only ("Supervisor keeps override/delete").
update permission_rules set allowed = false where rule_key in ('ca_edit_restricted','ca_close') and department = 'qa';
update permission_rules set allowed = true  where rule_key = 'ca_edit_full' and department in ('cs','mp');
update permission_rules set allowed = true  where rule_key = 'ca_delete'   and department = 'mp_supervisor';
update permission_rules set allowed = true  where rule_key = 'ca_create'  and department = 'mp_supervisor';
update permission_rules set allowed = true  where rule_key = 'attachment_delete' and department = 'mp_supervisor';
update permission_rules set allowed = true  where rule_key = 'eval_edit_delivery' and department = 'mp_supervisor';
update permission_rules set allowed = true  where rule_key = 'eval_delete' and department = 'mp_supervisor';
update permission_rules set allowed = true  where rule_key = 'attachment_upload' and department = 'mp_supervisor';

-- ------------------------------------------------------------
-- 3) enforce_evaluation_edit_permissions — two-tier approve logic.
--    sup_approved requires eval_sup_approve + both sections submitted.
--    mgr_approved requires eval_mgr_approve + already sup_approved.
-- ------------------------------------------------------------
create or replace function public.enforce_evaluation_edit_permissions()
returns trigger as $$
declare
  can_edit_quality  boolean;
  can_edit_delivery boolean;
  can_sup_approve   boolean;
  can_mgr_approve   boolean;
begin
  if not exists (select 1 from user_profiles where id = auth.uid()) then
    raise exception 'No user_profiles row found for current user — cannot verify permissions';
  end if;

  can_edit_quality  := public.has_permission('eval_edit_quality');
  can_edit_delivery := public.has_permission('eval_edit_delivery');
  can_sup_approve   := public.has_permission('eval_sup_approve');
  can_mgr_approve   := public.has_permission('eval_mgr_approve');

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

  if new.status = 'sup_approved' and old.status is distinct from 'sup_approved' then
    if not can_sup_approve then
      raise exception 'You do not have permission to give Supervisor Approval';
    end if;
    if new.quality_submitted_at is null or new.delivery_submitted_at is null then
      raise exception 'Cannot approve until both QA and CS/MP have submitted their sections';
    end if;
    new.sup_approved_by = auth.uid();
    new.sup_approved_at = now();
  end if;

  if new.status = 'mgr_approved' and old.status is distinct from 'mgr_approved' then
    if not can_mgr_approve then
      raise exception 'You do not have permission to give Manager Approval';
    end if;
    if old.status is distinct from 'sup_approved' then
      raise exception 'Cannot give Manager Approval until Supervisor Approval is done first';
    end if;
    new.mgr_approved_by = auth.uid();
    new.mgr_approved_at = now();
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- 4) auto_create_corrective_action — now fires on mgr_approved
--    (final approval), not the old single 'approved' status.
-- ------------------------------------------------------------
create or replace function public.auto_create_corrective_action()
returns trigger as $$
declare
  next_seq int;
  should_create boolean;
begin
  if tg_op = 'INSERT' then
    should_create := (new.status = 'mgr_approved' and new.grade in ('C', 'D'));
  else
    should_create := (new.status = 'mgr_approved'
                       and old.status is distinct from 'mgr_approved'
                       and new.grade in ('C', 'D'));
  end if;

  if should_create and not exists (select 1 from corrective_actions where evaluation_id = new.id) then
    select coalesce(max(seq_no), 0) + 1 into next_seq
    from corrective_actions where evaluation_id = new.id;

    insert into corrective_actions (evaluation_id, seq_no, problem, status, start_date, due_date)
    values (
      new.id,
      next_seq,
      'Auto-generated: evaluation scored ' || new.total_score || '% (Grade ' || new.grade || ') — supplier must submit an improvement plan.',
      'open',
      current_date,
      public.add_working_days(current_date, 5)
    );
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- 5) enforce_ca_edit_permissions — CS/MP now get full edit rights
--    (same as before, just driven by ca_edit_full which now includes
--    cs/mp per the permission_rules update above). QA no longer has
--    any special-cased path — if they somehow still have
--    ca_edit_restricted/ca_close set true, step 2 above already
--    turned those off; this function doesn't need to change, it
--    already just reads has_permission() generically.
-- ------------------------------------------------------------
-- (no change needed — enforce_ca_edit_permissions from 13_dynamic_
-- permission_rules.sql already reads ca_edit_full/ca_edit_restricted
-- generically; updating the rules table in step 2 is sufficient)

-- ------------------------------------------------------------
-- Sanity check
-- ------------------------------------------------------------
select rule_key, department, allowed from permission_rules
where rule_key in ('eval_sup_approve','eval_mgr_approve','ca_edit_full','ca_delete')
order by rule_key, department;
