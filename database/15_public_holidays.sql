-- ============================================================
-- 15_public_holidays.sql
-- Closes a known limitation flagged in PLAN.md: `add_working_days()`
-- (used for the Corrective Action "5 working days" due date) only
-- skipped weekends, not public holidays.
--
-- Seeded with Thailand's 2026 official public holidays (source:
-- cross-checked against several holiday-calendar sites in Sep 2026 —
-- if the government adds/moves a special bridge holiday later in the
-- year, add it via Master Control -> Holidays, no SQL needed).
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

create table public_holidays (
  id           uuid primary key default gen_random_uuid(),
  holiday_date date not null unique,
  name         text not null,
  name_th      text,
  created_at   timestamptz not null default now()
);

comment on table public_holidays is 'Public/company holidays excluded from add_working_days() — the "5 working days" Corrective Action due-date calculation. Admin-managed via Master Control -> Holidays.';

alter table public_holidays enable row level security;

create policy "authenticated can read holidays"
  on public_holidays for select
  to authenticated
  using (true);

create policy "admin can manage holidays"
  on public_holidays for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

insert into public_holidays (holiday_date, name, name_th) values
  ('2026-01-01', 'New Year''s Day', 'วันขึ้นปีใหม่'),
  ('2026-01-02', 'New Year Special Holiday', 'วันหยุดพิเศษ (ต่อเนื่องปีใหม่)'),
  ('2026-03-03', 'Makha Bucha Day', 'วันมาฆบูชา'),
  ('2026-04-06', 'Chakri Day', 'วันจักรี'),
  ('2026-04-13', 'Songkran Festival', 'วันสงกรานต์'),
  ('2026-04-14', 'Songkran Festival', 'วันสงกรานต์'),
  ('2026-04-15', 'Songkran Festival', 'วันสงกรานต์'),
  ('2026-05-01', 'National Labour Day', 'วันแรงงานแห่งชาติ'),
  ('2026-05-04', 'Coronation Day', 'วันฉัตรมงคล'),
  ('2026-05-31', 'Visakha Bucha Day', 'วันวิสาขบูชา'),
  ('2026-06-01', 'Substitution for Visakha Bucha Day', 'วันหยุดชดเชยวันวิสาขบูชา'),
  ('2026-06-03', 'H.M. Queen Suthida''s Birthday', 'วันเฉลิมพระชนมพรรษาสมเด็จพระราชินี'),
  ('2026-07-28', 'H.M. King Vajiralongkorn''s Birthday', 'วันเฉลิมพระชนมพรรษา ร.10'),
  ('2026-07-29', 'Asalha Bucha Day', 'วันอาสาฬหบูชา'),
  ('2026-08-12', 'H.M. Queen Mother''s Birthday (Mother''s Day)', 'วันแม่แห่งชาติ'),
  ('2026-10-13', 'Anniversary of the Death of King Bhumibol', 'วันคล้ายวันสวรรคต ร.9'),
  ('2026-10-23', 'Chulalongkorn Day', 'วันปิยมหาราช'),
  ('2026-12-05', 'H.M. King Bhumibol''s Birthday (Father''s Day)', 'วันพ่อแห่งชาติ'),
  ('2026-12-07', 'Substitution for King Bhumibol''s Birthday', 'วันหยุดชดเชยวันพ่อแห่งชาติ'),
  ('2026-12-10', 'Constitution Day', 'วันรัฐธรรมนูญ'),
  ('2026-12-31', 'New Year''s Eve', 'วันสิ้นปี')
on conflict (holiday_date) do nothing;

-- ------------------------------------------------------------
-- Update add_working_days() to also skip public_holidays, not just
-- weekends. Same signature/name, so the existing caller (the
-- auto_create_corrective_action trigger in 08_corrective_action_
-- workflow.sql) picks this up automatically — no other file needs to
-- change.
-- ------------------------------------------------------------
create or replace function public.add_working_days(start_date date, n int)
returns date as $$
declare
  d date := start_date;
  remaining int := n;
begin
  while remaining > 0 loop
    d := d + 1;
    if extract(isodow from d) < 6  -- Mon=1 .. Fri=5, Sat=6, Sun=7
       and not exists (select 1 from public_holidays where holiday_date = d) then
      remaining := remaining - 1;
    end if;
  end loop;
  return d;
end;
$$ language plpgsql stable;

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * Only 2026 is seeded. Add future years' holidays the same way
--   (via Master Control -> Holidays, or another SQL insert) before
--   they're needed — a CA due date calculated in late 2026 that spills
--   into January 2027 would use the plain weekend-only rule for any
--   date beyond what's seeded here, since there's nothing to look up.
-- * This function changed from IMMUTABLE to STABLE (it now reads from
--   a table, which can change, so it can no longer be marked as
--   always returning the same output for the same input).
-- ============================================================
