-- create_business_for_me checked for an existing membership and then inserted,
-- which is only safe if one call runs at a time. Signing in fires more than one
-- auth event (signedIn, then a token refresh), the client re-resolved its shop
-- lookup on each, and two calls raced: both saw no membership, both created a
-- business. A shop ended up duplicated on the very first sign-in.
--
-- A transaction-scoped advisory lock keyed on the user makes the check and the
-- insert atomic against each other. The second caller blocks until the first
-- commits, then sees the membership and returns it. The lock is released
-- automatically when the transaction ends, including on error.

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
  if auth.uid() is null then
    raise exception 'not authenticated'
      using errcode = '42501';
  end if;

  -- Serialise concurrent calls for this user. Anything else may run freely.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));

  -- Re-check now that we hold the lock: a racing call may have created the
  -- shop while this one was waiting.
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

-- Belt and braces: even if some future code path forgets the lock, a user
-- cannot end up owning two shops by accident. Partial so that a removed
-- membership does not block rejoining later.
create unique index if not exists business_members_one_active_per_user
  on business_members (user_id)
  where status = 'active';
