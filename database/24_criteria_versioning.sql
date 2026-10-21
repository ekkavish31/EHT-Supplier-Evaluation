-- ============================================================
-- 24_criteria_versioning.sql
-- Evaluation criteria become immutable once actually used in a real
-- evaluation (evaluation_items references it) — editing them further
-- would silently rewrite the meaning of historical reports. Instead,
-- editing an already-used criteria creates a new "version" in the
-- same lineage: old row is deactivated (is_active=false) and points
-- to the new one (superseded_by); the new row carries on the same
-- lineage_id so Dashboard/Issue Pareto can still aggregate across all
-- versions as "the same topic" while each historical evaluation keeps
-- pointing at the exact version that was true when it was scored.
--
-- Run this once in the Supabase SQL editor.
-- ============================================================

alter table evaluation_criteria
  add column lineage_id    uuid,
  add column version       int not null default 1,
  add column superseded_by uuid references evaluation_criteria(id);

-- Backfill: every existing criteria is version 1 of its own lineage.
update evaluation_criteria set lineage_id = id where lineage_id is null;
alter table evaluation_criteria alter column lineage_id set not null;

create index idx_criteria_lineage on evaluation_criteria(lineage_id);

comment on column evaluation_criteria.lineage_id is 'Constant across every version of "the same topic" — use this (not id) when aggregating occurrence counts across time in the Dashboard, since id changes every time a used criteria is versioned.';
comment on column evaluation_criteria.version is 'Starts at 1, +1 every time this lineage is versioned (create_criteria_version()).';
comment on column evaluation_criteria.superseded_by is 'Points to the next version in this lineage, once this one has been replaced. Null = this is the current/latest version.';

-- ------------------------------------------------------------
-- Has this specific criteria row ever been used in a real evaluation?
-- ------------------------------------------------------------
create or replace function public.criteria_is_used(p_criteria_id uuid)
returns boolean as $$
  select exists (select 1 from evaluation_items where criteria_id = p_criteria_id);
$$ language sql stable security definer set search_path = public;

-- ------------------------------------------------------------
-- Immutability trigger — once used, only display_order and is_active
-- can still change directly. Everything else must go through
-- create_criteria_version() instead.
-- ------------------------------------------------------------
create or replace function public.enforce_criteria_immutability()
returns trigger as $$
begin
  if public.criteria_is_used(old.id) then
    if new.item_no is distinct from old.item_no
       or new.description is distinct from old.description
       or new.description_th is distinct from old.description_th
       or new.full_score is distinct from old.full_score
       or new.deduction_points is distinct from old.deduction_points
       or new.category is distinct from old.category
       or new.lineage_id is distinct from old.lineage_id
       or new.version is distinct from old.version then
      raise exception 'This criteria has already been used in a real evaluation and cannot be edited directly — create a new version instead (see create_criteria_version()).';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_enforce_criteria_immutability on evaluation_criteria;
create trigger trg_enforce_criteria_immutability
  before update on evaluation_criteria
  for each row execute function public.enforce_criteria_immutability();

create or replace function public.prevent_used_criteria_delete()
returns trigger as $$
begin
  if public.criteria_is_used(old.id) then
    raise exception 'This criteria has already been used in a real evaluation and cannot be deleted — set is_active = false instead.';
  end if;
  return old;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_prevent_used_criteria_delete on evaluation_criteria;
create trigger trg_prevent_used_criteria_delete
  before delete on evaluation_criteria
  for each row execute function public.prevent_used_criteria_delete();

-- ------------------------------------------------------------
-- create_new_criteria() — for the "+ Add New" path (no prior
-- version, starts a brand new lineage).
-- ------------------------------------------------------------
create or replace function public.create_new_criteria(
  p_category text, p_item_no text, p_description text, p_description_th text,
  p_full_score numeric, p_deduction_points numeric, p_display_order int
) returns uuid as $$
declare
  v_id uuid;
begin
  if not public.has_permission('master_data_manage') then
    raise exception 'Only Admin can manage evaluation criteria';
  end if;

  insert into evaluation_criteria (category, item_no, description, description_th, full_score, deduction_points, display_order, is_active)
  values (p_category, p_item_no, p_description, p_description_th, p_full_score, p_deduction_points, p_display_order, true)
  returning id into v_id;

  update evaluation_criteria set lineage_id = v_id, version = 1 where id = v_id;
  return v_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- create_criteria_version() — for the "Edit" path on a criteria that
-- turns out to already be used: closes the old row and opens a new
-- one in the same lineage, atomically.
-- ------------------------------------------------------------
create or replace function public.create_criteria_version(
  p_old_id uuid, p_category text, p_item_no text, p_description text, p_description_th text,
  p_full_score numeric, p_deduction_points numeric, p_display_order int
) returns uuid as $$
declare
  v_lineage uuid;
  v_version int;
  v_new_id uuid;
begin
  if not public.has_permission('master_data_manage') then
    raise exception 'Only Admin can manage evaluation criteria';
  end if;

  select lineage_id, version into v_lineage, v_version from evaluation_criteria where id = p_old_id;
  if not found then
    raise exception 'Original criteria not found';
  end if;

  insert into evaluation_criteria (category, item_no, description, description_th, full_score, deduction_points, display_order, is_active, lineage_id, version)
  values (p_category, p_item_no, p_description, p_description_th, p_full_score, p_deduction_points, p_display_order, true, v_lineage, v_version + 1)
  returning id into v_new_id;

  update evaluation_criteria set is_active = false, superseded_by = v_new_id where id = p_old_id;

  return v_new_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- Notes
-- ------------------------------------------------------------
-- * display_order and is_active can still be changed with a plain
--   UPDATE even on a used criteria (the immutability trigger only
--   blocks the other fields) — no need to go through a function for
--   those two.
-- * The app calls create_new_criteria() / create_criteria_version()
--   via supabase-js .rpc(), checking criteria_is_used() first to
--   decide which path applies (see app.js saveCriteria()).
-- * Dashboard aggregation (Issue Pareto) must group occurrence counts
--   by lineage_id, not id, to correctly combine all versions of "the
--   same topic" into one bar — see the app.js change in this same
--   package version.
-- ============================================================
