-- BOOM JEJU initial secure schema (run once in Supabase SQL Editor)
create extension if not exists pgcrypto;

create table if not exists public.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  is_superadmin boolean not null default false,
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.staff_permissions (
  user_id uuid not null references public.staff_profiles(user_id) on delete cascade,
  category text not null check (category in ('construction','real_estate','drone_film')),
  primary key (user_id,category)
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('construction','real_estate','drone_film')),
  title text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  location text not null default '',
  price_label text not null default '',
  status text not null default 'draft' check (status in ('draft','pending','published','archived')),
  media jsonb not null default '[]'::jsonb check (jsonb_typeof(media)='array' and jsonb_array_length(media)<=30),
  author_id uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.home_slides (
  id uuid primary key default gen_random_uuid(),
  sort_order integer not null default 0,
  title text not null default '',
  subtitle text not null default '',
  media_type text not null default 'image' check (media_type in ('image','youtube')),
  media_url text not null default '',
  link_url text not null default '',
  is_visible boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.is_boom_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
 select exists(select 1 from public.staff_profiles
 where user_id=(select auth.uid()) and approved=true and is_superadmin=true)
$$;

create or replace function public.can_boom_edit(cat text)
returns boolean language sql stable security definer set search_path = ''
as $$
 select public.is_boom_admin() or exists(
 select 1 from public.staff_profiles p
 join public.staff_permissions sp on sp.user_id=p.user_id
 where p.user_id=(select auth.uid()) and p.approved=true and sp.category=cat)
$$;

alter table public.staff_profiles enable row level security;
alter table public.staff_permissions enable row level security;
alter table public.posts enable row level security;
alter table public.home_slides enable row level security;

drop policy if exists "profile read self or admin" on public.staff_profiles;
create policy "profile read self or admin" on public.staff_profiles
for select to authenticated using (user_id=(select auth.uid()) or public.is_boom_admin());

drop policy if exists "admin manages profiles" on public.staff_profiles;
create policy "admin manages profiles" on public.staff_profiles
for all to authenticated using (public.is_boom_admin()) with check (public.is_boom_admin());

drop policy if exists "permissions read self or admin" on public.staff_permissions;
create policy "permissions read self or admin" on public.staff_permissions
for select to authenticated using (user_id=(select auth.uid()) or public.is_boom_admin());

drop policy if exists "admin manages permissions" on public.staff_permissions;
create policy "admin manages permissions" on public.staff_permissions
for all to authenticated using (public.is_boom_admin()) with check (public.is_boom_admin());

drop policy if exists "public reads published posts" on public.posts;
create policy "public reads published posts" on public.posts
for select to anon,authenticated using (
 status='published' or (select auth.uid())=author_id or public.is_boom_admin()
);

drop policy if exists "approved staff create own posts" on public.posts;
create policy "approved staff create own posts" on public.posts
for insert to authenticated with check (
 author_id=(select auth.uid()) and public.can_boom_edit(category)
 and (status in ('draft','pending') or public.is_boom_admin())
);

drop policy if exists "staff update own drafts and pending" on public.posts;
create policy "staff update own drafts and pending" on public.posts
for update to authenticated
using (public.is_boom_admin() or
 (author_id=(select auth.uid()) and public.can_boom_edit(category) and status in ('draft','pending')))
with check (public.is_boom_admin() or
 (author_id=(select auth.uid()) and public.can_boom_edit(category) and status in ('draft','pending')));

drop policy if exists "admin delete posts" on public.posts;
create policy "admin delete posts" on public.posts
for delete to authenticated using (public.is_boom_admin());

drop policy if exists "public reads visible slides" on public.home_slides;
create policy "public reads visible slides" on public.home_slides
for select to anon,authenticated using (is_visible or public.is_boom_admin());

drop policy if exists "admin manages slides" on public.home_slides;
create policy "admin manages slides" on public.home_slides
for all to authenticated using (public.is_boom_admin()) with check (public.is_boom_admin());

-- After creating the FIRST administrator via Supabase Authentication > Users,
-- run the following separately, replacing the example email with that user's email:
-- insert into public.staff_profiles(user_id,display_name,is_superadmin,approved)
-- select id,'BOOM 대표',true,true from auth.users where email='YOUR_EMAIL_HERE'
-- on conflict(user_id) do update set is_superadmin=true,approved=true;
--
-- Do not run the example with a placeholder email. No one is granted admin by default.
