-- Supabase Postgres. Run as the database owner, never from the app.
begin;
create schema if not exists cardwise_private;
revoke all on schema cardwise_private from public, anon, authenticated;
create table cardwise_private.owner_config (
  singleton boolean primary key default true check (singleton),
  user_id uuid not null references auth.users(id)
);
-- Intentionally no owner seed. A trusted operator provisions one verified auth.users.id.
create table cardwise_private.participants (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  epoch uuid not null,
  updated_at timestamptz not null default now()
);
create table cardwise_private.impact (
  user_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  recommendation_id uuid,
  day date not null,
  kind text not null check (kind in ('recommendationAccepted','estimatedBenefitCalculated','rewardReceived')),
  category text check (category in ('base','dining','groceries','gas','travel','travelPortal','flights','hotels','transit','rideshare','streaming','entertainment','drugstores','onlineShopping','departmentStore','homeImprovement','warehouseClub')),
  product text check (product in ('chase-freedom-flex','chase-sapphire-preferred','discover-it-cash-back','amex-blue-cash-preferred','amex-gold','citi-double-cash','capital-one-savor','wells-fargo-active-cash','citi-costco-anywhere-visa')),
  purchase_cents bigint check (purchase_cents between 1 and 100000000),
  estimated_cents bigint check (estimated_cents between -100000000 and 100000000),
  incremental_cents bigint check (incremental_cents between -100000000 and 100000000),
  received_cents bigint check (received_cents between 0 and 100000000),
  calculation_version integer check (calculation_version between 1 and 100),
  primary key (user_id,id),
  check ((kind = 'estimatedBenefitCalculated' and recommendation_id is not null and purchase_cents is not null and estimated_cents is not null and calculation_version is not null and received_cents is null)
    or (kind = 'recommendationAccepted' and recommendation_id is not null and purchase_cents is null and estimated_cents is null and incremental_cents is null and received_cents is null)
    or (kind = 'rewardReceived' and recommendation_id is null and received_cents is not null and purchase_cents is null and estimated_cents is null and incremental_cents is null))
);
create unique index impact_recommendation_kind on cardwise_private.impact(user_id,recommendation_id,kind) where recommendation_id is not null;
alter table cardwise_private.owner_config enable row level security;
alter table cardwise_private.participants enable row level security;
alter table cardwise_private.impact enable row level security;
-- No table policies or grants: even the owner account uses guarded aggregate functions.
revoke all on all tables in schema cardwise_private from public, anon, authenticated;

create function public.cardwise_is_owner() returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from cardwise_private.owner_config c join auth.users u on u.id = c.user_id
    where c.singleton and u.id = auth.uid() and u.email_confirmed_at is not null);
$$;

create function public.cardwise_set_sharing(enabled boolean, epoch uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from auth.users where id = auth.uid() and email_confirmed_at is not null) then
    raise exception 'Verified authentication required' using errcode = '42501';
  end if;
  if epoch is null or enabled is null then raise exception 'Invalid consent'; end if;
  insert into cardwise_private.participants(user_id,enabled,epoch) values(auth.uid(),enabled,epoch)
  on conflict(user_id) do update set enabled = excluded.enabled, epoch = excluded.epoch, updated_at = now();
end;
$$;

create function public.cardwise_upload(epoch uuid, records jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare r jsonb; consent cardwise_private.participants;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select * into consent from cardwise_private.participants where user_id = auth.uid() for update;
  if not found or not consent.enabled or epoch is null or consent.epoch <> epoch then raise exception 'Sharing not authorized' using errcode = '42501'; end if;
  if records is null or jsonb_typeof(records) <> 'array' or jsonb_array_length(records) > 100 then raise exception 'Invalid batch'; end if;
  for r in select * from jsonb_array_elements(records) loop
    if jsonb_typeof(r) <> 'object' or exists(select 1 from jsonb_object_keys(r) k where k not in
      ('id','recommendation_id','day','kind','category','product','purchase_cents','estimated_cents','incremental_cents','received_cents','calculation_version')) then
      raise exception 'Unexpected field';
    end if;
    if (r->>'day')::date < date '2020-01-01' or (r->>'day')::date > (now() at time zone 'UTC')::date + 1 then raise exception 'Invalid day'; end if;
    insert into cardwise_private.impact values(auth.uid(),(r->>'id')::uuid,(r->>'recommendation_id')::uuid,
      (r->>'day')::date,r->>'kind',r->>'category',r->>'product',(r->>'purchase_cents')::bigint,
      (r->>'estimated_cents')::bigint,(r->>'incremental_cents')::bigint,(r->>'received_cents')::bigint,(r->>'calculation_version')::integer)
    on conflict do nothing;
  end loop;
end;
$$;

create function public.cardwise_delete_shared() returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  -- Lock the same row as upload: no in-flight upload can resurrect deleted records.
  update cardwise_private.participants set enabled = false, epoch = gen_random_uuid(), updated_at = now() where user_id = auth.uid();
  delete from cardwise_private.impact where user_id = auth.uid();
end;
$$;

create function public.cardwise_dashboard(from_day date, to_day date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not public.cardwise_is_owner() then raise exception 'Owner only' using errcode = '42501'; end if;
  if from_day is null or to_day is null or from_day > to_day or to_day - from_day > 3660 then raise exception 'Invalid date range'; end if;
  with data as (select * from cardwise_private.impact where day between from_day and to_day),
  groups as (
    select 'day' dimension, day::text label, count(*) filter(where kind='recommendationAccepted') acted,
      sum(purchase_cents) purchases, sum(estimated_cents) estimated, sum(incremental_cents) incremental, sum(received_cents) received from data group by day
    union all select 'category',coalesce(category,'Unknown'),count(*) filter(where kind='recommendationAccepted'),sum(purchase_cents),sum(estimated_cents),sum(incremental_cents),sum(received_cents) from data group by category
    union all select 'product',coalesce(product,'Unknown'),count(*) filter(where kind='recommendationAccepted'),sum(purchase_cents),sum(estimated_cents),sum(incremental_cents),sum(received_cents) from data group by product
  )
  select jsonb_build_object(
    'participating_users',(select count(*) from cardwise_private.participants where enabled),
    'reporting_users',(select count(distinct user_id) from data),
    'acted_on',(select count(*) from data where kind='recommendationAccepted'),
    'purchase_cents',(select sum(purchase_cents) from data),
    'estimated_cents',(select sum(estimated_cents) from data),
    'incremental_cents',(select sum(incremental_cents) from data),
    'received_cents',(select sum(received_cents) from data),
    'known_baselines',(select count(*) from data where incremental_cents is not null),
    'priced_recommendations',(select count(*) from data where kind='estimatedBenefitCalculated'),
    'breakdowns',coalesce((select jsonb_agg(to_jsonb(g) order by dimension,label) from groups g),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;
revoke all on function public.cardwise_is_owner(), public.cardwise_set_sharing(boolean,uuid), public.cardwise_upload(uuid,jsonb), public.cardwise_delete_shared(), public.cardwise_dashboard(date,date) from public, anon;
grant execute on function public.cardwise_is_owner(), public.cardwise_set_sharing(boolean,uuid), public.cardwise_upload(uuid,jsonb), public.cardwise_delete_shared(), public.cardwise_dashboard(date,date) to authenticated;
commit;
