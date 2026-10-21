-- ============================================================
-- 27_bulk_complete_imported_evaluations.sql
-- One-time data fixup: the Excel import feature always creates
-- evaluations as status='draft' with no submitted timestamps — for
-- freshly re-imported historical data (already finalized in the
-- source Excel files) this looked like "QA hasn't evaluated yet"
-- when really the whole thing is already complete.
--
-- This bulk-advances every still-draft evaluation straight to
-- 'acknowledged' (same for every grade — A/B/C/D all treated as
-- fully closed, no exceptions), stamping all the workflow timestamps
-- as today. Deliberately skips the normal Submit -> Supervisor
-- Approve -> Manager Approve -> Mark Sent button sequence, so:
--   - Nothing about how/that this happened is fabricated on the row
--     itself beyond a visible marker: quality_comment/delivery_comment
--     get "[นำเข้าจากข้อมูลเก่า / Imported from Excel]" filled in,
--     but ONLY where that comment field was empty — never overwrites
--     a real comment. The full before/after is also captured
--     automatically in admin_action_log (see 23_action_log.sql),
--     timestamped, if you need to look back at exactly what changed.
--   - auto_create_corrective_action does NOT fire, because it only
--     triggers on a transition INTO 'mgr_approved' specifically, and
--     this update skips past that status entirely. No Corrective
--     Action gets created for any C/D grade in this batch — decided
--     on purpose, since these are historical closed records, not
--     open cases that need tracking.
--
-- Scope: only rows with status='draft' AND scoring_mode='itemized' —
-- i.e. exactly what a fresh Excel import produces. Does not touch
-- anything already further along in a real workflow.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

alter table evaluations disable trigger trg_enforce_evaluation_edit;

update evaluations
set
  status = 'acknowledged',
  quality_submitted_at  = coalesce(quality_submitted_at, now()),
  delivery_submitted_at = coalesce(delivery_submitted_at, now()),
  sup_approved_at       = coalesce(sup_approved_at, now()),
  mgr_approved_at       = coalesce(mgr_approved_at, now()),
  sent_at               = coalesce(sent_at, now()),
  -- Visible marker on the record itself (not just in admin_action_log)
  -- — only fills empty comment fields, never overwrites a real one.
  quality_comment  = case when quality_comment  is null or quality_comment  = '' then '[นำเข้าจากข้อมูลเก่า / Imported from Excel]' else quality_comment  end,
  delivery_comment = case when delivery_comment is null or delivery_comment = '' then '[นำเข้าจากข้อมูลเก่า / Imported from Excel]' else delivery_comment end
where status = 'draft'
  and scoring_mode = 'itemized';

alter table evaluations enable trigger trg_enforce_evaluation_edit;

-- ------------------------------------------------------------
-- Sanity check — should show 0 remaining itemized drafts, and the
-- count of corrective_actions should NOT have grown from this.
-- ------------------------------------------------------------
select count(*) as remaining_itemized_drafts
from evaluations where status = 'draft' and scoring_mode = 'itemized';

select count(*) as total_corrective_actions from corrective_actions;

insert into app_schema_version (id, version, package_version)
values (1, 27, 'v45')
on conflict (id) do update
set version = excluded.version, package_version = excluded.package_version, applied_at = now();
