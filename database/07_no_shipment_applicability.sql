-- ============================================================
-- 07_no_shipment_applicability.sql
-- Phase A — fix the "No Shipment" score-normalization bug
--
-- PROBLEM (confirmed against real July 2026 data — 5 of 30 suppliers
-- this month: ETO, AKIYAMA JP, DAIDO, KYOTO, UGITECH):
--   Old Excel process, when a supplier has no shipment that month,
--   shows Quality 50/50 raw but a final result of 83.33% / Grade B.
--   That 83.33% = 50 / 60 — it excludes Delivery's 40-point weight from
--   the denominator but forgets to also exclude Purchase's 10-point
--   weight, even though Purchase is equally inapplicable with no
--   shipment. The intended rule (confirmed in the workflow proposal
--   and matching FM0704-3's own logic) is: when a category doesn't
--   apply, exclude its FULL weight from BOTH numerator and
--   denominator. Quality 50/50 with Delivery+Purchase not applicable
--   should be 50/50 = 100% / Grade A, not 83.33% / B.
--
--   Separately, this app's own `evaluations` table had the same class
--   of bug from a different angle: `total_score`/`grade` were summed
--   from raw points with no "applicable" concept at all, AND new rows
--   defaulted to quality_score=50 (full), delivery_score=40 (full),
--   purchase_score=0 — meaning an evaluation nobody has touched yet
--   already looks like a fully-scored 90/B, instead of looking
--   unfinished. Both are fixed here.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Add shipment/applicability tracking
-- ------------------------------------------------------------
alter table evaluations
  add column shipment_status text not null default 'normal'
    check (shipment_status in ('normal', 'no_shipment')),
  add column no_shipment_reason text;

alter table evaluations
  add constraint chk_no_shipment_reason
    check (shipment_status <> 'no_shipment' or no_shipment_reason is not null);

comment on column evaluations.shipment_status is
  '''normal'' = Delivery & Purchase both apply as usual. ''no_shipment'' = no shipment/purchase this month, so Delivery (40) and Purchase (10) are excluded from both the raw score and the 100-point denominator; only Quality (50) counts.';
comment on column evaluations.no_shipment_reason is
  'Required whenever shipment_status = ''no_shipment'' — why there was no shipment/purchase this month.';

-- ------------------------------------------------------------
-- 2) Fix misleading defaults — an untouched row should look
--    unfinished (0s → Grade D), not like a good B grade.
-- ------------------------------------------------------------
alter table evaluations
  alter column quality_score set default 0,
  alter column delivery_score set default 0,
  alter column purchase_score set default 0;

-- ------------------------------------------------------------
-- 3) Replace the old raw-sum total_score/grade with normalized,
--    applicability-aware versions.
--
--    total_score is now always "score out of 100": when
--    shipment_status = 'normal' this is identical to the old
--    behaviour (weights already summed to 100), so nothing changes
--    for the common case. Only the no_shipment case changes.
--
--    Postgres generated columns cannot reference other generated
--    columns, and this formula has real branching logic, so — like
--    the existing enforce_evaluation_edit_permissions trigger —
--    total_score/grade are now maintained by a BEFORE INSERT/UPDATE
--    trigger instead of GENERATED ALWAYS AS.
-- ------------------------------------------------------------
alter table evaluations drop column grade;
alter table evaluations drop column total_score;

alter table evaluations add column total_score numeric(5,2);
alter table evaluations add column grade eval_grade;

-- Raw score and applicable weight are kept as plain generated columns
-- purely for display (e.g. "Raw Score 50/50") — they only reference
-- ordinary input columns, so the generated-column restriction above
-- doesn't apply to them.
alter table evaluations add column raw_score numeric(5,2) generated always as (
  quality_score
  + case when shipment_status = 'no_shipment' then 0 else delivery_score end
  + case when shipment_status = 'no_shipment' then 0 else purchase_score end
) stored;

alter table evaluations add column applicable_weight numeric(5,2) generated always as (
  50
  + case when shipment_status = 'no_shipment' then 0 else 40 end
  + case when shipment_status = 'no_shipment' then 0 else 10 end
) stored;

comment on column evaluations.raw_score is 'Sum of scores actually applicable this month (excludes Delivery/Purchase when shipment_status = no_shipment). For display alongside total_score.';
comment on column evaluations.applicable_weight is 'Sum of full-marks weight actually applicable this month: 50 when shipment_status = no_shipment (Quality only), 100 when normal (Quality+Delivery+Purchase). Denominator for total_score.';

create or replace function public.compute_evaluation_score()
returns trigger as $$
declare
  applicable_weight numeric(5,2);
  raw numeric(5,2);
begin
  applicable_weight := 50
    + case when new.shipment_status = 'no_shipment' then 0 else 40 end
    + case when new.shipment_status = 'no_shipment' then 0 else 10 end;

  raw := new.quality_score
    + case when new.shipment_status = 'no_shipment' then 0 else new.delivery_score end
    + case when new.shipment_status = 'no_shipment' then 0 else new.purchase_score end;

  new.total_score := round((raw / applicable_weight) * 100, 2);

  new.grade := case
    when new.total_score >= 100 then 'A'::eval_grade
    when new.total_score >= 80  then 'B'::eval_grade
    when new.total_score >= 70  then 'C'::eval_grade
    else 'D'::eval_grade
  end;

  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_compute_evaluation_score on evaluations;
create trigger trg_compute_evaluation_score
  before insert or update on evaluations
  for each row execute function public.compute_evaluation_score();

-- ------------------------------------------------------------
-- 4) Extend the QA/CS-MP column-lock trigger: shipment_status and
--    no_shipment_reason are CS/MP's call (they're the ones who know
--    whether anything shipped), same as the delivery fields — QA
--    must not be able to change them either.
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
         or new.delivery_comment is distinct from old.delivery_comment
         or new.shipment_status is distinct from old.shipment_status
         or new.no_shipment_reason is distinct from old.no_shipment_reason then
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

-- (trigger trg_enforce_evaluation_edit already points at this function
-- by name — `create or replace function` above is enough, no need to
-- recreate the trigger itself)

-- ------------------------------------------------------------
-- 5) Backfill: recompute total_score/grade for every existing row
--    under the new rule (all existing rows default to
--    shipment_status = 'normal', so this only changes rows whose
--    generated column was dropped in step 3 and is otherwise a
--    like-for-like recalculation — no evaluation's meaning changes
--    unless you also go back and mark specific rows as no_shipment,
--    see the note below).
--
--    Temporarily disable two triggers for this one bulk update:
--    - trg_enforce_evaluation_edit checks auth.uid() against
--      user_profiles, which is null when run from the SQL editor (no
--      logged-in app user), and would otherwise block the statement.
--    - trg_evaluations_updated_at would stamp every row's updated_at
--      to "now", wiping out real history for a change that isn't a
--      real content edit.
-- ------------------------------------------------------------
alter table evaluations disable trigger trg_enforce_evaluation_edit;
alter table evaluations disable trigger trg_evaluations_updated_at;
update evaluations set updated_at = updated_at;  -- no-op update, just to fire trg_compute_evaluation_score
alter table evaluations enable trigger trg_evaluations_updated_at;
alter table evaluations enable trigger trg_enforce_evaluation_edit;

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * This migration does NOT retroactively mark any existing evaluation
--   as "no_shipment" — it only fixes the calculation going forward.
--   If any of July's rows (ETO, AKIYAMA JP, DAIDO, KYOTO, UGITECH,
--   or others) should actually be marked no_shipment, edit them again
--   from the app (Shipment Status → No Shipment + reason) so the
--   change goes through the normal audit trail, e.g.:
--     update evaluations
--     set shipment_status = 'no_shipment', no_shipment_reason = 'No PO this month'
--     where supplier_id = (select id from suppliers where code = '...')
--       and year = 2026 and month = 7;
-- * total_score is still always "out of 100" — nothing downstream
--   (dashboard KPIs, grade filters, profile trend) needs to change,
--   since they already just read total_score/grade.
-- ============================================================
