-- ============================================================
-- 28_mark_sent_and_ca_close_sync.sql
-- Closes a real gap found reviewing the approval flow: grade A/B
-- evaluations jumped straight from mgr_approved to acknowledged in
-- one update, never actually passing through sent_to_supplier — so
-- the DB never recorded "this was sent" as a distinct fact, and
-- nothing stopped a client from skipping straight to acknowledged
-- without going through mgr_approved -> sent_to_supplier first. This
-- migration:
--   1. Adds a dedicated eval_mark_sent permission (who's allowed to
--      mark something as sent, separate from who can edit/approve it)
--   2. Makes both transitions into sent_to_supplier and acknowledged
--      real, checked invariants in the trigger — no more silent
--      status-skipping regardless of what the client sends
--   3. Adds a trigger so closing the LAST open Corrective Action on
--      an evaluation automatically flips that evaluation to
--      acknowledged — closing a CA already meant "this case is done";
--      now the evaluation's own status reflects that automatically
--      instead of being stuck at sent_to_supplier forever
--   4. Backfills any evaluation already stuck at sent_to_supplier
--      whose corrective actions are all closed (or has none)
--
-- Run this BEFORE deploying the updated app.js/index.html — if
-- deployed out of order, the Mark Sent button will error until this
-- migration lands (the new permission row won't exist in the DB yet).
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. New permission: eval_mark_sent
-- ------------------------------------------------------------
insert into permission_rules (rule_key, department, allowed) values
  ('eval_mark_sent', 'qa',            false),
  ('eval_mark_sent', 'cs',            true),
  ('eval_mark_sent', 'mp',            true),
  ('eval_mark_sent', 'cs_supervisor', true),
  ('eval_mark_sent', 'mp_supervisor', true),
  ('eval_mark_sent', 'opd_manager',   true),
  ('eval_mark_sent', 'admin',         true)
on conflict (rule_key, department) do nothing;

-- ------------------------------------------------------------
-- 2. Extend enforce_evaluation_edit_permissions() — add real
--    invariant checks for entering sent_to_supplier and acknowledged.
--    Everything above the two new blocks is unchanged from
--    22_reject_flow.sql.
-- ------------------------------------------------------------
create or replace function public.enforce_evaluation_edit_permissions()
returns trigger as $$
declare
  can_edit_quality  boolean;
  can_edit_delivery boolean;
  can_sup_approve   boolean;
  can_mgr_approve   boolean;
  can_mark_sent     boolean;
  is_reject         boolean := false;
begin
  if not exists (select 1 from user_profiles where id = auth.uid()) then
    raise exception 'No user_profiles row found for current user — cannot verify permissions';
  end if;

  can_edit_quality  := public.has_permission('eval_edit_quality');
  can_edit_delivery := public.has_permission('eval_edit_delivery');
  can_sup_approve   := public.has_permission('eval_sup_approve');
  can_mgr_approve   := public.has_permission('eval_mgr_approve');
  can_mark_sent     := public.has_permission('eval_mark_sent');

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

  -- NEW: entering sent_to_supplier requires eval_mark_sent AND must
  -- come directly from mgr_approved — no skipping ahead of Manager
  -- Approval by sending a status straight from the client.
  if new.status = 'sent_to_supplier' and old.status is distinct from 'sent_to_supplier' then
    if not can_mark_sent then
      raise exception 'You do not have permission to mark this evaluation as sent to supplier';
    end if;
    if old.status is distinct from 'mgr_approved' then
      raise exception 'Cannot mark as sent until Manager Approval is done';
    end if;
    new.sent_at = coalesce(new.sent_at, now());
  end if;

  -- NEW: entering acknowledged must come from sent_to_supplier — closes
  -- the gap where grade A/B evaluations used to jump straight from
  -- mgr_approved to acknowledged, skipping sent_to_supplier entirely.
  -- Every evaluation, A/B or C/D, now genuinely passes through
  -- sent_to_supplier on its way to being closed.
  if new.status = 'acknowledged' and old.status is distinct from 'acknowledged' then
    if old.status is distinct from 'sent_to_supplier' then
      raise exception 'Cannot close an evaluation before it has been marked sent to supplier';
    end if;
    new.acknowledged_at = coalesce(new.acknowledged_at, now());
  end if;

  -- Reject detection: status stays 'draft' the whole time a Supervisor
  -- is reviewing (submit only sets the *_submitted_at timestamps, not
  -- status) — so a Supervisor-stage reject looks like "both submitted
  -- timestamps get cleared while status stays draft", not a status
  -- transition at all. A Manager-stage reject IS a real transition:
  -- sup_approved -> draft.
  if (old.status = 'draft' and new.status = 'draft'
      and old.quality_submitted_at is not null and old.delivery_submitted_at is not null
      and new.quality_submitted_at is null and new.delivery_submitted_at is null)
     or (old.status = 'sup_approved' and new.status = 'draft') then
    is_reject := true;
  end if;

  if is_reject then
    if not (can_sup_approve or can_mgr_approve) then
      raise exception 'You do not have permission to reject an evaluation';
    end if;
    if new.rejection_reason is null or length(trim(new.rejection_reason)) = 0 then
      raise exception 'A rejection reason is required';
    end if;
    new.rejected_by = auth.uid();
    new.rejected_at = now();
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- 3. Closing the last open CA on an evaluation auto-acknowledges it.
--    security definer because the person closing a CA (cs_close
--    permission, which QA also has) may not otherwise be allowed to
--    write evaluations.status directly — same pattern already used by
--    auto_create_corrective_action for the opposite direction.
-- ------------------------------------------------------------
create or replace function public.sync_evaluation_on_ca_close()
returns trigger as $$
declare
  all_closed boolean;
begin
  if new.status = 'closed' and old.status is distinct from 'closed' then
    select not exists (
      select 1 from corrective_actions
      where evaluation_id = new.evaluation_id and status <> 'closed'
    ) into all_closed;

    if all_closed then
      update evaluations
      set status = 'acknowledged',
          acknowledged_at = now()
      where id = new.evaluation_id
        and status = 'sent_to_supplier';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_sync_eval_on_ca_close on corrective_actions;
create trigger trg_sync_eval_on_ca_close
  after update on corrective_actions
  for each row execute function public.sync_evaluation_on_ca_close();

-- ------------------------------------------------------------
-- 4. One-time backfill — evaluations already stuck at
--    sent_to_supplier whose corrective actions (if any) are all
--    closed already. Dry-run count first, then the real update.
-- ------------------------------------------------------------
select count(*) as will_be_closed
from evaluations e
where e.status = 'sent_to_supplier'
  and not exists (
    select 1 from corrective_actions ca
    where ca.evaluation_id = e.id and ca.status <> 'closed'
  );

update evaluations e
set status = 'acknowledged', acknowledged_at = now()
where e.status = 'sent_to_supplier'
  and not exists (
    select 1 from corrective_actions ca
    where ca.evaluation_id = e.id and ca.status <> 'closed'
  );

-- ------------------------------------------------------------
-- 5. Sanity checks
-- ------------------------------------------------------------
select rule_key, department, allowed from permission_rules where rule_key = 'eval_mark_sent' order by department;
select count(*) as remaining_sent_to_supplier from evaluations where status = 'sent_to_supplier';

insert into app_schema_version (id, version, package_version)
values (1, 28, 'v54')
on conflict (id) do update
set version = excluded.version, package_version = excluded.package_version, applied_at = now();
