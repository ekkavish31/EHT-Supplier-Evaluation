-- ============================================================
-- 22_reject_flow.sql
-- Reject always returns to 'draft' regardless of which tier rejected
-- (per this session's decision) — QA and CS/MP must resubmit both
-- sections from scratch. Whoever has eval_sup_approve OR
-- eval_mgr_approve can reject (either tier is close enough in
-- seniority for this action).
--
-- No cascading concerns: corrective_actions are only auto-created on
-- mgr_approved (final approval), so rejecting at either the
-- Supervisor or Manager review step happens before any CA could ever
-- have been created — nothing downstream to unwind.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

alter table evaluations
  add column rejected_by     uuid references auth.users(id),
  add column rejected_at     timestamptz,
  add column rejection_reason text;

comment on column evaluations.rejection_reason is 'Required whenever an evaluation is rejected back to draft by a Supervisor or Manager — tells QA/CS-MP what to fix before resubmitting.';

create or replace function public.enforce_evaluation_edit_permissions()
returns trigger as $$
declare
  can_edit_quality  boolean;
  can_edit_delivery boolean;
  can_sup_approve   boolean;
  can_mgr_approve   boolean;
  is_reject         boolean := false;
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
