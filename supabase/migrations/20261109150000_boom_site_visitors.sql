-- BOOM JEJU unique visitor counts
-- One row per browser UUID per Korea calendar day.
create table if not exists public.boom_site_visits (
  visitor_id uuid not null,
  visit_date date not null,
  first_seen_at timestamptz not null default now(),
  primary key (visitor_id, visit_date)
);

alter table public.boom_site_visits enable row level security;
revoke all on table public.boom_site_visits from anon, authenticated;

create or replace function public.boom_track_visitor(p_visitor_id uuid)
returns table(today_visitors bigint, total_visitors bigint)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  korea_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  insert into public.boom_site_visits(visitor_id, visit_date)
  values (p_visitor_id, korea_today)
  on conflict (visitor_id, visit_date) do nothing;

  return query
  select
    count(*) filter (where v.visit_date = korea_today),
    count(distinct v.visitor_id)
  from public.boom_site_visits as v;
end;
$$;

revoke all on function public.boom_track_visitor(uuid) from public;
grant execute on function public.boom_track_visitor(uuid) to anon, authenticated;
