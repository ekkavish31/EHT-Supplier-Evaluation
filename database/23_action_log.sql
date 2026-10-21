-- ============================================================
-- 23_action_log.sql
-- Generic audit trail across the key tables, with Revert support for
-- the safe action types (per this session's decision):
--   🟢 delete  — always revertible (re-insert the row from snapshot)
--   🟢 insert  — always revertible (delete the row that was created)
--   🟡 update  — revertible UNLESS the row's own `status` column was
--                among the changed fields (workflow transitions —
--                submit/approve/reject/close — are visible in the log
--                but never get a Revert button, per decision)
--
-- Everyone logged in can READ the log. Only Admin can revert.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

create table admin_action_log (
  id               uuid primary key default gen_random_uuid(),
  table_name       text not null,
  row_id           uuid not null,
  action           text not null check (action in ('insert','update','delete')),
  old_data         jsonb,
  new_data         jsonb,
  changed_fields   text[],
  revert_supported boolean not null default false,
  performed_by     uuid references auth.users(id),
  performed_at     timestamptz not null default now(),
  reverted         boolean not null default false,
  reverted_by      uuid references auth.users(id),
  reverted_at      timestamptz
);

comment on table admin_action_log is 'Generic before/after snapshot log for insert/update/delete on the key tables (evaluations, corrective_actions, suppliers, evaluation_criteria, permission_rules, user_profiles). revert_supported is false for any update where the row''s status column changed (workflow transitions aren''t safely revertible — see PLAN.md).';

create index idx_action_log_table_row on admin_action_log(table_name, row_id);
create index idx_action_log_performed_at on admin_action_log(performed_at desc);

alter table admin_action_log enable row level security;

create policy "authenticated can read action log"
  on admin_action_log for select
  to authenticated
  using (true);

-- No insert/update/delete policy for normal use — rows are written
-- only by the security-definer trigger function below, and the
-- revert_admin_action() function (also security definer) is the only
-- thing allowed to mark a row reverted.

-- ------------------------------------------------------------
-- Generic logging trigger — attach to any table with a uuid `id`
-- primary key.
-- ------------------------------------------------------------
create or replace function public.log_admin_action()
returns trigger as $$
declare
  v_action  text;
  v_row_id  uuid;
  v_old     jsonb;
  v_new     jsonb;
  v_changed text[];
  v_revert  boolean;
begin
  if tg_op = 'INSERT' then
    v_action := 'insert';
    v_row_id := new.id;
    v_old := null;
    v_new := to_jsonb(new);
    v_revert := true;
  elsif tg_op = 'DELETE' then
    v_action := 'delete';
    v_row_id := old.id;
    v_old := to_jsonb(old);
    v_new := null;
    v_revert := true;
  else
    v_action := 'update';
    v_row_id := new.id;
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    select array_agg(o.key) into v_changed
      from jsonb_each(v_old) o
      where o.value is distinct from (v_new -> o.key);
    -- Not revertible if nothing actually changed, or if `status`
    -- (a workflow field where every table that has one uses it that
    -- way) is among the changed columns.
    v_revert := (v_changed is not null and array_length(v_changed,1) > 0)
                and not (v_old ? 'status' and 'status' = any(v_changed));
  end if;

  insert into admin_action_log (table_name, row_id, action, old_data, new_data, changed_fields, revert_supported, performed_by)
  values (tg_table_name, v_row_id, v_action, v_old, v_new, v_changed, v_revert, auth.uid());

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- Attach to the key tables. AFTER triggers — logging never blocks or
-- changes the actual operation, it just records it once it's done.
drop trigger if exists trg_log_evaluations on evaluations;
create trigger trg_log_evaluations after insert or update or delete on evaluations
  for each row execute function public.log_admin_action();

drop trigger if exists trg_log_corrective_actions on corrective_actions;
create trigger trg_log_corrective_actions after insert or update or delete on corrective_actions
  for each row execute function public.log_admin_action();

drop trigger if exists trg_log_suppliers on suppliers;
create trigger trg_log_suppliers after insert or update or delete on suppliers
  for each row execute function public.log_admin_action();

drop trigger if exists trg_log_evaluation_criteria on evaluation_criteria;
create trigger trg_log_evaluation_criteria after insert or update or delete on evaluation_criteria
  for each row execute function public.log_admin_action();

drop trigger if exists trg_log_permission_rules on permission_rules;
create trigger trg_log_permission_rules after insert or update or delete on permission_rules
  for each row execute function public.log_admin_action();

drop trigger if exists trg_log_user_profiles on user_profiles;
create trigger trg_log_user_profiles after insert or update or delete on user_profiles
  for each row execute function public.log_admin_action();

-- ------------------------------------------------------------
-- revert_admin_action(log_id) — Admin-only. Restores the row to its
-- pre-change state (or removes it, for reverting an insert; or
-- re-creates it, for reverting a delete). Uses jsonb_populate_record
-- so every column gets its correct type automatically — no manual
-- per-column casting needed.
-- ------------------------------------------------------------
create or replace function public.revert_admin_action(p_log_id uuid)
returns void as $$
declare
  v_log admin_action_log%rowtype;
  v_set_clause text;
begin
  if not public.has_permission('master_data_manage') then
    raise exception 'Only Admin can revert an action';
  end if;

  select * into v_log from admin_action_log where id = p_log_id;
  if not found then
    raise exception 'Log entry not found';
  end if;
  if v_log.reverted then
    raise exception 'This action has already been reverted';
  end if;
  if not v_log.revert_supported then
    raise exception 'This action cannot be reverted';
  end if;

  if v_log.action = 'insert' then
    execute format('delete from %I where id = $1', v_log.table_name) using v_log.row_id;

  elsif v_log.action = 'delete' then
    execute format(
      'insert into %I select * from jsonb_populate_record(null::%I, $1)',
      v_log.table_name, v_log.table_name
    ) using v_log.old_data;

  elsif v_log.action = 'update' then
    select string_agg(format('%I = src.%I', col, col), ', ')
      into v_set_clause
      from unnest(v_log.changed_fields) as col;
    execute format(
      'update %I t set %s from jsonb_populate_record(null::%I, $1) as src where t.id = $2',
      v_log.table_name, v_set_clause, v_log.table_name
    ) using v_log.old_data, v_log.row_id;
  end if;

  update admin_action_log
  set reverted = true, reverted_by = auth.uid(), reverted_at = now()
  where id = p_log_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * Reverting a 'delete' on `suppliers` will itself fail (safely, with
--   a normal Postgres error, nothing corrupted) if something else now
--   references a supplier code that got reused, etc. — edge case, not
--   handled specially.
-- * The AFTER trigger runs even for the security-definer functions
--   above (recompute_evaluation_scores, auto_create_corrective_action,
--   etc.) and for this migration's own INSERT statements below (the
--   admin_action_log table itself is not logged — no trigger on it).
-- * INSERT/DELETE are always revert_supported=true. This means, for
--   example, the auto-created corrective_actions row from
--   auto_create_corrective_action() shows up as a revertible "insert"
--   in the log too — reverting it just deletes that CA, same as doing
--   it by hand.
-- ============================================================
