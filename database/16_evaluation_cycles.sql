-- ============================================================
-- 16_evaluation_cycles.sql
-- Closes another flagged gap: the Dashboard's own v0.8.0 notes say
-- "cycle coverage is derived from active suppliers for the selected
-- period until a dedicated evaluation_cycles table is added" — this
-- is that table, plus the "open a monthly cycle" bulk action from the
-- very first workflow proposal (Step 1: "เปิดรอบประเมินประจำเดือน" —
-- opening a round auto-creates a draft evaluation for every active
-- supplier, instead of each department finding suppliers one at a
-- time).
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

create table evaluation_cycles (
  id          uuid primary key default gen_random_uuid(),
  year        int not null,
  month       int not null check (month between 1 and 12),
  opened_by   uuid references auth.users(id),
  opened_at   timestamptz not null default now(),
  notes       text,
  unique (year, month)
);

comment on table evaluation_cycles is 'One row per month a coordinator/admin has "opened" — the act of opening bulk-creates a draft evaluation for every active supplier that does not already have one that month. Existence of a row here (vs. evaluations just accumulating ad hoc) is what lets the Dashboard show real cycle coverage instead of deriving it from whichever evaluations happen to exist.';

alter table evaluation_cycles enable row level security;

create policy "authenticated can read evaluation cycles"
  on evaluation_cycles for select
  to authenticated
  using (true);

create policy "admin can open evaluation cycles"
  on evaluation_cycles for insert
  to authenticated
  with check (public.is_admin());

-- ------------------------------------------------------------
-- open_evaluation_cycle(year, month) — the bulk action itself.
-- Idempotent: re-running it for the same year/month just fills in any
-- suppliers that still don't have a row (e.g. a supplier was added
-- after the cycle was first opened), never touches existing
-- evaluations. New rows are created in 'draft' / 'itemized' scoring
-- mode with all-zero scores — same "looks unfinished" defaults as
-- v0.4.0's fix, on purpose.
-- ------------------------------------------------------------
create or replace function public.open_evaluation_cycle(p_year int, p_month int)
returns table(created_count int, cycle_already_existed boolean) as $$
declare
  v_existed boolean;
  v_created int;
begin
  if not public.is_admin() then
    raise exception 'Only Admin can open an evaluation cycle';
  end if;

  select exists(select 1 from evaluation_cycles where year = p_year and month = p_month) into v_existed;

  insert into evaluation_cycles (year, month, opened_by)
  values (p_year, p_month, auth.uid())
  on conflict (year, month) do nothing;

  with inserted as (
    insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, quality_score, delivery_score, purchase_score)
    select s.id, p_year, p_month, 'draft', 'itemized', 'normal', 0, 0, 0
    from suppliers s
    where s.is_active = true
      and not exists (
        select 1 from evaluations e
        where e.supplier_id = s.id and e.year = p_year and e.month = p_month
      )
    on conflict (supplier_id, year, month) do nothing
    returning 1
  )
  select count(*) into v_created from inserted;

  return query select v_created, v_existed;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * Only creates the ROW — someone (QA/CS/MP) still has to actually
--   fill in and submit each evaluation as normal. This just removes
--   the "create it by picking supplier+year+month in Monthly Input
--   one at a time" step for a whole batch.
-- * The Dashboard's Command Center still derives cycle coverage from
--   `evaluations` directly, not from this table yet — wiring the
--   Dashboard to prefer `evaluation_cycles` when one exists for the
--   selected period (and show "not yet opened" when it doesn't) is
--   left for a follow-up pass, not done in this migration.
-- ============================================================
