-- ============================================================
-- 06_confirm_stuck_users.sql
--
-- Because logins use fake addresses like "xxxx@eht.local" (not real
-- email addresses), any account created while Supabase's "Confirm
-- email" setting was ON can never confirm itself by clicking a link
-- - that email will never arrive anywhere. This script manually marks
-- every such stuck account as confirmed so they can log in.
--
-- Run this once now to unstick any accounts already created (e.g.
-- test_qa01), and again any time in the future if you forget to turn
-- off "Confirm email" before someone signs up.
--
-- Recommended: also turn OFF "Confirm email" in
-- Supabase Dashboard -> Authentication -> Providers -> Email,
-- so this script becomes unnecessary going forward.
-- ============================================================

update auth.users
set
  email_confirmed_at = now(),
  confirmed_at        = now()
where email like '%@eht.local'
  and email_confirmed_at is null;

-- Sanity check — should return 0 rows after running the update above
select id, email, email_confirmed_at
from auth.users
where email like '%@eht.local'
  and email_confirmed_at is null;
