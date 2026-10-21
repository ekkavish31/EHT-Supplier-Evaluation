-- ============================================================
-- 35_auto_open_current_cycle.sql
-- Automatic monthly cycle opening.
--
-- Same bulk action as public.open_evaluation_cycle() (16_evaluation_cycles.sql)
-- but (a) callable by ANY signed-in user, not only Admin, and (b) always
-- targets the CURRENT calendar month in Thailand time, so the client can
-- simply call it after login. The app calls it once per session when it
-- notices that some active supplier has no evaluation row for this month.
--
-- Safe to call repeatedly: it only inserts missing rows and never touches
-- existing evaluations. New rows are 'draft' with all-zero scores, exactly
-- like open_evaluation_cycle. INSERT on evaluations is already open to any
-- authenticated department (see note at the end of 03_phase2_auth_and_roles.sql);
-- the before-insert trigger only stamps submitted_by = auth.uid().
--
-- Run once in the Supabase SQL Editor. Requires 16_evaluation_cycles.sql.
-- ============================================================

create or replace function public.ensure_current_cycle()
returns table(created_count int, cycle_year int, cycle_month int) as $$
declare
  v_year  int := extract(year  from (now() at time zone 'Asia/Bangkok'))::int;
  v_month int := extract(month from (now() at time zone 'Asia/Bangkok'))::int;
  v_created int;
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  insert into evaluation_cycles (year, month, opened_by)
  values (v_year, v_month, auth.uid())
  on conflict (year, month) do nothing;

  with inserted as (
    insert into evaluations (supplier_id, year, month, status, scoring_mode, shipment_status, quality_score, delivery_score, purchase_score)
    select s.id, v_year, v_month, 'draft', 'itemized', 'normal', 0, 0, 0
    from suppliers s
    where s.is_active = true
      and not exists (
        select 1 from evaluations e
        where e.supplier_id = s.id and e.year = v_year and e.month = v_month
      )
    on conflict (supplier_id, year, month) do nothing
    returning 1
  )
  select count(*) into v_created from inserted;

  return query select v_created, v_year, v_month;
end;
$$ language plpgsql security definer set search_path = public;

revoke all on function public.ensure_current_cycle() from public;
grant execute on function public.ensure_current_cycle() to authenticated;
