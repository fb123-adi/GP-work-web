-- SIDADI Workspace — database setup (v2). Safe to run again: it updates an existing install.
-- Supabase → SQL Editor → New query → paste → Run.

create table if not exists public.members (
  user_id uuid primary key references auth.users on delete cascade,
  emp_id text unique not null,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.records (
  collection text not null,
  id text not null,
  emp_id text,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (collection, id)
);
alter table public.records drop constraint if exists records_collection_check;
alter table public.records add constraint records_collection_check check (collection in (
  'employees','submissions','tasks','logins','notifs','teams',
  'customers','orders','inventory','purchases','invoices',
  'leave','documents','payslips','consents','requests','settings'));
create index if not exists records_emp_idx on public.records (emp_id);
alter table public.records replica identity full;

-- ── helpers ──────────────────────────────────────────────────
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from members where user_id = auth.uid()), false) $$;

create or replace function public.my_emp_id() returns text
language sql stable security definer set search_path = public as $$
  select emp_id from members where user_id = auth.uid() $$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select r.data->>'role' from records r where r.collection = 'employees' and r.id = my_emp_id()), 'Staff') $$;

-- which business areas a role can work in
create or replace function public.role_can(p_collection text, p_emp text) returns boolean
language sql stable security definer set search_path = public as $$
  select case my_role()
    when 'Manager'  then p_collection in ('customers','orders','inventory','purchases') or (p_collection = 'documents' and p_emp is null)
    when 'Accounts' then p_collection in ('customers','invoices','purchases','inventory') or (p_collection = 'documents' and p_emp is null)
    else false end $$;

create or replace function public.whoami() returns table(emp_id text, is_admin boolean)
language sql stable security definer set search_path = public as $$
  select m.emp_id, m.is_admin from members m where m.user_id = auth.uid() $$;

-- first sign-in: link to a profile the admin pre-created with the same email, or create a new joiner
create or replace function public.join_workspace(p_name text) returns table(emp_id text, is_new boolean)
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(coalesce(auth.jwt()->>'email','')); v_emp text; v_n int;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select m.emp_id into v_emp from members m where m.user_id = auth.uid();
  if v_emp is not null then return query select v_emp, false; return; end if;
  if v_email <> '' then
    select r.id into v_emp from records r
     where r.collection = 'employees' and lower(r.data->>'email') = v_email
       and not exists (select 1 from members m where m.emp_id = r.id) limit 1;
    if v_emp is not null then
      insert into members(user_id, emp_id) values (auth.uid(), v_emp);
      return query select v_emp, false; return;
    end if;
  end if;
  select coalesce(max((regexp_match(r.data->>'userId','GPS-(\d+)'))[1]::int), 0) + 1 into v_n
    from records r where r.collection = 'employees';
  v_emp := 'u' || replace(auth.uid()::text, '-', '');
  insert into members(user_id, emp_id) values (auth.uid(), v_emp);
  insert into records(collection, id, emp_id, data) values ('employees', v_emp, v_emp, jsonb_build_object(
    'id', v_emp, 'userId', 'GPS-' || lpad(v_n::text, 3, '0'),
    'name', left(coalesce(nullif(trim(p_name), ''), split_part(v_email, '@', 1)), 80),
    'title', 'New joiner', 'teamId', 't0', 'role', 'Staff', 'active', true, 'color', '#6B6F60',
    'email', v_email, 'joinedAt', (extract(epoch from now()) * 1000)::bigint));
  return query select v_emp, true;
end $$;

create or replace function public.log_failed_signin(p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare v_id text := 'f' || (extract(epoch from clock_timestamp()) * 1000)::bigint || floor(random() * 1000)::int;
begin
  insert into records(collection, id, emp_id, data) values ('notifs', v_id, null, jsonb_build_object(
    'id', v_id, 'type', 'failed',
    'text', 'Failed admin sign-in attempt' || case when coalesce(p_email,'') <> '' then ' with ' || left(p_email, 80) else '' end,
    'time', to_char(now() at time zone 'Asia/Kolkata', 'FMHH12:MI AM'),
    'ts', (extract(epoch from now()) * 1000)::bigint, 'read', false));
end $$;

-- erase a person's data on request (admin only). Payslips are kept as the law requires; the request itself is kept as an audit record.
create or replace function public.delete_employee_data(p_emp text) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  delete from records where emp_id = p_emp and collection not in ('payslips','requests');
  delete from records where collection = 'employees' and id = p_emp;
  delete from auth.users where id in (select user_id from members where emp_id = p_emp);
  delete from members where emp_id = p_emp;
end $$;

grant execute on function public.whoami() to authenticated;
grant execute on function public.join_workspace(text) to authenticated;
grant execute on function public.delete_employee_data(text) to authenticated;
grant execute on function public.log_failed_signin(text) to anon, authenticated;

-- ── server-side rules employees cannot bypass ────────────────
create or replace function public.guard_records() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if is_admin() then return new; end if;
  if tg_op = 'UPDATE' and new.emp_id is distinct from old.emp_id then raise exception 'cannot reassign records'; end if;
  if new.collection = 'tasks' and tg_op = 'UPDATE' then
    if (new.data - 'status' - 'startedAt' - 'doneAt') <> (old.data - 'status' - 'startedAt' - 'doneAt') then
      raise exception 'you can only change the status of assigned work'; end if;
    if new.data->>'status' not in ('todo','in_progress','done') then raise exception 'invalid status'; end if;
  end if;
  if new.collection = 'submissions' then
    if tg_op = 'UPDATE' and old.data->>'status' = 'approved' then raise exception 'approved updates are locked'; end if;
    if coalesce(new.data->>'status','submitted') not in ('submitted') then raise exception 'only the admin can approve'; end if;
  end if;
  if new.collection = 'leave' then
    if tg_op = 'UPDATE' and old.data->>'status' <> 'Pending' then raise exception 'decided leave cannot be changed'; end if;
    if new.data->>'status' not in ('Pending','Cancelled') then raise exception 'only the admin can approve leave'; end if;
  end if;
  if new.collection = 'requests' and tg_op = 'UPDATE' then raise exception 'requests are handled by the admin'; end if;
  return new;
end $$;
drop trigger if exists records_guard on public.records;
create trigger records_guard before insert or update on public.records for each row execute function public.guard_records();

-- ── row-level security ───────────────────────────────────────
alter table public.members enable row level security;
alter table public.records enable row level security;

drop policy if exists members_read on public.members;
create policy members_read on public.members for select using (user_id = auth.uid() or public.is_admin());

drop policy if exists rec_select on public.records;
drop policy if exists rec_insert on public.records;
drop policy if exists rec_update on public.records;
drop policy if exists rec_delete on public.records;

create policy rec_select on public.records for select using (
  public.is_admin() or emp_id = public.my_emp_id()
  or (collection = 'teams' and auth.uid() is not null)
  or public.role_can(collection, emp_id));

create policy rec_insert on public.records for insert with check (
  public.is_admin()
  or (emp_id = public.my_emp_id() and collection in ('submissions','logins','notifs','leave','documents','consents','requests'))
  or public.role_can(collection, emp_id)
  or (collection = 'notifs' and auth.uid() is not null and emp_id = public.my_emp_id()));

create policy rec_update on public.records for update
  using (public.is_admin() or (emp_id = public.my_emp_id() and collection in ('submissions','tasks','logins','notifs','leave','documents')) or public.role_can(collection, emp_id))
  with check (public.is_admin() or (emp_id = public.my_emp_id() and collection in ('submissions','tasks','logins','notifs','leave','documents')) or public.role_can(collection, emp_id));

create policy rec_delete on public.records for delete using (
  public.is_admin() or public.role_can(collection, emp_id)
  or (emp_id = public.my_emp_id() and collection = 'documents'));

-- ── file storage for documents (private, 10 MB per file) ─────
insert into storage.buckets (id, name, public, file_size_limit)
values ('documents', 'documents', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

drop policy if exists docs_read on storage.objects;
drop policy if exists docs_write on storage.objects;
drop policy if exists docs_delete on storage.objects;
create policy docs_read on storage.objects for select using (bucket_id = 'documents' and (
  public.is_admin() or split_part(name, '/', 1) = public.my_emp_id()
  or (split_part(name, '/', 1) = 'company' and public.my_role() in ('Manager','Accounts'))));
create policy docs_write on storage.objects for insert with check (bucket_id = 'documents' and (
  public.is_admin() or split_part(name, '/', 1) = public.my_emp_id()
  or (split_part(name, '/', 1) = 'company' and public.my_role() in ('Manager','Accounts'))));
create policy docs_delete on storage.objects for delete using (bucket_id = 'documents' and (
  public.is_admin() or split_part(name, '/', 1) = public.my_emp_id()
  or (split_part(name, '/', 1) = 'company' and public.my_role() in ('Manager','Accounts'))));

-- ── live updates ─────────────────────────────────────────────
do $$ begin
  alter publication supabase_realtime add table public.records;
exception when duplicate_object then null; end $$;

-- ─────────────────────────────────────────────────────────────
-- MAKE YOUR ADMIN (after creating the admin user — SETUP.md step 3)
-- insert into public.members (user_id, emp_id, is_admin)
--   select id, 'ADMIN', true from auth.users where email = 'admin@greenprintech.com'
--   on conflict (user_id) do update set is_admin = true;
