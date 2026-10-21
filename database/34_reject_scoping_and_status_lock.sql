-- ============================================================
-- 34_reject_scoping_and_status_lock.sql
-- Two changes to enforce_evaluation_edit_permissions(), both from
-- this session's workflow review:
--
--   1. Reject can now target just Quality, just Delivery/Purchase,
--      or both — instead of always clearing both submitted_at
--      timestamps no matter which side actually had the problem.
--      Also scoped by stage: only a Supervisor can reject while the
--      evaluation is still at the Supervisor-review point (status
--      stays 'draft', both were submitted); only a Manager can reject
--      once it's at 'sup_approved' (a Supervisor no longer gets to
--      undo their own already-given approval from here). Previously
--      either permission could reject at either stage.
--
--   2. Editing quality_score/delivery_score (and their related
--      fields) is now locked based on the evaluation's status at the
--      DATABASE level, not just the UI:
--        - sup_approved: Quality locked for everyone. Delivery/
--          Purchase stays editable, but only for whoever holds
--          eval_sup_approve (a Supervisor fixing their own team's
--          data without a full Reject round-trip).
--        - mgr_approved and anything later: locked for everyone.
--      Previously the database only checked "do you have
--      eval_edit_quality/eval_edit_delivery at all", never the
--      evaluation's status — someone with a valid edit permission
--      could edit a closed evaluation by calling the API directly,
--      bypassing the UI's own lock (added client-side in an earlier
--      session).
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

create or replace function public.enforce_evaluation_edit_permissions()
returns trigger as $$
declare
  can_edit_quality  boolean;
  can_edit_delivery boolean;
  can_sup_approve   boolean;
  can_mgr_approve   boolean;
  can_mark_sent     boolean;
  quality_locked    boolean;
  delivery_locked   boolean;
  is_sup_stage_reject boolean := false;
  is_mgr_stage_reject boolean := false;
begin
  if not exists (select 1 from user_profiles where id = auth.uid()) then
    raise exception 'No user_profiles row found for current user — cannot verify permissions';
  end if;

  can_edit_quality  := public.has_permission('eval_edit_quality');
  can_edit_delivery := public.has_permission('eval_edit_delivery');
  can_sup_approve   := public.has_permission('eval_sup_approve');
  can_mgr_approve   := public.has_permission('eval_mgr_approve');
  can_mark_sent     := public.has_permission('eval_mark_sent');

  -- NEW: status-based lock, on top of the permission check that was
  -- already here. Uses old.status — the state the editor was actually
  -- looking at when they made this change.
  quality_locked  := old.status in ('sup_approved','mgr_approved','sent_to_supplier','acknowledged','follow_up_required');
  delivery_locked := old.status in ('mgr_approved','sent_to_supplier','acknowledged','follow_up_required')
                      or (old.status = 'sup_approved' and not can_sup_approve);

  if not can_edit_quality or quality_locked then
    if new.quality_score is distinct from old.quality_score
       or new.quality_comment is distinct from old.quality_comment then
      raise exception 'You do not have permission to edit Quality fields';
    end if;
  end if;

  if not can_edit_delivery or delivery_locked then
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

  if new.status = 'sent_to_supplier' and old.status is distinct from 'sent_to_supplier' then
    if not can_mark_sent then
      raise exception 'You do not have permission to mark this evaluation as sent to supplier';
    end if;
    if old.status is distinct from 'mgr_approved' then
      raise exception 'Cannot mark as sent until Manager Approval is done';
    end if;
    new.sent_at = coalesce(new.sent_at, now());
  end if;

  if new.status = 'acknowledged' and old.status is distinct from 'acknowledged' then
    if old.status is distinct from 'sent_to_supplier' then
      raise exception 'Cannot close an evaluation before it has been marked sent to supplier';
    end if;
    new.acknowledged_at = coalesce(new.acknowledged_at, now());
  end if;

  -- NEW: reject detection split into its two stages, each requiring
  -- its own matching permission — and no longer requires BOTH
  -- submitted_at to clear; either one alone (the department that was
  -- actually wrong) is enough to count as a reject at the Supervisor
  -- stage.
  is_sup_stage_reject := (
    old.status = 'draft' and new.status = 'draft'
    and (
      (old.quality_submitted_at is not null and new.quality_submitted_at is null)
      or (old.delivery_submitted_at is not null and new.delivery_submitted_at is null)
    )
  );
  is_mgr_stage_reject := (old.status = 'sup_approved' and new.status = 'draft');

  if is_sup_stage_reject then
    if not can_sup_approve then
      raise exception 'Only a Supervisor can reject at this stage';
    end if;
    if new.rejection_reason is null or length(trim(new.rejection_reason)) = 0 then
      raise exception 'A rejection reason is required';
    end if;
    new.rejected_by = auth.uid();
    new.rejected_at = now();
  end if;

  if is_mgr_stage_reject then
    if not can_mgr_approve then
      raise exception 'Only a Manager can reject at this stage';
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

-- (trigger already points at this function by name — create or
-- replace above is enough, no need to re-create the trigger)
