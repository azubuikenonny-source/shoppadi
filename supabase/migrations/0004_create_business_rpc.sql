-- Creating a shop is a chicken-and-egg problem under RLS: businesses_select
-- requires app.is_member(id), but membership cannot exist until the business
-- row does. The client's INSERT ... RETURNING id therefore failed — Postgres
-- applies SELECT policies to returned rows, and the caller was not yet a
-- member of the row it had just created.
--
-- Doing both writes in one SECURITY DEFINER function fixes it properly: the
-- membership is created in the same transaction as the business, so the pair
-- is never observable in a half-built state, and no policy has to be loosened
-- to let a stranger read a shop they do not belong to.

create or replace function public.create_business_for_me(shop_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_id uuid;
  new_id      uuid;
begin
  -- SECURITY DEFINER bypasses RLS, so this check is what keeps the function
  -- honest. Without it, anyone with the anon key could create shops.
  if auth.uid() is null then
    raise exception 'not authenticated'
      using errcode = '42501';
  end if;

  -- Already belongs somewhere: hand back that shop rather than making another.
  -- Signing in on a second device must not silently fork the business.
  select bm.business_id into existing_id
  from business_members bm
  where bm.user_id = auth.uid()
    and bm.status = 'active'
  limit 1;

  if existing_id is not null then
    return existing_id;
  end if;

  insert into businesses (name)
  values (coalesce(nullif(btrim(shop_name), ''), 'My shop'))
  returning id into new_id;

  insert into business_members (business_id, user_id, role, status)
  values (new_id, auth.uid(), 'owner', 'active');

  insert into profiles (user_id, full_name, phone)
  values (
    auth.uid(),
    coalesce(
      (select raw_user_meta_data ->> 'full_name'
         from auth.users where id = auth.uid()),
      ''),
    (select phone from auth.users where id = auth.uid())
  )
  on conflict (user_id) do nothing;

  return new_id;
end;
$$;

revoke all on function public.create_business_for_me(text) from public, anon;
grant execute on function public.create_business_for_me(text) to authenticated;
