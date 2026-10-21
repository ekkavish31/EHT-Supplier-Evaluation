-- ============================================================
-- 08_corrective_action_workflow.sql
-- Phase B — turn on the Corrective Action table + auto-create CA
-- requirements for Grade C/D, per FM0704-3 page 2 and the 5-working-day
-- rule already documented in PLAN.md / the Excel form.
--
-- IMPORTANT: `corrective_actions` had `enable row level security` set
-- since v0.1.0 but has NEVER had a single policy defined for it. With
-- RLS on and zero policies, Postgres denies ALL access by default —
-- so this table has been completely unusable from the app (select,
-- insert, update, delete all silently return "no rows"/permission
-- denied) since it was created. This migration is what actually turns
-- it on.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1) RLS policies — any authenticated user (any department) can
--    read and manage corrective actions. Unlike `evaluations`,
--    resolving a CA often needs QA, CS/MP, and a supervisor all
--    touching the same record over time (problem → root cause →
--    action → verify), so this intentionally doesn't column-lock by
--    department the way evaluations does. Tighten later if needed.
-- ------------------------------------------------------------
create policy "authenticated can read corrective actions"
  on corrective_actions for select
  to authenticated
  using (true);

create policy "authenticated can insert corrective actions"
  on corrective_actions for insert
  to authenticated
  with check (true);

create policy "authenticated can update corrective actions"
  on corrective_actions for update
  to authenticated
  using (true);

create policy "authenticated can delete corrective actions"
  on corrective_actions for delete
  to authenticated
  using (true);

-- ------------------------------------------------------------
-- 2) Add a due_date so "5 working days" and "overdue" are trackable.
--    (start_date/finished_date already existed but there was nowhere
--    to record the deadline itself.)
-- ------------------------------------------------------------
alter table corrective_actions
  add column due_date date;

comment on column corrective_actions.due_date is
  'Deadline for the supplier to submit their improvement plan. Auto-set to 5 working days after the evaluation was approved, for auto-created rows (see trigger below). "Overdue" is computed in the app (due_date < today and status not closed) rather than stored, since it changes with the calendar.';

-- ------------------------------------------------------------
-- 3) Helper: add N working days (Mon-Fri) to a date.
--    Simplification: does not account for public holidays — there is
--    no holiday-calendar table yet (see PLAN.md open question
--    "Working Days / Holidays"). Close enough for now; revisit once
--    that table exists.
-- ------------------------------------------------------------
create or replace function public.add_working_days(start_date date, n int)
returns date as $$
declare
  d date := start_date;
  remaining int := n;
begin
  while remaining > 0 loop
    d := d + 1;
    if extract(isodow from d) < 6 then  -- Mon=1 .. Fri=5, Sat=6, Sun=7
      remaining := remaining - 1;
    end if;
  end loop;
  return d;
end;
$$ language plpgsql immutable;

-- ------------------------------------------------------------
-- 4) Auto-create a Corrective Action requirement when an evaluation
--    is newly approved with Grade C or D (both require an improvement
--    plan within 5 working days, per the existing grade-criteria text
--    already shown in the app's Report Preview).
--    Does nothing if a CA already exists for that evaluation, so
--    re-approving or editing an already-CA'd evaluation is a no-op.
-- ------------------------------------------------------------
create or replace function public.auto_create_corrective_action()
returns trigger as $$
declare
  next_seq int;
  should_create boolean;
begin
  -- OLD does not exist on INSERT — branch on TG_OP before touching it.
  -- A brand-new evaluation can be saved directly with status='approved'
  -- (the app's upsert lets you pick any status on first save), so this
  -- has to handle INSERT, not just the more obvious UPDATE-to-approved case.
  if tg_op = 'INSERT' then
    should_create := (new.status = 'approved' and new.grade in ('C', 'D'));
  else
    should_create := (new.status = 'approved'
                       and old.status is distinct from 'approved'
                       and new.grade in ('C', 'D'));
  end if;

  if should_create and not exists (select 1 from corrective_actions where evaluation_id = new.id) then
    select coalesce(max(seq_no), 0) + 1 into next_seq
    from corrective_actions where evaluation_id = new.id;

    insert into corrective_actions (evaluation_id, seq_no, problem, status, start_date, due_date)
    values (
      new.id,
      next_seq,
      'Auto-generated: evaluation scored ' || new.total_score || '% (Grade ' || new.grade || ') — supplier must submit an improvement plan.',
      'open',
      current_date,
      public.add_working_days(current_date, 5)
    );
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_auto_create_corrective_action on evaluations;
create trigger trg_auto_create_corrective_action
  after insert or update on evaluations
  for each row execute function public.auto_create_corrective_action();

-- ------------------------------------------------------------
-- 5) One-time backfill: create the CA rows that SHOULD already exist
--    for evaluations that are already approved with Grade C/D, but
--    predate this trigger (so it never fired for them).
--
--    Deliberately EXCLUDES rows tagged as pure historical imports
--    (quality_comment starting with 'Historical import' — see
--    02_seed_data.sql) — those are old total-score-only rows from
--    2025/early 2026 with no real Q/D/P breakdown, and "due in 5
--    working days from today" would be meaningless for a month that
--    ended a year ago. Only evaluations with real, current data (like
--    July 2026's 32-row breakdown import, or anything entered from
--    here on) get backfilled.
-- ------------------------------------------------------------
insert into corrective_actions (evaluation_id, seq_no, problem, status, start_date, due_date)
select
  e.id,
  1,
  'Auto-generated (backfilled): evaluation scored ' || e.total_score || '% (Grade ' || e.grade || ') — supplier must submit an improvement plan.',
  'open',
  current_date,
  public.add_working_days(current_date, 5)
from evaluations e
where e.status = 'approved'
  and e.grade in ('C', 'D')
  and coalesce(e.quality_comment, '') not like 'Historical import%'
  and not exists (select 1 from corrective_actions ca where ca.evaluation_id = e.id);

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * The backfilled rows above all get a due_date of "5 working days
--   from today" (the day you run this), since the real historical
--   approval date's due date has already passed for most of them —
--   that's expected. Adjust individual due_date values by hand in the
--   app if a specific one should reflect the real original deadline.
-- * "Overdue" is a UI-computed flag (due_date < today AND status not
--   closed), not a column the trigger sets — see app.js. The
--   ca_status enum still has an 'overdue' value if you want to mark
--   one manually/permanently, but nothing sets it automatically.
-- ============================================================
