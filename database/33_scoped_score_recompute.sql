-- ============================================================
-- 33_scoped_score_recompute.sql
-- Fixes a real, confirmed-live bug: CS/MP saving their own Delivery/
-- Purchase section got rejected with "You do not have permission to
-- edit Quality fields" (and, symmetrically, QA saving Quality would
-- have hit the same thing from the other side).
--
-- Root cause (two layers):
--   1. A freshly-created evaluation started with quality_score = 0,
--      delivery_score = 0, purchase_score = 0 (set explicitly by the
--      app's create-worksheet code) instead of the schema's intended
--      "nothing logged yet" defaults of 50 / 40 / 0.
--   2. recompute_evaluation_scores() always recalculated and wrote
--      ALL THREE score columns together, no matter which single
--      section actually changed. So when CS saved only their
--      Delivery checklist, this function ALSO recomputed
--      quality_score from its current value up to the "no
--      deductions yet" baseline (0 -> 50) — a real, detected change
--      — which enforce_evaluation_edit_permissions() then correctly
--      (from its own point of view) rejected, since CS doesn't have
--      eval_edit_quality permission. The permission check was doing
--      its job on a column it should never have been asked to touch
--      in the first place.
--
-- Fix: recompute_evaluation_scores() now takes an optional scope
-- ('quality' | 'delivery' | null for "everything", preserving exact
-- prior behavior for every existing caller that doesn't pass one —
-- imports, admin tooling, etc.) and only recalculates + writes the
-- column(s) that scope covers. The per-item trigger now derives the
-- right scope automatically from whichever criteria category the
-- changed item belongs to, so a live checklist tick never touches
-- the other section's score column either.
-- ============================================================

create or replace function public.recompute_evaluation_scores(p_evaluation_id uuid, p_scope text default null)
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
  if p_scope is null or p_scope = 'quality' then
    select coalesce(sum(full_score), 0) into base_quality
      from evaluation_criteria where category = 'quality' and full_score is not null;
    select coalesce(sum(ei.occurrence * ec.deduction_points), 0) into delta_quality
      from evaluation_items ei join evaluation_criteria ec on ec.id = ei.criteria_id
      where ei.evaluation_id = p_evaluation_id and ec.category = 'quality';
    new_quality := greatest(0, least(base_quality, base_quality + delta_quality));

    update evaluations set quality_score = new_quality
    where id = p_evaluation_id and scoring_mode = 'itemized';
  end if;

  if p_scope is null or p_scope = 'delivery' then
    select coalesce(sum(full_score), 0) into base_delivery
      from evaluation_criteria where category = 'delivery' and full_score is not null;
    select coalesce(sum(ei.occurrence * ec.deduction_points), 0) into delta_delivery
      from evaluation_items ei join evaluation_criteria ec on ec.id = ei.criteria_id
      where ei.evaluation_id = p_evaluation_id and ec.category = 'delivery';
    select coalesce(sum(ei.occurrence * ec.deduction_points), 0) into delta_purchase
      from evaluation_items ei join evaluation_criteria ec on ec.id = ei.criteria_id
      where ei.evaluation_id = p_evaluation_id and ec.category = 'purchase';
    new_delivery := greatest(0, least(base_delivery, base_delivery + delta_delivery));
    new_purchase := greatest(0, least(10, delta_purchase));

    update evaluations set delivery_score = new_delivery, purchase_score = new_purchase
    where id = p_evaluation_id and scoring_mode = 'itemized';
  end if;
end;
$$ language plpgsql security definer set search_path = public;

-- The per-item trigger now figures out the right scope from whichever
-- criteria category the changed item belongs to, instead of always
-- recomputing (and touching) every column.
create or replace function public.recompute_after_item_change()
returns trigger as $$
declare
  v_category text;
  v_scope text;
  v_eval_id uuid;
begin
  v_eval_id := coalesce(new.evaluation_id, old.evaluation_id);
  select category into v_category from evaluation_criteria where id = coalesce(new.criteria_id, old.criteria_id);
  v_scope := case when v_category in ('quality','environment') then 'quality'
                  when v_category in ('delivery','purchase') then 'delivery'
                  else null end; -- unrecognized category: fall back to recomputing everything, same as before

  perform public.recompute_evaluation_scores(v_eval_id, v_scope);
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$ language plpgsql security definer set search_path = public;

-- (triggers already point at these functions by name — create or
-- replace above is enough, no need to re-create the triggers)
