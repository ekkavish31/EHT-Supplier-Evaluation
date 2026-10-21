-- ============================================================
-- 10_phase3_autocalc.sql
-- Phase 3 — auto-calculate quality/delivery/purchase scores from
-- evaluation_items, instead of typing the 3 totals by hand.
--
-- `evaluation_items` has had RLS enabled since v0.1.0 with ZERO
-- policies (same bug class as corrective_actions/evaluation_criteria)
-- — completely inaccessible until this migration.
--
-- DESIGN CHOICE — coexistence with manual entry:
--   Existing evaluations (all 574+ of them) were entered as plain
--   numbers, not built from evaluation_items. If this auto-calc
--   applied unconditionally, adding a single itemized entry to an
--   evaluation would immediately overwrite its OTHER two category
--   scores with "no items = full marks", silently corrupting real
--   historical numbers. So each evaluation now has a `scoring_mode`:
--     'manual'   (default) — quality/delivery/purchase typed by hand,
--                exactly like before. evaluation_items are ignored.
--     'itemized' — the 3 scores are computed FROM evaluation_items
--                and become read-only in the UI.
--   Switching an evaluation to 'itemized' recomputes it immediately
--   from whatever items exist (zero items = category at its "empty"
--   value — full marks for quality/delivery since nothing went wrong
--   yet, zero for purchase since nothing's been credited yet).
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1) evaluations.scoring_mode
-- ------------------------------------------------------------
alter table evaluations
  add column scoring_mode text not null default 'manual'
    check (scoring_mode in ('manual', 'itemized'));

comment on column evaluations.scoring_mode is
  '''manual'' = quality/delivery/purchase scores typed directly (legacy behavior, all data before v0.6.0). ''itemized'' = scores are computed from evaluation_items and are read-only in the UI.';

-- ------------------------------------------------------------
-- 2) RLS for evaluation_items — read for everyone authenticated;
--    write left broad/authenticated-only for now, same precedent as
--    corrective_actions (v14) — department-level column locking on
--    evaluation_items can be added later if needed.
-- ------------------------------------------------------------
create policy "authenticated can read evaluation items"
  on evaluation_items for select
  to authenticated
  using (true);

create policy "authenticated can insert evaluation items"
  on evaluation_items for insert
  to authenticated
  with check (true);

create policy "authenticated can update evaluation items"
  on evaluation_items for update
  to authenticated
  using (true);

create policy "authenticated can delete evaluation items"
  on evaluation_items for delete
  to authenticated
  using (true);

-- ------------------------------------------------------------
-- 3) Recompute function — sums full_score per sub-group (A1/A2/B/C in
--    FM0704-3 terms; here just "distinct non-null full_score values
--    per category") as the base, then applies each logged item's
--    occurrence x deduction_points on top:
--      - quality/delivery: base is the category's full marks (50/40
--        combined across sub-groups for quality, 40 for delivery),
--        deduction_points are negative, so more occurrences = lower
--        score. Clamped to [0, base].
--      - purchase: base is 0 (nothing credited yet), deduction_points
--        are POSITIVE per tier (see 02_seed_data.sql — purchase rows
--        store e.g. +10/+5/+2, they're credits not deductions despite
--        the column name), clamped to [0, 10]. Selecting more than one
--        tier just sums and clamps rather than being rejected outright
--        — good enough for now, tighten later if double-selection
--        turns out to be a real problem in practice.
-- ------------------------------------------------------------
create or replace function public.recompute_evaluation_scores(p_evaluation_id uuid)
returns void as $$
declare
  base_quality numeric(5,2);
  base_delivery numeric(5,2);
  delta_quality numeric(5,2);
  delta_delivery numeric(5,2);
  delta_purchase numeric(5,2);
  new_quality numeric(5,2);
  new_delivery numeric(5,2);
  new_purchase numeric(5,2);
begin
  select coalesce(sum(full_score), 0) into base_quality
    from evaluation_criteria where category = 'quality' and full_score is not null;
  select coalesce(sum(full_score), 0) into base_delivery
    from evaluation_criteria where category = 'delivery' and full_score is not null;

  select coalesce(sum(ei.occurrence * ec.deduction_points), 0) into delta_quality
    from evaluation_items ei join evaluation_criteria ec on ec.id = ei.criteria_id
    where ei.evaluation_id = p_evaluation_id and ec.category = 'quality';

  select coalesce(sum(ei.occurrence * ec.deduction_points), 0) into delta_delivery
    from evaluation_items ei join evaluation_criteria ec on ec.id = ei.criteria_id
    where ei.evaluation_id = p_evaluation_id and ec.category = 'delivery';

  select coalesce(sum(ei.occurrence * ec.deduction_points), 0) into delta_purchase
    from evaluation_items ei join evaluation_criteria ec on ec.id = ei.criteria_id
    where ei.evaluation_id = p_evaluation_id and ec.category = 'purchase';

  new_quality  := greatest(0, least(base_quality,  base_quality  + delta_quality));
  new_delivery := greatest(0, least(base_delivery, base_delivery + delta_delivery));
  new_purchase := greatest(0, least(10, delta_purchase));

  update evaluations
  set quality_score  = new_quality,
      delivery_score = new_delivery,
      purchase_score = new_purchase
  where id = p_evaluation_id
    and scoring_mode = 'itemized';  -- never touch a 'manual' evaluation
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- 4) Also store the per-item points_applied (occurrence x
--    deduction_points) for display/audit, and trigger the recompute
--    above whenever an item changes.
-- ------------------------------------------------------------
create or replace function public.set_item_points_applied()
returns trigger as $$
begin
  new.points_applied := new.occurrence * (
    select deduction_points from evaluation_criteria where id = new.criteria_id
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.recompute_after_item_change()
returns trigger as $$
begin
  if tg_op = 'DELETE' then
    perform public.recompute_evaluation_scores(old.evaluation_id);
    return old;
  else
    perform public.recompute_evaluation_scores(new.evaluation_id);
    return new;
  end if;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_evaluation_item_points on evaluation_items;
create trigger trg_evaluation_item_points
  before insert or update on evaluation_items
  for each row execute function public.set_item_points_applied();

drop trigger if exists trg_evaluation_item_recompute on evaluation_items;
create trigger trg_evaluation_item_recompute
  after insert or update or delete on evaluation_items
  for each row execute function public.recompute_after_item_change();

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * Switching evaluation.scoring_mode from 'manual' to 'itemized' in
--   the app immediately triggers a recompute in the UI (calls
--   recompute via a no-op item touch, or simply shows 50/40/0 until
--   the first item is saved) — an evaluation with no items yet reads
--   as quality=50, delivery=40, purchase=0, which is the correct
--   "nothing logged yet" state, not a bug.
-- * recompute_evaluation_scores() updating `evaluations` still passes
--   through enforce_evaluation_edit_permissions (v0.3.0) and
--   compute_evaluation_score (v0.4.0) as normal BEFORE UPDATE
--   triggers — total_score/grade and the No-Shipment rule apply on
--   top of whatever quality/delivery/purchase this produces, no
--   double-counting.
-- ============================================================
