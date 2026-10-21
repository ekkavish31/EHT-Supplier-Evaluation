-- ============================================================
-- 32_supplier_group_by_prefix.sql
-- Replaces the old fragmented supplier grouping (Material / Part /
-- Heat Treatment / Plating / Outsource — the last two were a
-- best-effort KEYWORD GUESS on company name from
-- 21_supplier_category_cleanup.sql, confirmed unverified for several
-- suppliers) with a single deterministic rule based on the supplier
-- code prefix, decided directly by the business:
--   MA- -> 'Material'
--   OS- -> 'Outsource'   (covers Heat Treatment, Surface Treatment, Plating)
--   PA- -> 'Blank Part'
--
-- This is enforced with a trigger, not just a one-time backfill, so it
-- can never drift again — whatever a client sends for `category`
-- (Master Control UI, Excel import, direct SQL) is overwritten based
-- on the row's own `code` before it's ever stored. The only way to
-- change a supplier's group after this is to change its code prefix.
--
-- Run this once in the Supabase SQL editor, after 21 has already run.
-- ============================================================

-- ------------------------------------------------------------
-- 1) One-time backfill — collapses every existing category value
--    (including the guessed Heat Treatment/Plating/Outsource split)
--    down to the 3 real groups.
-- ------------------------------------------------------------
update suppliers set category = 'Material'    where code like 'MA-%';
update suppliers set category = 'Outsource'   where code like 'OS-%';
update suppliers set category = 'Blank Part'  where code like 'PA-%';

-- Anything with a code prefix outside MA-/OS-/PA- (shouldn't exist
-- today, but don't silently misclassify it if it ever does) falls
-- back to NULL rather than guessing.
update suppliers set category = null
  where code not like 'MA-%' and code not like 'OS-%' and code not like 'PA-%';

-- ------------------------------------------------------------
-- 2) Trigger — derives category from code on every insert/update,
--    regardless of what the client sent for that column.
-- ------------------------------------------------------------
create or replace function public.derive_supplier_category_from_code()
returns trigger as $$
begin
  if new.code like 'MA-%' then
    new.category := 'Material';
  elsif new.code like 'OS-%' then
    new.category := 'Outsource';
  elsif new.code like 'PA-%' then
    new.category := 'Blank Part';
  else
    new.category := null;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_derive_supplier_category on suppliers;
create trigger trg_derive_supplier_category
  before insert or update of code, category on suppliers
  for each row execute function public.derive_supplier_category_from_code();

-- Sanity check
select category, count(*) from suppliers group by category order by category;
