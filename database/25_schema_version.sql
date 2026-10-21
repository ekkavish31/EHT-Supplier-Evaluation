-- ============================================================
-- 25_schema_version.sql
-- Tracks which migration the database is currently at, so the app can
-- refuse to run against a database that's missing migrations it
-- depends on (instead of loading and then failing confusingly on
-- whichever specific feature touches the missing piece first).
--
-- Run this LAST, after every other migration up through 24, since its
-- own version number reflects "24 has been applied".
-- ============================================================

create table if not exists public.app_schema_version (
  id             integer primary key default 1 check (id = 1),
  version        integer not null,
  package_version text not null,
  applied_at     timestamptz not null default now()
);

comment on table app_schema_version is 'Single-row table (id always 1) recording the latest migration number applied. The app checks this on startup (see REQUIRED_SCHEMA_VERSION in app.js) and blocks with a clear message instead of loading half-broken if the database is behind.';

alter table app_schema_version enable row level security;

create policy "authenticated can read schema version"
  on app_schema_version for select
  to authenticated
  using (true);
-- No write policy for normal users — updated only by migrations
-- themselves (run as the SQL-editor/service role, which bypasses RLS).

insert into app_schema_version (id, version, package_version)
values (1, 25, 'v35')
on conflict (id) do update
set version = excluded.version,
    package_version = excluded.package_version,
    applied_at = now();

-- ------------------------------------------------------------
-- Going forward: every future migration file should end with a line
-- like this (bumping the numbers to match), so app_schema_version
-- always reflects the truth after running migrations in order:
--
--   insert into app_schema_version (id, version, package_version)
--   values (1, 26, 'v36')
--   on conflict (id) do update
--   set version = excluded.version, package_version = excluded.package_version, applied_at = now();
-- ============================================================
