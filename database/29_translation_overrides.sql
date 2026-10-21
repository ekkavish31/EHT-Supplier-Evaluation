-- ============================================================
-- 29_translation_overrides.sql
-- Lets Admin customize how specific UI labels/loanwords are shown,
-- without needing a code change each time. Deliberately an "override
-- layer" on top of the existing hardcoded TH dictionary in app.js —
-- NOT a full rewrite of the translation system (~700 existing keys
-- stay exactly as they are; this only kicks in for whichever specific
-- keys an Admin has explicitly overridden).
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

create table translation_overrides (
  id          uuid primary key default gen_random_uuid(),
  key         text not null unique,       -- matches a data-i18n key used in the app
  th_text     text,                       -- null = fall through to the built-in Thai text
  en_text     text,                       -- null = fall through to the built-in English text
  updated_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now()
);

comment on table translation_overrides is 'Admin-managed label overrides — checked by t()/applyLang() before falling back to the hardcoded TH dictionary in app.js. Lets an Admin customize wording (especially loanwords/transliterated terms) for both languages without a code deploy.';

alter table translation_overrides enable row level security;

-- Everyone authenticated can read (every user's UI needs these to
-- render); only Admin can write.
create policy "authenticated can read translation overrides"
  on translation_overrides for select
  to authenticated
  using (true);

create policy "admin can manage translation overrides"
  on translation_overrides for all
  to authenticated
  using (public.has_permission('master_data_manage'))
  with check (public.has_permission('master_data_manage'));

create index idx_translation_overrides_key on translation_overrides(key);

insert into app_schema_version (id, version, package_version)
values (1, 29, 'v55')
on conflict (id) do update
set version = excluded.version, package_version = excluded.package_version, applied_at = now();
