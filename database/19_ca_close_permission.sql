-- ============================================================
-- 19_ca_close_permission.sql
-- Workflow simplification agreed in this session:
--   - Dropped "Mark Acknowledged" as a separate step (it was
--     redundant with the supplier actually sending back a
--     countermeasure file, which is the real proof they engaged).
--   - Grade A/B: "Mark Sent to Supplier" now closes the evaluation
--     case automatically — no manual close step needed.
--   - Grade C/D: the corrective action created at Approve time is now
--     editable and closeable immediately (no more "wait for
--     something before you can touch it" — there never actually was
--     a real gate here besides the QA column-restriction itself).
--     QA can now also CLOSE the case (previously only CS
--     Supervisor/Admin could change a CA's status at all) via a new,
--     narrow permission: they can only ever set status to 'closed',
--     nothing else.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1) New rule_key: ca_close — separate from ca_edit_full/
--    ca_edit_restricted so it's independently toggleable in
--    Master Control -> Permissions.
-- ------------------------------------------------------------
insert into permission_rules (rule_key, department, allowed) values
  ('ca_close', 'qa',            true),
  ('ca_close', 'cs',            false),
  ('ca_close', 'mp',            false),
  ('ca_close', 'cs_supervisor', true),
  ('ca_close', 'admin',         true)
on conflict (rule_key, department) do nothing;

-- ------------------------------------------------------------
-- 2) Update the edit trigger: QA (or anyone with ca_edit_restricted)
--    can now also set status to 'closed' specifically, if they have
--    ca_close — no other status transition, and nothing else about
--    the row changes from what ca_edit_restricted already allowed.
-- ------------------------------------------------------------
create or replace function public.enforce_ca_edit_permissions()
returns trigger as $$
declare
  full_edit       boolean;
  restricted_edit boolean;
  can_close       boolean;
begin
  if not exists (select 1 from user_profiles where id = auth.uid()) then
    raise exception 'No user_profiles row found for current user — cannot verify permissions';
  end if;

  full_edit := public.has_permission('ca_edit_full');
  if full_edit then
    return new;
  end if;

  restricted_edit := public.has_permission('ca_edit_restricted');
  if restricted_edit then
    can_close := public.has_permission('ca_close');
    if new.evaluation_id        is distinct from old.evaluation_id
       or new.seq_no            is distinct from old.seq_no
       or new.problem           is distinct from old.problem
       or new.responsible_person is distinct from old.responsible_person
       or new.start_date        is distinct from old.start_date
       or new.due_date          is distinct from old.due_date
       or new.finished_date     is distinct from old.finished_date
       or (new.status is distinct from old.status and not (can_close and new.status = 'closed')) then
      raise exception 'You can only edit Root Cause / Corrective Action, and close the case, on an existing corrective action';
    end if;
    return new;
  end if;

  raise exception 'You do not have permission to edit an existing corrective action';
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * "Mark Acknowledged" (evaluations.status = 'acknowledged',
--   acknowledged_at) is no longer set manually from the UI — but for
--   a grade A/B evaluation, "Mark Sent to Supplier" now sets status
--   straight to 'acknowledged' (auto-close), reusing the same enum
--   value/column rather than adding a new one. Nothing downstream
--   (KPI "complete" counts, etc.) needed to change, since those
--   already treated 'acknowledged' as a closed state.
-- * corrective_actions.status = 'closed' is set via the new "Mark
--   Received Countermeasure" button, which also stamps finished_date.
-- ============================================================
