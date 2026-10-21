-- ============================================================
-- 04_simplify_admin_login.sql
--
-- Changes the admin login from:
--   admin@admin.com / admin1234
-- to:
--   admin01 / 413723
--
-- The app now shows a short "User ID" field instead of an email field,
-- but Supabase Auth still needs an email-shaped address internally.
-- app.js automatically appends the domain below to whatever the user
-- types, so the person only ever sees/types "admin01".
--
-- IMPORTANT: this domain must exactly match LOGIN_EMAIL_DOMAIN in app.js
-- (currently '@eht.local'). If you change one, change the other.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

-- 1) Make sure pgcrypto is available for hashing the new password
--    (Supabase projects normally already have this enabled)
create extension if not exists pgcrypto with schema extensions;

-- 2) Update the login itself: email -> admin01@eht.local, password -> 413723
update auth.users
set
  email               = 'admin01@eht.local',
  encrypted_password  = extensions.crypt('413723', extensions.gen_salt('bf')),
  email_confirmed_at  = coalesce(email_confirmed_at, now()),
  updated_at          = now()
where email = 'admin@admin.com';

-- 3) Keep auth.identities in sync (Supabase keeps its own copy of the
--    email address here for the "email" provider identity)
update auth.identities
set
  identity_data = jsonb_set(identity_data, '{email}', to_jsonb('admin01@eht.local'::text)),
  updated_at    = now()
where provider = 'email'
  and user_id = (select id from auth.users where email = 'admin01@eht.local');

-- 4) Sanity check — should show exactly one row with the new email
select id, email, email_confirmed_at from auth.users where email = 'admin01@eht.local';

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * Password rules: Supabase's default minimum password length is 6
--   characters, which "413723" already satisfies, so no Auth setting
--   needs to change for this specific password. If you ever want to
--   go shorter than 6, that requires lowering "Minimum password length"
--   in Supabase Dashboard -> Authentication -> Providers -> Email
--   (this is a project setting, not something SQL can change).
--
-- * To create MORE users with short IDs going forward (via
--   Dashboard -> Authentication -> Users -> Add user), just set their
--   email to "<shortid>@eht.local" (e.g. qa01@eht.local) and a 6-char
--   password directly — no need to run this script again, this one is
--   only for renaming the existing admin@admin.com account.
--
-- * After adding a user, remember to set their department in the
--   user_profiles table (qa / cs / mp / supervisor) — the
--   handle_new_user trigger creates the row automatically but leaves
--   department blank.
