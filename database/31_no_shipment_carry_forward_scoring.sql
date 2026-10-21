-- ============================================================
-- 31_no_shipment_carry_forward_scoring.sql
-- Items 10-11 from the Dashboard/Profile/Scoring review:
--
-- 10. New "Order Volume from E&H" field on each supplier — the
--     Purchase-tier score from whichever month most recently actually
--     had a real shipment (shipment_status = 'normal'). Shown on the
--     Supplier Profile.
--
-- 11. New No-Shipment scoring formula. Worked example that this was
--     derived from (from chat): a supplier with Q=50, D=40, S=2 in a
--     normal month (total 92) who has an equally-clean No-Shipment
--     month next should ALSO land on 92, not the old formula's 100 —
--     because "no mistake this month" should score the same as "no
--     mistake last month with a real shipment", not artificially
--     higher just because Delivery/Purchase got excluded.
--       quality_scaled = quality_score * 1.8    (0-50 -> 0-90, so a
--         quality deduction hits proportionally harder this month —
--         intentional: with nothing else to grade on, Quality carries
--         everything, so a mistake here should weigh more, not less)
--       total = quality_scaled + carried_purchase_score  (0-10, from
--         item 10's stored value; 0 if the supplier has literally
--         never had a normal-shipment month to carry from)
--       applicable_weight = 100 always now (was 50, Quality-only,
--         before this change) — No-Shipment is no longer a reduced-
--         denominator special case, just a different mix of the same
--         100-point scale every month uses.
--
-- Per explicit instruction: this does NOT retroactively recompute any
-- existing evaluation's score — only future inserts/updates (via the
-- trigger) use the new formula. Existing rows keep their current
-- raw_score/applicable_weight/total_score/grade exactly as-is (see
-- step 2 below, which preserves current values across the column-type
-- change rather than recalculating them).
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Item 10 — carry-forward purchase reference on suppliers
-- ------------------------------------------------------------
alter table suppliers
  add column last_purchase_score numeric(4,2),
  add column last_purchase_period text;

comment on column suppliers.last_purchase_score is 'Purchase-tier score (0-10) from this supplier''s most recent evaluation with shipment_status = normal. Used as item 11''s carried-forward Purchase value for No-Shipment months. Null until this supplier has had at least one normal-shipment evaluation.';
comment on column suppliers.last_purchase_period is 'Which month last_purchase_score came from, as YYYY-MM, for display context (e.g. "Order Volume from E&H" on the Supplier Profile).';

-- Backfill from existing history — this is seeding new REFERENCE data
-- from facts that already happened, not recalculating any evaluation's
-- score, so it's a one-time catch-up rather than something that
-- conflicts with "don't recompute old scores" above.
update suppliers s
set last_purchase_score = sub.purchase_score,
    last_purchase_period = sub.year || '-' || lpad(sub.month::text, 2, '0')
from (
  select distinct on (supplier_id) supplier_id, purchase_score, year, month
  from evaluations
  where shipment_status = 'normal'
  order by supplier_id, year desc, month desc
) sub
where s.id = sub.supplier_id;

-- ------------------------------------------------------------
-- 2) Convert raw_score/applicable_weight from generated columns to
--    plain columns the trigger can set directly — required because
--    the new No-Shipment formula needs to look up another table
--    (suppliers.last_purchase_score), which a GENERATED column cannot
--    do (it may only reference other columns in the same row).
--    Existing values are captured and restored unchanged, so no
--    existing evaluation's numbers move as a side effect of this
--    migration itself.
-- ------------------------------------------------------------
alter table evaluations add column raw_score_carry numeric(5,2);
alter table evaluations add column applicable_weight_carry numeric(5,2);
-- This UPDATE touches every row in evaluations, which would otherwise
-- fire trg_enforce_evaluation_edit — that trigger checks auth.uid()
-- against user_profiles, which is null when run from the SQL editor
-- (no logged-in app user) and would block the statement. Disable it
-- for just this one bulk, structural copy (not a real content edit).
alter table evaluations disable trigger trg_enforce_evaluation_edit;
update evaluations set raw_score_carry = raw_score, applicable_weight_carry = applicable_weight;
alter table evaluations enable trigger trg_enforce_evaluation_edit;
alter table evaluations drop column raw_score;
alter table evaluations drop column applicable_weight;
alter table evaluations rename column raw_score_carry to raw_score;
alter table evaluations rename column applicable_weight_carry to applicable_weight;

comment on column evaluations.raw_score is 'Points actually scored this month, on whatever scale applicable_weight uses that month. Now trigger-maintained (see compute_evaluation_score), not a generated column — a No-Shipment month needs to read suppliers.last_purchase_score, which a generated column cannot do.';
comment on column evaluations.applicable_weight is 'Always 100 as of this migration — No-Shipment used to reduce this to 50 (Quality-only); it now uses the full 100-point scale with Quality scaled up and Purchase carried forward instead. Kept as a column (not hardcoded 100 everywhere) in case a future rule needs a different scale again.';

-- ------------------------------------------------------------
-- 3) The new compute_evaluation_score() trigger.
--    security definer: a normal-shipment save now also writes to
--    suppliers.last_purchase_score/period, a table the saving user
--    (QA/CS/MP) may not otherwise have UPDATE rights on directly —
--    same reasoning as auto_create_corrective_action and
--    sync_evaluation_on_ca_close already use for their own
--    cross-table writes.
-- ------------------------------------------------------------
create or replace function public.compute_evaluation_score()
returns trigger as $$
declare
  v_carried_purchase numeric(5,2);
  v_quality_scaled numeric(5,2);
begin
  if new.shipment_status = 'no_shipment' then
    select last_purchase_score into v_carried_purchase
    from suppliers where id = new.supplier_id;
    v_carried_purchase := coalesce(v_carried_purchase, 0);

    v_quality_scaled := round(new.quality_score * 1.8, 2);

    new.raw_score := v_quality_scaled + v_carried_purchase;
    new.applicable_weight := 100;
  else
    new.raw_score := new.quality_score + new.delivery_score + new.purchase_score;
    new.applicable_weight := 100;

    -- Record this as the new "last known" purchase reference for this
    -- supplier, for whichever future month might need to carry it.
    update suppliers
    set last_purchase_score = new.purchase_score,
        last_purchase_period = new.year || '-' || lpad(new.month::text, 2, '0')
    where id = new.supplier_id;
  end if;

  new.total_score := round((new.raw_score / new.applicable_weight) * 100, 2);

  new.grade := case
    when new.total_score >= 100 then 'A'::eval_grade
    when new.total_score >= 80  then 'B'::eval_grade
    when new.total_score >= 70  then 'C'::eval_grade
    else 'D'::eval_grade
  end;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- (trigger trg_compute_evaluation_score already points at this
-- function by name — create or replace above is enough)

-- ------------------------------------------------------------
-- Sanity checks
-- ------------------------------------------------------------
-- How many suppliers now have a carried-forward reference:
select count(*) as suppliers_with_last_purchase from suppliers where last_purchase_score is not null;
-- Spot-check a few:
select code, name, last_purchase_score, last_purchase_period from suppliers where last_purchase_score is not null order by code limit 10;
