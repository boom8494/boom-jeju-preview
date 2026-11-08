-- Run once in the BOOM JEJU Supabase SQL Editor.
-- Creates unread notifications for approved superadmins when inquiries arrive
-- or a new post becomes public. No customer contact details are sent in push.

create table if not exists public.boom_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('inquiry', 'post')),
  title text not null,
  body text not null,
  link text not null default '/',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists boom_notifications_user_unread_idx
  on public.boom_notifications(user_id, created_at desc) where read_at is null;

alter table public.boom_notifications enable row level security;
revoke all on public.boom_notifications from anon, authenticated;
grant select on public.boom_notifications to authenticated;
grant update(read_at) on public.boom_notifications to authenticated;

drop policy if exists boom_notifications_read_own on public.boom_notifications;
create policy boom_notifications_read_own on public.boom_notifications
  for select to authenticated
  using (user_id = (select auth.uid()) and public.is_boom_admin());

drop policy if exists boom_notifications_mark_own on public.boom_notifications;
create policy boom_notifications_mark_own on public.boom_notifications
  for update to authenticated
  using (user_id = (select auth.uid()) and public.is_boom_admin())
  with check (user_id = (select auth.uid()) and public.is_boom_admin());

create table if not exists public.boom_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists boom_push_subscriptions_user_idx
  on public.boom_push_subscriptions(user_id);

alter table public.boom_push_subscriptions enable row level security;
revoke all on public.boom_push_subscriptions from anon, authenticated;
grant select, insert, update, delete on public.boom_push_subscriptions to authenticated;

drop policy if exists boom_push_subscriptions_manage_own on public.boom_push_subscriptions;
create policy boom_push_subscriptions_manage_own on public.boom_push_subscriptions
  for all to authenticated
  using (user_id = (select auth.uid()) and public.is_boom_admin())
  with check (user_id = (select auth.uid()) and public.is_boom_admin());

create or replace function public.boom_notify_superadmins(
  p_kind text,
  p_title text,
  p_body text,
  p_link text
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.boom_notifications(user_id, kind, title, body, link)
  select sp.user_id, p_kind, p_title, p_body, p_link
  from public.staff_profiles sp
  where sp.approved = true and sp.is_superadmin = true;
end;
$$;

revoke all on function public.boom_notify_superadmins(text, text, text, text) from public, anon, authenticated;

create or replace function public.boom_notify_new_inquiry()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_category text;
begin
  v_category := case new.category
    when 'construction' then '붐건축'
    when 'real_estate' then '붐부동산'
    when 'drone_film' then '붐드론필름'
    else 'BOOM JEJU'
  end;
  perform public.boom_notify_superadmins(
    'inquiry',
    '새 온라인 문의',
    v_category || ' 상담 문의가 도착했습니다.',
    '/#boomInquiryAdmin'
  );
  return new;
end;
$$;

drop trigger if exists boom_notify_new_inquiry on public.boom_inquiries;
create trigger boom_notify_new_inquiry
  after insert on public.boom_inquiries
  for each row execute function public.boom_notify_new_inquiry();

create or replace function public.boom_notify_published_post()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_category text;
begin
  if new.status <> 'published' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'published' then return new; end if;

  v_category := case new.category
    when 'construction' then '붐건축'
    when 'real_estate' then '붐부동산'
    when 'drone_film' then '붐드론필름'
    else 'BOOM JEJU'
  end;
  perform public.boom_notify_superadmins(
    'post',
    '새 게시물 등록',
    v_category || '에 새 게시물이 공개됐습니다.',
    '/#liveManager'
  );
  return new;
end;
$$;

drop trigger if exists boom_notify_inserted_published_post on public.posts;
create trigger boom_notify_inserted_published_post
  after insert on public.posts
  for each row execute function public.boom_notify_published_post();

drop trigger if exists boom_notify_published_post on public.posts;
create trigger boom_notify_published_post
  after update of status on public.posts
  for each row execute function public.boom_notify_published_post();

revoke all on function public.boom_notify_new_inquiry() from public, anon, authenticated;
revoke all on function public.boom_notify_published_post() from public, anon, authenticated;

-- Enable Realtime for the signed-in admin notification list, if not already present.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'boom_notifications'
     ) then
    alter publication supabase_realtime add table public.boom_notifications;
  end if;
end;
$$;
