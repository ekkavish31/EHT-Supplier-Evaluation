-- ============================================================
-- 18_import_heat_plating_suppliers.sql
-- Adds the "Outsource" supplier group (Heat Treatment, Plating, and
-- similar surface-treatment processes — CS's supplier group per the
-- department split discussed earlier) that wasn't in the system at
-- all yet, plus their real July 2026 itemized evaluation data, from
-- 01_FM-0704-3_..._Jul-26_.xlsx.
--
-- Same template as the Material suppliers file (07__JULY_26.xlsx) —
-- row layout, criteria order, and the "Time Score" occurrence column
-- (N) all match exactly, so this reuses the same import approach as
-- 17_import_july_2026_itemized.sql.
--
-- One thing that took extra checking: this file's "wQuality" /
-- "wDelivery" / "wPurchase Amount" cells are NOT fixed weights like
-- they first appeared to be (unlike anything named similarly before)
-- — they're each month's ACHIEVED score per category (confirmed:
-- SAHASIN shows wQuality=44, i.e. an actual quality deduction that
-- month; wPurchase varies 0/2/5/10 matching whichever purchase tier's
-- occurrence was ticked). Same semantics as our own quality_score /
-- delivery_score / purchase_score — just a confusingly-reused label
-- in this particular template. No impact on the import logic itself.
--
-- 5 of these 22 suppliers are No Shipment this month (GENERAL,
-- SRITONG, SSI, TRIX, STT) — same old ÷60 Excel bug is present in
-- their reported 83.33%/B; this import lets our corrected trigger
-- recompute them to 100%/A automatically, same as the Material batch.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Create the 22 suppliers (category = 'Outsource').
-- ------------------------------------------------------------
insert into suppliers (code, name, short_name, category, attention, tel, target_score, is_active) values

  ('OS-001', 'Tanabe (Thailand ) Co., Ltd.', 'Tanabe', 'Outsource', 'K.Veeranut', '(037)210981-3', 80, true),
  ('OS-002', 'Thai Tohken Thermo Co., Ltd.', 'Thai Tohken Thermo Co.', 'Outsource', 'K. CHONTICHA', '038-465296 # 301', 80, true),
  ('OS-003', 'Union Autoparts Manufacturing Co., Ltd.', 'Union Autoparts Manufacturing Co.', 'Outsource', 'K.Chayika', '038-885-002  # 322', 80, true),
  ('OS-004', 'Sahasin Plating Co., Ltd.', 'Sahasin Plating Co.', 'Outsource', 'K.Wathunya', '(034)866763-4', 80, true),
  ('OS-005', 'Thai Mekki Company Limited', 'Thai Mekki Company Limited', 'Outsource', 'K.Somboon', '02-896-9008', 80, true),
  ('OS-006', 'T.I.D. Engineering Co., Ltd.', 'T.I.D. Engineering Co.', 'Outsource', 'K.Vipa', '089-779-6329', 80, true),
  ('OS-007', 'Surtec Kariya (Thailand ) Co., Ltd.', 'Surtec Kariya', 'Outsource', 'K. Karnkaran', '035-226896-8', 80, true),
  ('OS-008', 'Taiyo Seisakusho (Thailand) Co., Ltd.', 'Taiyo Seisakusho', 'Outsource', 'K.Nara', '(035)268-070-71', 80, true),
  ('OS-009', 'General Plating Industry Co., Ltd.', 'General Plating Industry Co.', 'Outsource', 'K.Sumana', '02-897-2735', 80, true),
  ('OS-010', 'Thai Parkerizing Co., Ltd.', 'Thai Parkerizing Co.', 'Outsource', 'K.Worada', '033-658-800', 80, true),
  ('OS-011', 'Sritong Electro Chemical', 'Sritong Electro Chemical', 'Outsource', 'K.Niracha', '02-4258743-45', 80, true),
  ('OS-012', 'Watanabe Heat Treatment Co., Ltd.', 'Watanabe Heat Treatment Co.', 'Outsource', 'K.Patchaya', '(038) 348 216-20', 80, true),
  ('OS-013', 'Jtekt Coating (Thailand) Co., Ltd.', 'Jtekt Coating', 'Outsource', 'K.Nittaya', '038-955-538', 80, true),
  ('OS-014', 'SSI SURFACE TECHNOLOGY CO., LTD', 'SSI SURFACE TECHNOLOGY CO.', 'Outsource', 'K. Orwan', '02-0058857', 80, true),
  ('OS-015', 'B.K.J. Engineering Co., Ltd.', 'B.K.J. Engineering Co.', 'Outsource', 'K.Phatsara', '02-4642524-6', 80, true),
  ('OS-016', 'Trix Manufacturing Co., Ltd.', 'Trix Manufacturing Co.', 'Outsource', 'K.Manoon', '086-600-6853', 80, true),
  ('OS-017', 'Toho Mekki (Thailand) Co., Ltd.', 'Toho Mekki', 'Outsource', 'K.Sukhon', '038-212344', 80, true),
  ('OS-018', 'Thai Inductions Services Co., Ltd.', 'Thai Inductions Services Co.', 'Outsource', 'K.Patsita', '02-1746227-36', 80, true),
  ('OS-019', 'Surface Treatment Technology', 'Surface Treatment Technology', 'Outsource', 'K. Kwanpracha', '033-048-075-7', 80, true),
  ('OS-020', 'Surtec & Plamex Co.,Ltd.', 'Surtec & Plamex Co.', 'Outsource', 'K. ANURAK', '037-278758-62', 80, true),
  ('OS-021', 'Thai Silvec Co.,Ltd.', 'Thai Silvec Co.', 'Outsource', 'K.Supawadee', '038-447-557-8', 80, true),
  ('OS-022', 'MIYAKI (Thailand) Co.,Ltd.', 'MIYAKI', 'Outsource', 'K.Somyot', '038-913-720-21', 80, true)
on conflict (code) do nothing;

-- ------------------------------------------------------------
-- 2) July 2026 evaluations + itemized checklist data.
-- Disables trg_enforce_evaluation_edit for the whole block (including
-- the safety-net recompute calls) — same reason as 17_...sql:
-- auth.uid() is null with no logged-in app user in the SQL editor.
-- ------------------------------------------------------------
alter table evaluations disable trigger trg_enforce_evaluation_edit;

-- ---- OS-001 (TANABE) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-001'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-002 (TOHKEN) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-002'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-003 (UNION) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-003'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-004 (SAHASIN) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-004'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-005 (TMK) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-005'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-006 (T.I.D.) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-006'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-007 (SURTEC) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-007'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-008 (TAIYO) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-008'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-009 (GENERAL) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-009'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-010 (TPK) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-010'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-011 (SRITONG) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-011'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-012 (WATANABE) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-012'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-013 (JTEKT) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-013'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-014 (SSI) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-014'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-015 (BKJ) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-015'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-016 (TRIX) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-016'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-017 (TOHO MEKKI) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-017'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-018 (THAI INDUCTION ) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-018'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-019 (STT) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-019'), 2026, 7, 'draft', 'itemized', 'no_shipment', 'No shipment/purchase this month (from FM0704-3 July worksheet)', 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'no_shipment',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, 'No shipment/purchase this month (from FM0704-3 July worksheet)');

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-020 (S_P) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-020'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 1),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 0)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-021 (SILVEC) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-021'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- ---- OS-022 (MIYAKI) ----
insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, no_shipment_reason, quality_score, delivery_score, purchase_score)
values ((select id from suppliers where code = 'OS-022'), 2026, 7, 'draft', 'itemized', 'normal', null, 0, 0, 0)
on conflict (supplier_id, year, month) do update set
  scoring_mode = 'itemized',
  shipment_status = 'normal',
  no_shipment_reason = coalesce(evaluations.no_shipment_reason, null);

insert into evaluation_items (evaluation_id, criteria_id, occurrence)
values
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-8'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A1-9'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='A2-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-3'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-4'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-5'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-6'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='B-7'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-1'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-2'), 0),
  ((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7), (select id from evaluation_criteria where item_no='C-3'), 1)
on conflict (evaluation_id, criteria_id) do update set occurrence = excluded.occurrence;

-- Safety-net recompute
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-001') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-002') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-003') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-004') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-005') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-006') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-007') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-008') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-009') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-010') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-011') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-012') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-013') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-014') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-015') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-016') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-017') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-018') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-019') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-020') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-021') and year=2026 and month=7));
select public.recompute_evaluation_scores((select id from evaluations where supplier_id=(select id from suppliers where code='OS-022') and year=2026 and month=7));

alter table evaluations enable trigger trg_enforce_evaluation_edit;

-- Sanity check — should show 22 rows
select s.code, s.short_name, e.shipment_status, e.total_score, e.grade
from evaluations e join suppliers s on s.id = e.supplier_id
where e.year = 2026 and e.month = 7 and s.category = 'Outsource'
order by s.code;
