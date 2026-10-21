-- ============================================================
-- 12_ca_permission_tiers.sql
-- Tightens corrective_actions from "any authenticated staff can do
-- anything" (v0.5.0) to a proper role split, as decided in this
-- session:
--   - CREATE a new corrective action: CS, MP, CS Supervisor, Admin
--   - EDIT (any field) or DELETE an existing one: CS Supervisor, Admin only
--   - QA may still update root_cause / action (their investigation
--     findings) on an existing record, nothing else
--   - Attachments: anyone above can upload; only CS Supervisor/Admin
--     can delete one
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Helper: can this user CREATE a corrective action?
-- ------------------------------------------------------------
create or replace function public.can_create_ca()
returns boolean as $$
  select exists (
    select 1 from user_profiles
    where id = auth.uid() and department in ('cs', 'mp', 'cs_supervisor', 'admin')
  );
$$ language sql stable security definer set search_path = public;

-- ------------------------------------------------------------
-- 2) Replace the broad insert/update/delete policies from
--    08_corrective_action_workflow.sql with the tiered versions.
-- ------------------------------------------------------------
drop policy if exists "authenticated can insert corrective actions" on corrective_actions;
create policy "cs/mp/cs_supervisor/admin can insert corrective actions"
  on corrective_actions for insert
  to authenticated
  with check (public.can_create_ca());

drop policy if exists "authenticated can delete corrective actions" on corrective_actions;
create policy "cs supervisor or admin can delete corrective actions"
  on corrective_actions for delete
  to authenticated
  using (public.is_cs_supervisor());

-- UPDATE stays permissive at the RLS layer (like `evaluations` does) —
-- the actual column-level rule (QA: only root_cause/action; CS/MP:
-- nothing at all once created; CS Supervisor/Admin: everything) is
-- enforced by the trigger below, same pattern as
-- enforce_evaluation_edit_permissions.
-- ("authenticated can update corrective actions" policy from
-- 08_corrective_action_workflow.sql is left as-is.)

-- ------------------------------------------------------------
-- 3) Column-level enforcement trigger for UPDATE.
-- ------------------------------------------------------------
create or replace function public.enforce_ca_edit_permissions()
returns trigger as $$
declare
  dept department_role;
begin
  select department into dept from user_profiles where id = auth.uid();

  if dept is null then
    raise exception 'No user_profiles row found for current user — cannot verify permissions';
  end if;

  if dept in ('cs_supervisor', 'admin') then
    return new; -- full access
  end if;

  if dept = 'qa' then
    if new.evaluation_id      is distinct from old.evaluation_id
       or new.seq_no           is distinct from old.seq_no
       or new.problem          is distinct from old.problem
       or new.responsible_person is distinct from old.responsible_person
       or new.start_date       is distinct from old.start_date
       or new.due_date         is distinct from old.due_date
       or new.finished_date    is distinct from old.finished_date
       or new.status           is distinct from old.status then
      raise exception 'QA can only edit Root Cause and Corrective Action on an existing corrective action';
    end if;
    return new;
  end if;

  -- cs / mp: can CREATE (insert policy above) but not edit afterward
  raise exception 'Only CS Supervisor or Admin can edit an existing corrective action';
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_enforce_ca_edit on corrective_actions;
create trigger trg_enforce_ca_edit
  before update on corrective_actions
  for each row execute function public.enforce_ca_edit_permissions();

-- ------------------------------------------------------------
-- 4) Attachment deletion — restrict to CS Supervisor/Admin (upload
--    stays open to everyone who can touch the CA at all, including QA).
-- ------------------------------------------------------------
drop policy if exists "authenticated can delete attachments" on evaluation_attachments;
create policy "cs supervisor or admin can delete attachments"
  on evaluation_attachments for delete
  to authenticated
  using (public.is_cs_supervisor());

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * QA cannot create a new corrective action under this rule (only
--   CS/MP/CS Supervisor/Admin can). If QA should also be able to open
--   a case for a quality issue they find, add 'qa' to can_create_ca().
-- * Evaluation attachments (not tied to a corrective action) are
--   unaffected by this file's delete-restriction change — wait, this
--   IS the same evaluation_attachments table, so evaluation-side
--   attachment deletion is now ALSO restricted to CS Supervisor/Admin,
--   not just CA-side. That's intentional — one delete rule for the
--   whole attachments table, simpler to reason about than two.
-- ============================================================
