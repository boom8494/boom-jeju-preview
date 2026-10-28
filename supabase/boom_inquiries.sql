-- Run once in Supabase SQL Editor. Public may submit inquiries; only approved superadmins may read/reply.
create table if not exists public.boom_inquiries (
 id uuid primary key default gen_random_uuid(),
 category text not null check(category in ('construction','real_estate','drone_film')),
 customer_name text not null check(char_length(customer_name) between 1 and 60),
 phone text not null check(char_length(phone) between 1 and 30),
 subject text not null check(char_length(subject) between 1 and 150),
 message text not null check(char_length(message) between 1 and 3000),
 reply text,
 replied_at timestamptz,
 created_at timestamptz not null default now()
);
alter table public.boom_inquiries enable row level security;
revoke all on public.boom_inquiries from anon, authenticated;
grant insert(category,customer_name,phone,subject,message) on public.boom_inquiries to anon, authenticated;
grant select on public.boom_inquiries to authenticated;
grant update(reply,replied_at) on public.boom_inquiries to authenticated;
drop policy if exists boom_inquiries_public_insert on public.boom_inquiries;
create policy boom_inquiries_public_insert on public.boom_inquiries for insert to anon,authenticated with check (reply is null and replied_at is null);
drop policy if exists boom_inquiries_staff_read on public.boom_inquiries;
create policy boom_inquiries_staff_read on public.boom_inquiries for select to authenticated using (
 exists (select 1 from public.staff_profiles sp where sp.user_id=auth.uid() and sp.approved=true and sp.is_superadmin=true)
);
drop policy if exists boom_inquiries_staff_reply on public.boom_inquiries;
create policy boom_inquiries_staff_reply on public.boom_inquiries for update to authenticated using (
 exists (select 1 from public.staff_profiles sp where sp.user_id=auth.uid() and sp.approved=true and sp.is_superadmin=true)
) with check (
 exists (select 1 from public.staff_profiles sp where sp.user_id=auth.uid() and sp.approved=true and sp.is_superadmin=true)
);
create index if not exists boom_inquiries_created_at_idx on public.boom_inquiries(created_at desc);
-- Note: Public inquiry submission requires abuse controls (rate limits/CAPTCHA) for production.
