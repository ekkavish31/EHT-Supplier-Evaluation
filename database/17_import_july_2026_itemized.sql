-- ============================================================
-- 17_import_july_2026_itemized.sql  (v2 — self-sufficient)
-- Fills in the real per-criteria checklist data for July 2026 from
-- the official Excel worksheets (07__JULY_26.xlsx), for the 31
-- suppliers that actually have July data in that file (MA-088
-- Yamaichi's July sheet is mislabeled and actually contains June
-- data — excluded, its July evaluation stays as-is).
--
-- v2 change: the evaluations row for a supplier+2026+7 is now created
-- with INSERT ... ON CONFLICT DO UPDATE (upsert) instead of a plain
-- UPDATE. Plain UPDATE silently does nothing if the row doesn't exist
-- yet, which left evaluation_id as NULL for the evaluation_items
-- insert that follows it and broke the whole script (Postgres runs
-- this as one transaction, so that failure rolled back everything
-- before it too, not just the failing part).
--
-- For each supplier this:
--   1. Upserts the July evaluation row: scoring_mode='itemized',
--      shipment_status per the Excel's own wDelivery/wPurchase weight
--      columns. On conflict (row already existed), only these two
--      columns (+ no_shipment_reason) are touched — status/approval
--      history on an existing row is left alone. On a fresh insert,
--      status defaults to 'draft'.
--   2. Upserts all 22 evaluation_items (occurrence counts) exactly as
--      recorded in each supplier's sheet (column N, "Time Score").
-- Triggers take it from there — total_score/grade recalculate
-- automatically and correctly (including the No-Shipment fix from
-- Phase A).
--
-- Disables trg_enforce_evaluation_edit for the WHOLE script (including
-- the safety-net recompute calls at the end, which do their own
-- internal UPDATE evaluations) — auth.uid() is null with no logged-in
-- app user in the SQL editor, which that trigger would otherwise reject.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

alter table evaluations disable trigger trg_enforce_evaluation_edit;

-- ---- MA-003 (ALMET THAI) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-003'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-037 (KYOTO) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-037'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-134 (DONGGUAN) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-134'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-083 (UGITECH) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-083'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-014 (DAIDO) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-014'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-121 (JIANGSU) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-121'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-002 (AKIYAMA SC) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-002'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-001 (AKIYAMA JP) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-001'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-005 (APOLLO) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-005'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-137 (VOESTALPINE) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-137'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-073 (TSK) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-073'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-071 (STEELTEC) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-071'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-136 (BEDRA) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-136'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-095 (CAMELLIA) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-095'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-115 (SHINSHO THAI) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-115'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-049 (NSL) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-049'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-007 (BGH) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-007'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-004 (AMINO) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-004'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-038 (LOTUS) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-038'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-103 (NIPPON STEEL) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-103'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-111 (SHINSHO COR P+M) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-111'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-040 (MENAM) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-040'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-036 (KOMATSU) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-036'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-006 (ASAI THAI) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-006'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-112 (LMAT) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-112'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-052 (OKAYA P+M) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-052'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 3),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-063 (SAKUMA) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-063'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- MA-107 (No eva. NST) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'MA-107'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- PA-005 (ETO) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'PA-005'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- PA-012 (SCS) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'PA-012'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- PA-010 (NISSAN SPRING) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'PA-010'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- Safety-net recompute (trigger already fires per-row on insert above, this just re-asserts it)
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-003') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-037') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-134') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-083') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-014') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-121') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-002') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-001') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-005') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-137') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-073') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-071') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-136') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-095') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-115') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-049') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-007') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-004') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-038') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-103') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-111') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-040') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-036') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-006') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-112') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-052') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-063') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='MA-107') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='PA-005') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='PA-012') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='PA-010') and year=2026 and month=7));

alter table evaluations enable trigger trg_enforce_evaluation_edit;

-- Sanity check — should show 31 rows, all with total_score/grade filled in
select s.code, s.short_name, e.shipment_status, e.total_score, e.grade
from evaluations e join suppliers s on s.id = e.supplier_id
where e.year = 2026 and e.month = 7 and e.scoring_mode = 'itemized'
order by s.code;
