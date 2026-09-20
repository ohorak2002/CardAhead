\set ON_ERROR_STOP on
begin;
create function public.test_assert(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
create function public.test_denied(command text) returns void language plpgsql as $$
begin
  begin execute command; exception when insufficient_privilege then return; end;
  raise exception 'FAIL: permitted %',command;
end $$;
create function public.test_invalid(command text) returns void language plpgsql as $$
begin
  begin execute command; exception when others then return; end;
  raise exception 'FAIL: accepted invalid input %',command;
end $$;
insert into auth.users values
 ('00000000-0000-0000-0000-000000000001',now()),
 ('00000000-0000-0000-0000-000000000002',now()),
 ('00000000-0000-0000-0000-000000000003',null);

set local role anon;
select public.test_denied('select public.cardwise_dashboard(current_date,current_date)');
select public.test_denied('select public.cardwise_is_owner()');
select public.test_denied('select * from cardwise_private.impact');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select public.test_assert(not public.cardwise_is_owner(),'no first-user admin');
select public.test_denied('select public.cardwise_dashboard(current_date,current_date)');
select public.test_denied('insert into cardwise_private.owner_config values(true,auth.uid())');
reset role;
insert into cardwise_private.owner_config values(true,'00000000-0000-0000-0000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims','{"role":"owner","email":"owner@example.com","user_metadata":{"admin":true}}',true);
select public.test_assert(not public.cardwise_is_owner(),'forged role cannot authorize');
select public.test_denied('select public.cardwise_dashboard(current_date,current_date)');
select public.test_denied('select * from cardwise_private.participants');
select public.test_denied('select * from cardwise_private.impact');
select public.test_denied('update cardwise_private.owner_config set user_id = auth.uid()');
select public.test_denied($q$select public.cardwise_upload('11111111-1111-1111-1111-111111111111','[]')$q$);
select public.cardwise_set_sharing(true,'11111111-1111-1111-1111-111111111111');
select public.cardwise_upload('11111111-1111-1111-1111-111111111111',
 '[{"id":"22222222-2222-2222-2222-222222222222","recommendation_id":"33333333-3333-3333-3333-333333333333","day":"2026-09-20","kind":"recommendationAccepted","category":"dining"}]');
-- Retry with the same ID and a distinct ID for the same recommendation both deduplicate.
select public.cardwise_upload('11111111-1111-1111-1111-111111111111',
 '[{"id":"22222222-2222-2222-2222-222222222222","recommendation_id":"33333333-3333-3333-3333-333333333333","day":"2026-09-20","kind":"recommendationAccepted","category":"dining"},{"id":"44444444-4444-4444-4444-444444444444","recommendation_id":"33333333-3333-3333-3333-333333333333","day":"2026-09-20","kind":"recommendationAccepted"}]');
select public.test_invalid($q$select public.cardwise_upload('11111111-1111-1111-1111-111111111111','[{"user_id":"fake"}]')$q$);
select public.test_invalid($q$select public.cardwise_upload('11111111-1111-1111-1111-111111111111','[{"id":"44444444-4444-4444-4444-444444444444","day":"2026-09-20","kind":"rewardReceived","received_cents":-1}]')$q$);
select public.cardwise_set_sharing(false,'55555555-5555-5555-5555-555555555555');
select public.test_denied($q$select public.cardwise_upload('11111111-1111-1111-1111-111111111111','[]')$q$);
reset role;
select public.test_assert((select count(*)=1 from cardwise_private.impact),'duplicate prevention');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select public.test_assert(public.cardwise_is_owner(),'verified configured owner');
select public.test_assert((public.cardwise_dashboard('2026-09-01','2026-09-30')->>'acted_on')::int=1,'owner aggregate');
select public.test_assert(public.cardwise_dashboard('2026-09-01','2026-09-30')->'incremental_cents'='null'::jsonb,'missing baseline stays unknown');
select public.test_denied('select * from cardwise_private.impact');
select public.cardwise_delete_shared(); -- Must not delete the other user's report.
reset role;
select public.test_assert((select count(*)=1 from cardwise_private.impact),'delete isolation');

update cardwise_private.owner_config set user_id='00000000-0000-0000-0000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
select public.test_assert(not public.cardwise_is_owner(),'unverified configured identity denied');
select public.test_denied('select public.cardwise_dashboard(current_date,current_date)');
select public.test_denied($q$select public.cardwise_set_sharing(true,'11111111-1111-1111-1111-111111111111')$q$);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select public.cardwise_delete_shared();
select public.test_denied($q$select public.cardwise_upload('11111111-1111-1111-1111-111111111111','[]')$q$);
reset role;
select public.test_assert((select count(*)=0 from cardwise_private.impact),'deletion');
rollback;
\echo 'PASS: authorization, consent, input validation, deduplication, deletion, honest aggregates'
