-- ============================================================
-- 20b_fix_missing_approval_columns.sql
-- Discovered while running 27_bulk_complete_imported_evaluations.sql:
-- sup_approved_at/sup_approved_by/mgr_approved_at/mgr_approved_by
-- were never actually added to evaluations, even though the
-- eval_status enum values (sup_approved/mgr_approved) exist — these
-- come from two different statements inside 20_two_tier_approval.sql
-- (Part 2), and only the enum half seems to have landed.
--
-- This is why it never surfaced earlier: the trigger that sets these
-- columns (enforce_evaluation_edit_permissions) is PL/pgSQL — Postgres
-- doesn't check that referenced columns actually exist until the
-- function *runs*, not when it's created. So CREATE FUNCTION always
-- succeeded silently; only an actual Supervisor/Manager Approve click
-- (or, as happened here, a direct SQL UPDATE naming the column) would
-- have ever surfaced this.
--
-- Uses "add column if not exists" — safe to run even if some of these
-- already exist for any reason.
--
-- Run this once, THEN re-run 27_bulk_complete_imported_evaluations.sql.
-- ============================================================

alter table evaluations
  add column if not exists sup_approved_by  uuid references auth.users(id),
  add column if not exists sup_approved_at  timestamptz,
  add column if not exists mgr_approved_by  uuid references auth.users(id),
  add column if not exists mgr_approved_at  timestamptz;

-- Sanity check — should list all 4 columns
select column_name, data_type
from information_schema.columns
where table_name = 'evaluations'
  and column_name in ('sup_approved_by','sup_approved_at','mgr_approved_by','mgr_approved_at')
order by column_name;
