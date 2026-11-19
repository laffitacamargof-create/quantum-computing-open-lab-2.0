-- 20261114162031_secure_quolab_nexus_public_api

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.quolab_nexus_secret_archive (
  key text primary key,
  value text,
  archived_at timestamptz not null default now(),
  archive_reason text not null default 'Removed from the exposed public configuration table'
);
revoke all on table private.quolab_nexus_secret_archive from public, anon, authenticated;

insert into private.quolab_nexus_secret_archive (key, value)
select key, value
from public.quantum_ecosystem_config
where key in ('ai_config','deepseek_config','github_config','founder_password')
on conflict (key) do update
set value = excluded.value, archived_at = now();

delete from public.quantum_ecosystem_config
where key in ('ai_config','deepseek_config','github_config','founder_password');

drop policy if exists "Allow all" on public.quantum_ecosystem_config;
revoke all on table public.quantum_ecosystem_config from public, anon, authenticated;
grant select on table public.quantum_ecosystem_config to anon, authenticated;
create policy "public_read_non_secret_nexus_config"
on public.quantum_ecosystem_config for select
to anon, authenticated
using (key in ('colab_url','system_config','platform_config','monitor_config'));

drop policy if exists "Allow all" on public.quantum_pending_apps;
revoke all on table public.quantum_pending_apps from public, anon, authenticated;

drop policy if exists "Allow all" on public.quantum_published_apps;
revoke all on table public.quantum_published_apps from public, anon, authenticated;
grant select on table public.quantum_published_apps to anon, authenticated;
create policy "public_read_active_nexus_apps"
on public.quantum_published_apps for select
to anon, authenticated
using (is_active is true);

drop policy if exists "Allow all versions" on public.quantum_app_versions;
revoke all on table public.quantum_app_versions from public, anon, authenticated;
grant select on table public.quantum_app_versions to anon, authenticated;
create policy "public_read_nexus_app_versions"
on public.quantum_app_versions for select
to anon, authenticated
using (true);

revoke all on table public.repo_items from public, anon, authenticated;
grant select on table public.repo_items to anon, authenticated;
revoke all on table public.repo_item_keys from public, anon, authenticated;
revoke all on table public.repo_admin from public, anon, authenticated;

create or replace function public.repo_hash(k text)
returns text
language sql
immutable
set search_path = pg_catalog
as $function$
  select pg_catalog.encode(
    pg_catalog.sha256(pg_catalog.convert_to(coalesce(k, ''), 'UTF8')),
    'hex'
  )
$function$;

create or replace function public.quantum_submit_app(p_app jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id text := pg_catalog.gen_random_uuid()::text;
  v_name text;
  v_title text;
  v_description text;
  v_tags text;
  v_duration integer;
  v_python text;
  v_html text;
  v_server_url text;
begin
  if pg_catalog.jsonb_typeof(p_app) <> 'object' then
    raise exception 'invalid app payload';
  end if;

  v_name := pg_catalog.left(pg_catalog.coalesce(nullif(pg_catalog.btrim(p_app->>'name'), ''), nullif(pg_catalog.btrim(p_app->>'title'), ''), 'Untitled'), 100);
  v_title := pg_catalog.left(pg_catalog.coalesce(nullif(pg_catalog.btrim(p_app->>'title'), ''), v_name), 100);
  v_description := pg_catalog.left(pg_catalog.coalesce(p_app->>'description', ''), 500);
  v_tags := pg_catalog.left(pg_catalog.coalesce(p_app->>'tags', ''), 300);
  v_duration := greatest(1, least(240, coalesce(nullif(p_app->>'duration','')::integer, 8)));
  v_python := pg_catalog.coalesce(p_app->>'python_code', p_app->>'pythonCode', '');
  v_html := pg_catalog.coalesce(p_app->>'html_code', p_app->>'htmlCode', '');
  v_server_url := pg_catalog.coalesce(p_app->>'server_url', p_app->>'serverUrl', '');

  if pg_catalog.length(v_python) > 1000000 or pg_catalog.length(v_html) > 1000000 then
    raise exception 'app code too large';
  end if;
  if v_server_url <> '' and v_server_url !~* '^https?://' then
    raise exception 'invalid server url';
  end if;

  insert into public.quantum_pending_apps
    (id, name, title, description, tags, duration, python_code, html_code,
     server_url, created_by, created_at, updated_at, status, submitted_by, submitted_at)
  values
    (v_id, v_name, v_title, v_description, v_tags, v_duration, v_python, v_html,
     v_server_url, pg_catalog.left(pg_catalog.coalesce(p_app->>'created_by','anonymous'),120),
     now(), now(), 'pending',
     pg_catalog.left(pg_catalog.coalesce(p_app->>'submitted_by', p_app->>'created_by', 'anonymous'),120), now());

  return v_id;
end
$function$;

create or replace function public.quantum_list_pending(p_key text)
returns setof public.quantum_pending_apps
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.repo_is_founder(p_key) then
    raise exception 'forbidden';
  end if;
  return query
    select * from public.quantum_pending_apps order by created_at desc;
end
$function$;

create or replace function public.quantum_approve_app(p_id text, p_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_pending public.quantum_pending_apps%rowtype;
  v_published public.quantum_published_apps%rowtype;
begin
  if not public.repo_is_founder(p_key) then
    raise exception 'forbidden';
  end if;

  select * into v_pending
  from public.quantum_pending_apps
  where id = p_id
  for update;

  if not found then
    raise exception 'not_found';
  end if;

  insert into public.quantum_published_apps
    (id, name, title, description, tags, duration, python_code, html_code,
     server_url, created_by, created_at, updated_at, published_by,
     published_at, version, is_active)
  values
    (v_pending.id, v_pending.name, v_pending.title, v_pending.description,
     v_pending.tags, v_pending.duration, v_pending.python_code, v_pending.html_code,
     v_pending.server_url, v_pending.created_by, v_pending.created_at, now(),
     'founder', now(), 1, true)
  on conflict (id) do update set
    name = excluded.name,
    title = excluded.title,
    description = excluded.description,
    tags = excluded.tags,
    duration = excluded.duration,
    python_code = excluded.python_code,
    html_code = excluded.html_code,
    server_url = excluded.server_url,
    updated_at = now(),
    published_by = 'founder',
    published_at = now(),
    version = public.quantum_published_apps.version + 1,
    is_active = true
  returning * into v_published;

  delete from public.quantum_pending_apps where id = p_id;
  return pg_catalog.to_jsonb(v_published);
end
$function$;

create or replace function public.quantum_reject_app(p_id text, p_key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare v_count integer;
begin
  if not public.repo_is_founder(p_key) then
    raise exception 'forbidden';
  end if;
  delete from public.quantum_pending_apps where id = p_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end
$function$;

create or replace function public.quantum_delete_published_app(p_id text, p_key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare v_count integer;
begin
  if not public.repo_is_founder(p_key) then
    raise exception 'forbidden';
  end if;
  delete from public.quantum_published_apps where id = p_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end
$function$;

create or replace function public.quantum_config_save(p_key text, p_value text, p_founder_key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.repo_is_founder(p_founder_key) then
    raise exception 'forbidden';
  end if;
  if p_key not in ('colab_url','system_config','platform_config','monitor_config') then
    raise exception 'configuration key is not cloud-shareable';
  end if;
  insert into public.quantum_ecosystem_config (id, key, value, updated_by, updated_at, created_at)
  values ('cfg-' || p_key, p_key, p_value, 'founder_panel', now(), now())
  on conflict (key) do update
    set value = excluded.value, updated_by = 'founder_panel', updated_at = now();
  return true;
end
$function$;

revoke execute on function public.repo_hash(text) from public, anon, authenticated;
revoke execute on function public.repo_can_edit(uuid,text) from public, anon, authenticated;
revoke execute on function public.repo_create(text,text,text,text,text,integer,integer,text,jsonb,text,text) from public, anon, authenticated;
revoke execute on function public.repo_delete(uuid,text) from public, anon, authenticated;
revoke execute on function public.repo_is_founder(text) from public, anon, authenticated;
revoke execute on function public.repo_update(uuid,text,text,text,text,integer,integer,jsonb,text) from public, anon, authenticated;
grant execute on function public.repo_create(text,text,text,text,text,integer,integer,text,jsonb,text,text) to anon;
grant execute on function public.repo_delete(uuid,text) to anon;
grant execute on function public.repo_is_founder(text) to anon;
grant execute on function public.repo_update(uuid,text,text,text,text,integer,integer,jsonb,text) to anon;

revoke execute on function public.quantum_submit_app(jsonb) from public, anon, authenticated;
revoke execute on function public.quantum_list_pending(text) from public, anon, authenticated;
revoke execute on function public.quantum_approve_app(text,text) from public, anon, authenticated;
revoke execute on function public.quantum_reject_app(text,text) from public, anon, authenticated;
revoke execute on function public.quantum_delete_published_app(text,text) from public, anon, authenticated;
revoke execute on function public.quantum_config_save(text,text,text) from public, anon, authenticated;
grant execute on function public.quantum_submit_app(jsonb) to anon;
grant execute on function public.quantum_list_pending(text) to anon;
grant execute on function public.quantum_approve_app(text,text) to anon;
grant execute on function public.quantum_reject_app(text,text) to anon;
grant execute on function public.quantum_delete_published_app(text,text) to anon;
grant execute on function public.quantum_config_save(text,text,text) to anon;


-- 20261114162307_fix_quantum_submit_app_search_path
create or replace function public.quantum_submit_app(p_app jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id text := pg_catalog.gen_random_uuid()::text;
  v_name text;
  v_title text;
  v_description text;
  v_tags text;
  v_duration integer;
  v_python text;
  v_html text;
  v_server_url text;
begin
  if pg_catalog.jsonb_typeof(p_app) <> 'object' then
    raise exception 'invalid app payload';
  end if;
  v_name := pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'name'), ''), nullif(pg_catalog.btrim(p_app->>'title'), ''), 'Untitled'), 100);
  v_title := pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'title'), ''), v_name), 100);
  v_description := pg_catalog.left(coalesce(p_app->>'description', ''), 500);
  v_tags := pg_catalog.left(coalesce(p_app->>'tags', ''), 300);
  v_duration := greatest(1, least(240, coalesce(nullif(p_app->>'duration','')::integer, 8)));
  v_python := coalesce(p_app->>'python_code', p_app->>'pythonCode', '');
  v_html := coalesce(p_app->>'html_code', p_app->>'htmlCode', '');
  v_server_url := coalesce(p_app->>'server_url', p_app->>'serverUrl', '');
  if pg_catalog.length(v_python) > 1000000 or pg_catalog.length(v_html) > 1000000 then
    raise exception 'app code too large';
  end if;
  if v_server_url <> '' and v_server_url !~* '^https?://' then
    raise exception 'invalid server url';
  end if;
  insert into public.quantum_pending_apps
    (id, name, title, description, tags, duration, python_code, html_code,
     server_url, created_by, created_at, updated_at, status, submitted_by, submitted_at)
  values
    (v_id, v_name, v_title, v_description, v_tags, v_duration, v_python, v_html,
     v_server_url, pg_catalog.left(coalesce(p_app->>'created_by','anonymous'),120),
     now(), now(), 'pending',
     pg_catalog.left(coalesce(p_app->>'submitted_by', p_app->>'created_by', 'anonymous'),120), now());
  return v_id;
end
$function$;

-- 20261114162333_remove_plaintext_secret_archive_values
alter table private.quolab_nexus_secret_archive drop column if exists value;
comment on table private.quolab_nexus_secret_archive is
  'Audit record of configuration keys removed from the exposed public table. Secret values are intentionally not retained.';

-- 20261114181736_harden_repo_functions_and_query_indexes
-- QuOLab Nexus database hardening: pin SECURITY DEFINER functions to an empty search_path.
-- All application objects are schema-qualified to prevent object-shadowing attacks.
create or replace function public.repo_is_founder(p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.repo_admin
    where key_hash = public.repo_hash(p_key)
  )
$function$;

create or replace function public.repo_can_edit(p_id uuid, p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.repo_is_founder(p_key)
      or exists (
        select 1 from public.repo_item_keys
        where item_id = p_id
          and key_hash = public.repo_hash(p_key)
      )
$function$;

create or replace function public.repo_create(
  p_kind text,
  p_title text,
  p_edit_key text,
  p_description text default '',
  p_tags text default '',
  p_cell_count integer default 0,
  p_est_minutes integer default 10,
  p_author text default '',
  p_content jsonb default null,
  p_file_url text default '',
  p_slug text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  new_id uuid;
begin
  if p_kind not in ('nb','pdf','video') then raise exception 'invalid kind'; end if;
  if coalesce(pg_catalog.btrim(p_title), '') = '' then raise exception 'title required'; end if;
  if pg_catalog.length(p_title) > 200
     or pg_catalog.length(coalesce(p_description,'')) > 2000
     or pg_catalog.length(coalesce(p_tags,'')) > 300
     or pg_catalog.length(coalesce(p_author,'')) > 120 then
    raise exception 'field too long';
  end if;
  if pg_catalog.length(coalesce(p_edit_key, '')) < 16 then raise exception 'forbidden'; end if;
  if coalesce(p_file_url,'') <> '' and p_file_url !~* '^https?://' then
    raise exception 'invalid url';
  end if;
  if p_slug is not null and p_slug !~ '^[a-z0-9_-]{1,80}$' then
    raise exception 'invalid slug';
  end if;

  if p_kind = 'nb' then
    if p_content is null or pg_catalog.jsonb_typeof(p_content) <> 'array'
       or pg_catalog.jsonb_array_length(p_content) = 0 then
      raise exception 'notebook content required';
    end if;
    if pg_catalog.length(p_content::text) > 2000000 then raise exception 'content too large'; end if;
  else
    if not public.repo_is_founder(p_edit_key) then raise exception 'forbidden'; end if;
  end if;

  insert into public.repo_items
    (kind, slug, title, description, tags, cell_count, est_minutes,
     author_name, content, file_url)
  values
    (p_kind, p_slug, pg_catalog.btrim(p_title), coalesce(p_description,''),
     coalesce(p_tags,''), greatest(coalesce(p_cell_count,0),0),
     greatest(coalesce(p_est_minutes,10),1), coalesce(p_author,''),
     case when p_kind = 'nb' then p_content else null end,
     coalesce(p_file_url,''))
  returning id into new_id;

  insert into public.repo_item_keys (item_id, key_hash)
  values (new_id, public.repo_hash(p_edit_key));
  return new_id;
end
$function$;

create or replace function public.repo_update(
  p_id uuid,
  p_key text,
  p_title text default null,
  p_description text default null,
  p_tags text default null,
  p_cell_count integer default null,
  p_est_minutes integer default null,
  p_content jsonb default null,
  p_file_url text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not exists (select 1 from public.repo_items where id = p_id) then
    raise exception 'not_found';
  end if;
  if not public.repo_can_edit(p_id, p_key) then raise exception 'forbidden'; end if;
  if pg_catalog.length(coalesce(p_title,'')) > 200
     or pg_catalog.length(coalesce(p_description,'')) > 2000
     or pg_catalog.length(coalesce(p_tags,'')) > 300 then
    raise exception 'field too long';
  end if;
  if coalesce(p_file_url,'') <> '' and p_file_url !~* '^https?://' then
    raise exception 'invalid url';
  end if;
  if p_content is not null then
    if pg_catalog.jsonb_typeof(p_content) <> 'array'
       or pg_catalog.jsonb_array_length(p_content) = 0 then
      raise exception 'notebook content required';
    end if;
    if pg_catalog.length(p_content::text) > 2000000 then raise exception 'content too large'; end if;
  end if;

  update public.repo_items set
    title = coalesce(nullif(pg_catalog.btrim(p_title), ''), title),
    description = coalesce(p_description, description),
    tags = coalesce(p_tags, tags),
    cell_count = coalesce(p_cell_count, cell_count),
    est_minutes = coalesce(p_est_minutes, est_minutes),
    content = case when kind = 'nb' then coalesce(p_content, content) else content end,
    file_url = coalesce(p_file_url, file_url),
    version = case when p_content is not null then version + 1 else version end,
    updated_at = now()
  where id = p_id;
end
$function$;

create or replace function public.repo_delete(p_id uuid, p_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not exists (select 1 from public.repo_items where id = p_id) then
    raise exception 'not_found';
  end if;
  if not public.repo_can_edit(p_id, p_key) then raise exception 'forbidden'; end if;
  delete from public.repo_items where id = p_id;
end
$function$;

-- Match the repository's actual list/order access patterns.
create index if not exists repo_items_created_at_desc_idx
  on public.repo_items (created_at desc);
create index if not exists quantum_pending_apps_created_at_desc_idx
  on public.quantum_pending_apps (created_at desc);
create index if not exists quantum_app_versions_app_version_idx
  on public.quantum_app_versions (app_id, version desc);


-- 20261114182310_quolab_nexus_private_schema_grants
-- QuOLab Nexus: ensure the private audit schema is not granted to API roles.
-- The table itself has no grants to anon/authenticated; this migration also removes
-- any inherited schema/table/function access if it was granted elsewhere.
revoke all on schema private from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;


-- 20261115072252_restrict_privileged_rpc_execution
-- Apply only after the QuOLab Nexus frontend has been deployed with
-- supabase/functions/quolab-nexus-admin. The Edge Function uses the server-only
-- QUOLAB_NEXUS_SECRET_KEY; browser clients must no longer call these RPCs directly.

revoke execute on function public.quantum_submit_app(jsonb) from public, anon, authenticated;
revoke execute on function public.quantum_list_pending(text) from public, anon, authenticated;
revoke execute on function public.quantum_approve_app(text, text) from public, anon, authenticated;
revoke execute on function public.quantum_reject_app(text, text) from public, anon, authenticated;
revoke execute on function public.quantum_delete_published_app(text, text) from public, anon, authenticated;
revoke execute on function public.quantum_config_save(text, text, text) from public, anon, authenticated;
revoke execute on function public.repo_is_founder(text) from public, anon, authenticated;
revoke execute on function public.repo_can_edit(uuid, text) from public, anon, authenticated;
revoke execute on function public.repo_create(text, text, text, text, text, integer, integer, text, jsonb, text, text) from public, anon, authenticated;
revoke execute on function public.repo_update(uuid, text, text, text, text, integer, integer, jsonb, text) from public, anon, authenticated;
revoke execute on function public.repo_delete(uuid, text) from public, anon, authenticated;

grant execute on function public.quantum_submit_app(jsonb) to service_role;
grant execute on function public.quantum_list_pending(text) to service_role;
grant execute on function public.quantum_approve_app(text, text) to service_role;
grant execute on function public.quantum_reject_app(text, text) to service_role;
grant execute on function public.quantum_delete_published_app(text, text) to service_role;
grant execute on function public.quantum_config_save(text, text, text) to service_role;
grant execute on function public.repo_is_founder(text) to service_role;
grant execute on function public.repo_can_edit(uuid, text) to service_role;
grant execute on function public.repo_create(text, text, text, text, text, integer, integer, text, jsonb, text, text) to service_role;
grant execute on function public.repo_update(uuid, text, text, text, text, integer, integer, jsonb, text) to service_role;
grant execute on function public.repo_delete(uuid, text) to service_role;

-- Defense in depth for the private secret archive. No client role receives access.
alter table private.quolab_nexus_secret_archive enable row level security;
revoke all on table private.quolab_nexus_secret_archive from public, anon, authenticated;

-- 20261117160635_secure_temporary_founder_sessions
create table if not exists private.repo_founder_sessions (
  token_hash text primary key,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz
);
alter table private.repo_founder_sessions enable row level security;
revoke all on table private.repo_founder_sessions from public, anon, authenticated;

create or replace function public.repo_is_founder(p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.repo_admin
    where key_hash = public.repo_hash(p_key)
  ) or exists (
    select 1 from private.repo_founder_sessions
    where token_hash = public.repo_hash(p_key)
      and revoked_at is null
      and expires_at > now()
  )
$function$;

create or replace function public.repo_create_founder_session(p_key text)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token text;
begin
  if p_key is null or length(p_key) < 16 or length(p_key) > 512
     or not exists (
       select 1 from public.repo_admin
       where key_hash = public.repo_hash(p_key)
     ) then
    raise exception 'forbidden';
  end if;

  v_token := replace(gen_random_uuid()::text, '-', '') ||
             replace(gen_random_uuid()::text, '-', '');
  insert into private.repo_founder_sessions(token_hash, expires_at)
  values (public.repo_hash(v_token), now() + interval '8 hours');
  return v_token;
end
$function$;

create or replace function public.repo_revoke_founder_session(p_token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare v_count integer;
begin
  update private.repo_founder_sessions
     set revoked_at = now()
   where token_hash = public.repo_hash(p_token)
     and revoked_at is null;
  get diagnostics v_count = row_count;
  return v_count > 0;
end
$function$;

revoke all on function public.repo_create_founder_session(text) from public;
revoke all on function public.repo_revoke_founder_session(text) from public;
grant execute on function public.repo_create_founder_session(text) to anon, authenticated;
grant execute on function public.repo_revoke_founder_session(text) to anon, authenticated;


-- 20261117160901_restrict_founder_session_rpc_to_service_role
revoke all on function public.repo_create_founder_session(text) from public, anon, authenticated;
revoke all on function public.repo_revoke_founder_session(text) from public, anon, authenticated;
grant execute on function public.repo_create_founder_session(text) to service_role;
grant execute on function public.repo_revoke_founder_session(text) to service_role;

-- 20261117161534_fix_founder_session_minimum_credential_length
create or replace function public.repo_create_founder_session(p_key text)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token text;
begin
  if p_key is null or length(p_key) < 8 or length(p_key) > 512
     or not exists (
       select 1 from public.repo_admin
       where key_hash = public.repo_hash(p_key)
     ) then
    raise exception 'forbidden';
  end if;

  v_token := replace(gen_random_uuid()::text, '-', '') ||
             replace(gen_random_uuid()::text, '-', '');
  insert into private.repo_founder_sessions(token_hash, expires_at)
  values (public.repo_hash(v_token), now() + interval '8 hours');
  return v_token;
end
$function$;

revoke all on function public.repo_create_founder_session(text) from public, anon, authenticated;
grant execute on function public.repo_create_founder_session(text) to service_role;

-- 20261117194054_founder_edit_published_and_pending_apps

create or replace function public.quantum_update_published_app(p_id text, p_app jsonb, p_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current public.quantum_published_apps%rowtype;
  v_python text;
  v_html text;
  v_server_url text;
  v_result public.quantum_published_apps%rowtype;
begin
  if not public.repo_is_founder(p_key) then raise exception 'forbidden'; end if;
  if pg_catalog.jsonb_typeof(p_app) <> 'object' then raise exception 'invalid app payload'; end if;
  select * into v_current from public.quantum_published_apps where id = p_id for update;
  if not found then raise exception 'not_found'; end if;

  v_python := coalesce(p_app->>'python_code', p_app->>'pythonCode', v_current.python_code, '');
  v_html := coalesce(p_app->>'html_code', p_app->>'htmlCode', v_current.html_code, '');
  v_server_url := coalesce(p_app->>'server_url', p_app->>'serverUrl', v_current.server_url, '');
  if pg_catalog.length(v_python) > 1000000 or pg_catalog.length(v_html) > 1000000 then raise exception 'app code too large'; end if;
  if v_server_url <> '' and v_server_url !~* '^https?://' then raise exception 'invalid server url'; end if;

  insert into public.quantum_app_versions
    (app_id, version, python_code, html_code, published_by, published_at, change_notes)
  values
    (v_current.id, coalesce(v_current.version, 1), v_current.python_code, v_current.html_code,
     'founder', pg_catalog.now(), 'Snapshot before founder edit');

  update public.quantum_published_apps set
    name = pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'name'), ''), nullif(pg_catalog.btrim(p_app->>'title'), ''), v_current.name), 100),
    title = pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'title'), ''), nullif(pg_catalog.btrim(p_app->>'name'), ''), v_current.title), 100),
    description = pg_catalog.left(coalesce(p_app->>'description', v_current.description, ''), 500),
    tags = pg_catalog.left(coalesce(p_app->>'tags', v_current.tags, ''), 300),
    duration = greatest(1, least(240, coalesce(nullif(p_app->>'duration','')::integer, v_current.duration, 8))),
    python_code = v_python,
    html_code = v_html,
    server_url = v_server_url,
    updated_at = pg_catalog.now(),
    version = coalesce(v_current.version, 1) + 1,
    is_active = true
  where id = p_id returning * into v_result;
  return pg_catalog.to_jsonb(v_result);
end
$function$;

create or replace function public.quantum_update_pending_app(p_id text, p_app jsonb, p_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current public.quantum_pending_apps%rowtype;
  v_python text;
  v_html text;
  v_server_url text;
  v_result public.quantum_pending_apps%rowtype;
begin
  if not public.repo_is_founder(p_key) then raise exception 'forbidden'; end if;
  if pg_catalog.jsonb_typeof(p_app) <> 'object' then raise exception 'invalid app payload'; end if;
  select * into v_current from public.quantum_pending_apps where id = p_id for update;
  if not found then raise exception 'not_found'; end if;

  v_python := coalesce(p_app->>'python_code', p_app->>'pythonCode', v_current.python_code, '');
  v_html := coalesce(p_app->>'html_code', p_app->>'htmlCode', v_current.html_code, '');
  v_server_url := coalesce(p_app->>'server_url', p_app->>'serverUrl', v_current.server_url, '');
  if pg_catalog.length(v_python) > 1000000 or pg_catalog.length(v_html) > 1000000 then raise exception 'app code too large'; end if;
  if v_server_url <> '' and v_server_url !~* '^https?://' then raise exception 'invalid server url'; end if;

  update public.quantum_pending_apps set
    name = pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'name'), ''), nullif(pg_catalog.btrim(p_app->>'title'), ''), v_current.name), 100),
    title = pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'title'), ''), nullif(pg_catalog.btrim(p_app->>'name'), ''), v_current.title), 100),
    description = pg_catalog.left(coalesce(p_app->>'description', v_current.description, ''), 500),
    tags = pg_catalog.left(coalesce(p_app->>'tags', v_current.tags, ''), 300),
    duration = greatest(1, least(240, coalesce(nullif(p_app->>'duration','')::integer, v_current.duration, 8))),
    python_code = v_python,
    html_code = v_html,
    server_url = v_server_url,
    updated_at = pg_catalog.now()
  where id = p_id returning * into v_result;
  return pg_catalog.to_jsonb(v_result);
end
$function$;

revoke execute on function public.quantum_update_published_app(text,jsonb,text) from public, anon, authenticated;
revoke execute on function public.quantum_update_pending_app(text,jsonb,text) from public, anon, authenticated;
grant execute on function public.quantum_update_published_app(text,jsonb,text) to anon;
grant execute on function public.quantum_update_pending_app(text,jsonb,text) to anon;


-- 20261117194216_restrict_founder_app_update_rpc_to_service_role

revoke execute on function public.quantum_update_published_app(text,jsonb,text) from public, anon, authenticated;
revoke execute on function public.quantum_update_pending_app(text,jsonb,text) from public, anon, authenticated;
grant execute on function public.quantum_update_published_app(text,jsonb,text) to service_role;
grant execute on function public.quantum_update_pending_app(text,jsonb,text) to service_role;


-- 20261117194355_founder_edit_quantum_apps
-- Founder-only editing for public Quantum Apps.
-- All writes are gated by repo_is_founder(), which accepts valid temporary founder sessions.

create or replace function public.quantum_update_pending_app(p_id text, p_app jsonb, p_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_app public.quantum_pending_apps%rowtype;
  v_python text;
  v_html text;
  v_server text;
begin
  if not public.repo_is_founder(p_key) then raise exception 'forbidden'; end if;
  if pg_catalog.jsonb_typeof(p_app) <> 'object' then raise exception 'invalid app payload'; end if;
  v_python := coalesce(p_app->>'python_code', p_app->>'pythonCode', '');
  v_html := coalesce(p_app->>'html_code', p_app->>'htmlCode', '');
  v_server := coalesce(p_app->>'server_url', p_app->>'serverUrl', '');
  if pg_catalog.length(v_python) > 1000000 or pg_catalog.length(v_html) > 1000000 then
    raise exception 'app code too large';
  end if;
  if v_server <> '' and v_server !~* '^https?://' then raise exception 'invalid server url'; end if;

  update public.quantum_pending_apps
  set name = pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'name'), ''), name), 100),
      title = pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'title'), ''), nullif(pg_catalog.btrim(p_app->>'name'), ''), title), 100),
      description = pg_catalog.left(coalesce(p_app->>'description', description, ''), 500),
      tags = pg_catalog.left(coalesce(p_app->>'tags', tags, ''), 300),
      duration = greatest(1, least(240, coalesce(nullif(p_app->>'duration','')::integer, duration, 8))),
      python_code = v_python,
      html_code = v_html,
      server_url = v_server,
      updated_at = now()
  where id = p_id and status = 'pending'
  returning * into v_app;
  if not found then raise exception 'not_found'; end if;
  return pg_catalog.to_jsonb(v_app);
end
$function$;

create or replace function public.quantum_update_published_app(p_id text, p_app jsonb, p_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_app public.quantum_published_apps%rowtype;
  v_updated public.quantum_published_apps%rowtype;
  v_python text;
  v_html text;
  v_server text;
begin
  if not public.repo_is_founder(p_key) then raise exception 'forbidden'; end if;
  if pg_catalog.jsonb_typeof(p_app) <> 'object' then raise exception 'invalid app payload'; end if;
  select * into v_app from public.quantum_published_apps where id = p_id for update;
  if not found then raise exception 'not_found'; end if;

  v_python := coalesce(p_app->>'python_code', p_app->>'pythonCode', '');
  v_html := coalesce(p_app->>'html_code', p_app->>'htmlCode', '');
  v_server := coalesce(p_app->>'server_url', p_app->>'serverUrl', '');
  if pg_catalog.length(v_python) > 1000000 or pg_catalog.length(v_html) > 1000000 then
    raise exception 'app code too large';
  end if;
  if v_server <> '' and v_server !~* '^https?://' then raise exception 'invalid server url'; end if;

  insert into public.quantum_app_versions
    (app_id, version, python_code, html_code, published_by, published_at, change_notes)
  values
    (v_app.id, coalesce(v_app.version, 1), v_app.python_code, v_app.html_code,
     'founder', now(), 'Snapshot before founder edit');

  update public.quantum_published_apps
  set name = pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'name'), ''), name), 100),
      title = pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_app->>'title'), ''), nullif(pg_catalog.btrim(p_app->>'name'), ''), title), 100),
      description = pg_catalog.left(coalesce(p_app->>'description', description, ''), 500),
      tags = pg_catalog.left(coalesce(p_app->>'tags', tags, ''), 300),
      duration = greatest(1, least(240, coalesce(nullif(p_app->>'duration','')::integer, duration, 8))),
      python_code = v_python,
      html_code = v_html,
      server_url = v_server,
      updated_at = now(),
      published_by = 'founder',
      published_at = now(),
      version = coalesce(version, 1) + 1,
      is_active = true
  where id = p_id
  returning * into v_updated;
  return pg_catalog.to_jsonb(v_updated);
end
$function$;

revoke all on function public.quantum_update_pending_app(text,jsonb,text) from public, anon, authenticated;
revoke all on function public.quantum_update_published_app(text,jsonb,text) from public, anon, authenticated;
grant execute on function public.quantum_update_pending_app(text,jsonb,text) to anon;
grant execute on function public.quantum_update_published_app(text,jsonb,text) to anon;


-- 20261117194459_restrict_app_edit_rpc_to_service_role
-- App-edit RPCs are callable only by the trusted administrative Edge Function.
-- The function itself verifies the temporary founder session before forwarding to these RPCs.
revoke all on function public.quantum_update_pending_app(text,jsonb,text) from public, anon, authenticated;
revoke all on function public.quantum_update_published_app(text,jsonb,text) from public, anon, authenticated;
grant execute on function public.quantum_update_pending_app(text,jsonb,text) to service_role;
grant execute on function public.quantum_update_published_app(text,jsonb,text) to service_role;


-- 20261118081706_allow_public_read_active_quantum_published_apps
create policy "Public can read active quantum apps" on public.quantum_published_apps for select to anon, authenticated using (is_active = true);

-- 20261118231452_quolab_nexus_connectors_20261118
-- QuOLab Nexus connector community store.
-- Credentials are never submitted here; only validated connector code and metadata.
-- Private SECURITY DEFINER functions are called through public SECURITY INVOKER RPC wrappers.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to anon, authenticated;

create table if not exists public.nexus_pending_connectors (
  id text primary key,
  name text not null,
  version text not null default '0.1.0',
  description text not null default '',
  author text not null default 'anonymous',
  perms jsonb not null default '{}'::jsonb,
  requires jsonb not null default '[]'::jsonb,
  ui text not null default '',
  web text not null default '',
  py text not null,
  hash text not null,
  status text not null default 'pending' check (status in ('pending','rejected')),
  reason text not null default '',
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create table if not exists public.nexus_published_connectors (
  id text primary key,
  name text not null,
  version text not null,
  description text not null default '',
  author text not null default 'anonymous',
  perms jsonb not null default '{}'::jsonb,
  requires jsonb not null default '[]'::jsonb,
  ui text not null default '',
  web text not null default '',
  py text not null,
  hash text not null,
  published_at timestamptz not null default now(),
  reviewer text not null default ''
);

create index if not exists nexus_pending_status_submitted_idx
  on public.nexus_pending_connectors (status, submitted_at);
create index if not exists nexus_published_published_idx
  on public.nexus_published_connectors (published_at desc);

alter table public.nexus_pending_connectors enable row level security;
alter table public.nexus_published_connectors enable row level security;

revoke all on public.nexus_pending_connectors from public, anon, authenticated;
revoke all on public.nexus_published_connectors from public, anon, authenticated;
grant select on public.nexus_published_connectors to anon, authenticated;

drop policy if exists nexus_published_read on public.nexus_published_connectors;
create policy nexus_published_read
  on public.nexus_published_connectors
  for select to anon, authenticated
  using (true);

-- Founder verification helper. It reuses the existing repository founder-key verifier.
create or replace function private.nexus_is_founder(p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.repo_is_founder(p_key), false);
$$;

create or replace function private.nexus_submit_connector(p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text;
  v_py text;
begin
  if jsonb_typeof(p_data) <> 'object' then
    raise exception 'invalid payload';
  end if;

  v_id := p_data->>'id';
  v_py := coalesce(p_data->>'py','');

  if v_id is null or v_id !~ '^[A-Za-z0-9_-]{1,64}$' then
    raise exception 'invalid id';
  end if;
  if coalesce(p_data->>'name','') = '' or length(p_data->>'name') > 80 then
    raise exception 'invalid name';
  end if;
  if length(v_py) = 0 or length(v_py) > 60000 or position('@connector.tool' in v_py) = 0 then
    raise exception 'invalid python code';
  end if;
  if length(coalesce(p_data->>'ui','')) > 60000 or length(coalesce(p_data->>'web','')) > 60000 then
    raise exception 'code too large';
  end if;
  if jsonb_typeof(coalesce(p_data->'perms','{}'::jsonb)) <> 'object' then
    raise exception 'invalid permissions';
  end if;
  if jsonb_typeof(coalesce(p_data->'requires','[]'::jsonb)) <> 'array' then
    raise exception 'invalid requirements';
  end if;
  if coalesce(p_data->>'hash','') !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'invalid checksum';
  end if;
  if exists (select 1 from public.nexus_published_connectors where id = v_id) then
    raise exception 'connector is already published';
  end if;
  if not exists (select 1 from public.nexus_pending_connectors where id = v_id and status = 'rejected')
     and (select count(*) from public.nexus_pending_connectors where status = 'pending') >= 200 then
    raise exception 'the review queue is full, try later';
  end if;

  insert into public.nexus_pending_connectors as t
    (id,name,version,description,author,perms,requires,ui,web,py,hash,status,reason,submitted_at,reviewed_at)
  values
    (v_id,left(p_data->>'name',80),left(coalesce(p_data->>'version','0.1.0'),20),
     left(coalesce(p_data->>'description',''),400),left(coalesce(p_data->>'author','anonymous'),60),
     coalesce(p_data->'perms','{}'::jsonb),coalesce(p_data->'requires','[]'::jsonb),
     coalesce(p_data->>'ui',''),coalesce(p_data->>'web',''),v_py,p_data->>'hash','pending','',now(),null)
  on conflict (id) do update set
    name=excluded.name,version=excluded.version,description=excluded.description,author=excluded.author,
    perms=excluded.perms,requires=excluded.requires,ui=excluded.ui,web=excluded.web,py=excluded.py,
    hash=excluded.hash,status='pending',reason='',submitted_at=now(),reviewed_at=null;

  return jsonb_build_object('ok',true,'id',v_id);
end;
$$;

create or replace function private.nexus_submission_status(p_ids text[])
returns table(id text,status text,reason text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id,p.status,p.reason
  from public.nexus_pending_connectors p
  where p.id = any(p_ids)
  union all
  select b.id,'published',''
  from public.nexus_published_connectors b
  where b.id = any(p_ids)
    and not exists (select 1 from public.nexus_pending_connectors p where p.id=b.id);
$$;

create or replace function private.nexus_list_pending(p_key text)
returns setof public.nexus_pending_connectors
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.nexus_is_founder(p_key) then raise exception 'forbidden'; end if;
  return query
    select * from public.nexus_pending_connectors
    where status='pending'
    order by submitted_at;
end;
$$;

create or replace function private.nexus_approve_connector(p_id text,p_key text,p_reviewer text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare r public.nexus_pending_connectors;
begin
  if not private.nexus_is_founder(p_key) then raise exception 'forbidden'; end if;
  select * into r from public.nexus_pending_connectors where id=p_id and status='pending';
  if not found then raise exception 'not found'; end if;

  insert into public.nexus_published_connectors as b
    (id,name,version,description,author,perms,requires,ui,web,py,hash,published_at,reviewer)
  values
    (r.id,r.name,r.version,r.description,r.author,r.perms,r.requires,r.ui,r.web,r.py,r.hash,now(),left(coalesce(p_reviewer,''),60))
  on conflict (id) do update set
    name=excluded.name,version=excluded.version,description=excluded.description,author=excluded.author,
    perms=excluded.perms,requires=excluded.requires,ui=excluded.ui,web=excluded.web,py=excluded.py,
    hash=excluded.hash,published_at=now(),reviewer=excluded.reviewer;

  delete from public.nexus_pending_connectors where id=p_id;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function private.nexus_reject_connector(p_id text,p_key text,p_reason text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.nexus_is_founder(p_key) then raise exception 'forbidden'; end if;
  update public.nexus_pending_connectors
    set status='rejected',reason=left(coalesce(p_reason,''),400),reviewed_at=now()
    where id=p_id and status='pending';
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function private.nexus_delete_connector(p_table text,p_id text,p_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.nexus_is_founder(p_key) then raise exception 'forbidden'; end if;
  if p_table='published' then
    delete from public.nexus_published_connectors where id=p_id;
  elsif p_table='pending' then
    delete from public.nexus_pending_connectors where id=p_id;
  else
    raise exception 'invalid table';
  end if;
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('ok',true);
end;
$$;

-- Public RPC wrappers are SECURITY INVOKER; privileged work stays in private schema.
create or replace function public.nexus_submit_connector(p_data jsonb)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.nexus_submit_connector(p_data); $$;

create or replace function public.nexus_submission_status(p_ids text[])
returns table(id text,status text,reason text)
language sql stable security invoker set search_path = ''
as $$ select * from private.nexus_submission_status(p_ids); $$;

create or replace function public.nexus_list_pending(p_key text)
returns setof public.nexus_pending_connectors
language sql security invoker set search_path = ''
as $$ select * from private.nexus_list_pending(p_key); $$;

create or replace function public.nexus_approve_connector(p_id text,p_key text,p_reviewer text default '')
returns jsonb language sql security invoker set search_path = ''
as $$ select private.nexus_approve_connector(p_id,p_key,p_reviewer); $$;

create or replace function public.nexus_reject_connector(p_id text,p_key text,p_reason text default '')
returns jsonb language sql security invoker set search_path = ''
as $$ select private.nexus_reject_connector(p_id,p_key,p_reason); $$;

create or replace function public.nexus_delete_connector(p_table text,p_id text,p_key text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.nexus_delete_connector(p_table,p_id,p_key); $$;

-- No direct access to the internal schema/tables. RPC wrappers are the only API surface.
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.nexus_submit_connector(jsonb) to anon, authenticated;
grant execute on function private.nexus_submission_status(text[]) to anon, authenticated;
grant execute on function private.nexus_list_pending(text) to anon, authenticated;
grant execute on function private.nexus_approve_connector(text,text,text) to anon, authenticated;
grant execute on function private.nexus_reject_connector(text,text,text) to anon, authenticated;
grant execute on function private.nexus_delete_connector(text,text,text) to anon, authenticated;

revoke all on function public.nexus_submit_connector(jsonb) from public, anon, authenticated;
revoke all on function public.nexus_submission_status(text[]) from public, anon, authenticated;
revoke all on function public.nexus_list_pending(text) from public, anon, authenticated;
revoke all on function public.nexus_approve_connector(text,text,text) from public, anon, authenticated;
revoke all on function public.nexus_reject_connector(text,text,text) from public, anon, authenticated;
revoke all on function public.nexus_delete_connector(text,text,text) from public, anon, authenticated;
grant execute on function public.nexus_submit_connector(jsonb) to anon, authenticated;
grant execute on function public.nexus_submission_status(text[]) to anon, authenticated;
grant execute on function public.nexus_list_pending(text) to anon, authenticated;
grant execute on function public.nexus_approve_connector(text,text,text) to anon, authenticated;
grant execute on function public.nexus_reject_connector(text,text,text) to anon, authenticated;
grant execute on function public.nexus_delete_connector(text,text,text) to anon, authenticated;

grant usage on schema public to anon, authenticated;
notify pgrst, 'reload schema';


-- 20261119200318_nexus_user_accounts_for_1000_users

create table if not exists public.nexus_user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  locale text not null default 'es' check (locale in ('es','en','fr','pt','de','other')),
  role text not null default 'user' check (role in ('user','admin')),
  account_status text not null default 'active' check (account_status in ('active','suspended')),
  preferences jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.nexus_user_api_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  service_kind text not null check (service_kind in ('ai','cpu','qpu','storage','external')),
  provider text not null,
  endpoint_url text not null,
  model text not null default '',
  auth_type text not null default 'none' check (auth_type in ('none','bearer','api_key','basic','oauth')),
  secret_ref text,
  display_name text not null default '',
  enabled boolean not null default true,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint nexus_api_endpoint_https check (endpoint_url ~ '^https://')
);

create table if not exists public.nexus_user_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  url text not null,
  link_type text not null default 'resource' check (link_type in ('resource','documentation','api','project','other')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint nexus_user_link_https check (url ~ '^https://')
);

create index if not exists nexus_api_user_kind_idx on public.nexus_user_api_connections(user_id, service_kind);
create index if not exists nexus_links_user_idx on public.nexus_user_links(user_id);
create index if not exists nexus_profiles_status_idx on public.nexus_user_profiles(account_status);

alter table public.nexus_user_profiles enable row level security;
alter table public.nexus_user_api_connections enable row level security;
alter table public.nexus_user_links enable row level security;

drop policy if exists "Users read own Nexus profile" on public.nexus_user_profiles;
create policy "Users read own Nexus profile" on public.nexus_user_profiles
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users update own Nexus profile" on public.nexus_user_profiles;
create policy "Users update own Nexus profile" on public.nexus_user_profiles
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users read own API connections" on public.nexus_user_api_connections;
create policy "Users read own API connections" on public.nexus_user_api_connections
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users create own API connections" on public.nexus_user_api_connections;
create policy "Users create own API connections" on public.nexus_user_api_connections
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own API connections" on public.nexus_user_api_connections;
create policy "Users update own API connections" on public.nexus_user_api_connections
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own API connections" on public.nexus_user_api_connections;
create policy "Users delete own API connections" on public.nexus_user_api_connections
  for delete to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users read own links" on public.nexus_user_links;
create policy "Users read own links" on public.nexus_user_links
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users create own links" on public.nexus_user_links;
create policy "Users create own links" on public.nexus_user_links
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own links" on public.nexus_user_links;
create policy "Users update own links" on public.nexus_user_links
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own links" on public.nexus_user_links;
create policy "Users delete own links" on public.nexus_user_links
  for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on public.nexus_user_profiles from anon;
revoke all on public.nexus_user_api_connections from anon;
revoke all on public.nexus_user_links from anon;
grant select on public.nexus_user_profiles to authenticated;
grant update (display_name, locale, preferences, updated_at) on public.nexus_user_profiles to authenticated;
grant select, insert, delete on public.nexus_user_api_connections to authenticated;
grant update (service_kind, provider, endpoint_url, model, auth_type, display_name, enabled, config, updated_at) on public.nexus_user_api_connections to authenticated;
grant select, insert, update, delete on public.nexus_user_links to authenticated;

create or replace function public.nexus_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.nexus_user_profiles (user_id, display_name, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'locale', 'es')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.nexus_handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_nexus_profile on auth.users;
create trigger on_auth_user_created_nexus_profile
  after insert on auth.users
  for each row execute function public.nexus_handle_new_user();

insert into public.nexus_user_profiles (user_id, display_name)
select id, coalesce(raw_user_meta_data ->> 'name', raw_user_meta_data ->> 'full_name', '')
from auth.users
on conflict (user_id) do nothing;


-- 20261119200334_nexus_user_rls_hardening

drop policy if exists "Users read own Nexus profile" on public.nexus_user_profiles;
create policy "Users read own Nexus profile" on public.nexus_user_profiles
  for select to authenticated
  using ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "Users update own Nexus profile" on public.nexus_user_profiles;
create policy "Users update own Nexus profile" on public.nexus_user_profiles
  for update to authenticated
  using ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false)
  with check ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "Users read own API connections" on public.nexus_user_api_connections;
create policy "Users read own API connections" on public.nexus_user_api_connections
  for select to authenticated
  using ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "Users create own API connections" on public.nexus_user_api_connections;
create policy "Users create own API connections" on public.nexus_user_api_connections
  for insert to authenticated
  with check ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "Users update own API connections" on public.nexus_user_api_connections;
create policy "Users update own API connections" on public.nexus_user_api_connections
  for update to authenticated
  using ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false)
  with check ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "Users delete own API connections" on public.nexus_user_api_connections;
create policy "Users delete own API connections" on public.nexus_user_api_connections
  for delete to authenticated
  using ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "Users read own links" on public.nexus_user_links;
create policy "Users read own links" on public.nexus_user_links
  for select to authenticated
  using ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "Users create own links" on public.nexus_user_links;
create policy "Users create own links" on public.nexus_user_links
  for insert to authenticated
  with check ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "Users update own links" on public.nexus_user_links;
create policy "Users update own links" on public.nexus_user_links
  for update to authenticated
  using ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false)
  with check ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

drop policy if exists "Users delete own links" on public.nexus_user_links;
create policy "Users delete own links" on public.nexus_user_links
  for delete to authenticated
  using ((select auth.uid()) = user_id and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);

revoke all on public.nexus_user_profiles from anon, authenticated;
revoke all on public.nexus_user_api_connections from anon, authenticated;
revoke all on public.nexus_user_links from anon, authenticated;

grant select on public.nexus_user_profiles to authenticated;
grant update (display_name, locale, preferences, updated_at) on public.nexus_user_profiles to authenticated;

grant select, delete on public.nexus_user_api_connections to authenticated;
grant insert (user_id, service_kind, provider, endpoint_url, model, auth_type, display_name, enabled, config) on public.nexus_user_api_connections to authenticated;
grant update (service_kind, provider, endpoint_url, model, auth_type, display_name, enabled, config, updated_at) on public.nexus_user_api_connections to authenticated;

grant select, delete on public.nexus_user_links to authenticated;
grant insert (user_id, title, url, link_type) on public.nexus_user_links to authenticated;
grant update (title, url, link_type, updated_at) on public.nexus_user_links to authenticated;

