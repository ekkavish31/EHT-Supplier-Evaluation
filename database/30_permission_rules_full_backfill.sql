-- ============================================================
-- 30_permission_rules_full_backfill.sql
-- Discovered live: eval_sup_approve/eval_mgr_approve had ZERO rows
-- in permission_rules (not an RLS issue — the UPDATE genuinely
-- matched 0 rows because nothing was there to match). Given this
-- happened once already, this backfills EVERY (rule_key, department)
-- combination that should exist across all migrations, not just the
-- one pair already found — including mp_supervisor, which was never
-- explicitly seeded for the older rule_keys (ca_close, ca_create,
-- eval_edit_quality, etc.) at all; those get mp_supervisor mirrored
-- from cs_supervisor's value (the two supervisor tiers are meant to
-- be symmetric).
--
-- Uses "on conflict do nothing" throughout — safe to run even if some
-- (or all) of these rows already exist; only fills genuine gaps.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

insert into permission_rules (rule_key, department, allowed) values
  ('attachment_delete', 'qa', false),
  ('attachment_delete', 'cs', false),
  ('attachment_delete', 'mp', false),
  ('attachment_delete', 'cs_supervisor', true),
  ('attachment_delete', 'mp_supervisor', true),
  ('attachment_delete', 'opd_manager', false),
  ('attachment_delete', 'admin', true),
  ('attachment_upload', 'qa', true),
  ('attachment_upload', 'cs', true),
  ('attachment_upload', 'mp', true),
  ('attachment_upload', 'cs_supervisor', true),
  ('attachment_upload', 'mp_supervisor', true),
  ('attachment_upload', 'opd_manager', true),
  ('attachment_upload', 'admin', true),
  ('ca_close', 'qa', true),
  ('ca_close', 'cs', false),
  ('ca_close', 'mp', false),
  ('ca_close', 'cs_supervisor', true),
  ('ca_close', 'mp_supervisor', true),
  ('ca_close', 'opd_manager', false),
  ('ca_close', 'admin', true),
  ('ca_create', 'qa', false),
  ('ca_create', 'cs', true),
  ('ca_create', 'mp', true),
  ('ca_create', 'cs_supervisor', true),
  ('ca_create', 'mp_supervisor', true),
  ('ca_create', 'opd_manager', false),
  ('ca_create', 'admin', true),
  ('ca_delete', 'qa', false),
  ('ca_delete', 'cs', false),
  ('ca_delete', 'mp', false),
  ('ca_delete', 'cs_supervisor', true),
  ('ca_delete', 'mp_supervisor', true),
  ('ca_delete', 'opd_manager', false),
  ('ca_delete', 'admin', true),
  ('ca_edit_full', 'qa', false),
  ('ca_edit_full', 'cs', false),
  ('ca_edit_full', 'mp', false),
  ('ca_edit_full', 'cs_supervisor', true),
  ('ca_edit_full', 'mp_supervisor', true),
  ('ca_edit_full', 'opd_manager', false),
  ('ca_edit_full', 'admin', true),
  ('ca_edit_restricted', 'qa', true),
  ('ca_edit_restricted', 'cs', false),
  ('ca_edit_restricted', 'mp', false),
  ('ca_edit_restricted', 'cs_supervisor', false),
  ('ca_edit_restricted', 'mp_supervisor', false),
  ('ca_edit_restricted', 'opd_manager', false),
  ('ca_edit_restricted', 'admin', false),
  ('eval_delete', 'qa', false),
  ('eval_delete', 'cs', false),
  ('eval_delete', 'mp', false),
  ('eval_delete', 'cs_supervisor', true),
  ('eval_delete', 'mp_supervisor', true),
  ('eval_delete', 'opd_manager', false),
  ('eval_delete', 'admin', true),
  ('eval_edit_delivery', 'qa', false),
  ('eval_edit_delivery', 'cs', true),
  ('eval_edit_delivery', 'mp', true),
  ('eval_edit_delivery', 'cs_supervisor', true),
  ('eval_edit_delivery', 'mp_supervisor', true),
  ('eval_edit_delivery', 'opd_manager', false),
  ('eval_edit_delivery', 'admin', true),
  ('eval_edit_quality', 'qa', true),
  ('eval_edit_quality', 'cs', false),
  ('eval_edit_quality', 'mp', false),
  ('eval_edit_quality', 'cs_supervisor', false),
  ('eval_edit_quality', 'mp_supervisor', false),
  ('eval_edit_quality', 'opd_manager', false),
  ('eval_edit_quality', 'admin', true),
  ('eval_mark_sent', 'qa', false),
  ('eval_mark_sent', 'cs', true),
  ('eval_mark_sent', 'mp', true),
  ('eval_mark_sent', 'cs_supervisor', true),
  ('eval_mark_sent', 'mp_supervisor', true),
  ('eval_mark_sent', 'opd_manager', true),
  ('eval_mark_sent', 'admin', true),
  ('eval_mgr_approve', 'qa', false),
  ('eval_mgr_approve', 'cs', false),
  ('eval_mgr_approve', 'mp', false),
  ('eval_mgr_approve', 'cs_supervisor', false),
  ('eval_mgr_approve', 'mp_supervisor', false),
  ('eval_mgr_approve', 'opd_manager', true),
  ('eval_mgr_approve', 'admin', true),
  ('eval_sup_approve', 'qa', false),
  ('eval_sup_approve', 'cs', false),
  ('eval_sup_approve', 'mp', false),
  ('eval_sup_approve', 'cs_supervisor', true),
  ('eval_sup_approve', 'mp_supervisor', true),
  ('eval_sup_approve', 'opd_manager', false),
  ('eval_sup_approve', 'admin', true),
  ('master_data_manage', 'qa', false),
  ('master_data_manage', 'cs', false),
  ('master_data_manage', 'mp', false),
  ('master_data_manage', 'cs_supervisor', false),
  ('master_data_manage', 'mp_supervisor', false),
  ('master_data_manage', 'opd_manager', false),
  ('master_data_manage', 'admin', true)
on conflict (rule_key, department) do nothing;

-- ------------------------------------------------------------
-- Sanity check — should show 14 rule_keys x 7 departments = 98 rows
-- total (eval_approve intentionally excluded — retired rule key, not
-- part of the current permission system, not reseeded on purpose).
-- ------------------------------------------------------------
select count(*) as total_rows, count(distinct rule_key) as distinct_rule_keys
from permission_rules
where rule_key <> 'eval_approve';
