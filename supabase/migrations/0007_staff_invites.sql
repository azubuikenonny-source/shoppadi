-- Staff join by code. Inviting by phone number would mean creating a
-- membership for a person who has no account yet, and phone sign-in is not
-- configured anyway. A code the owner reads out loud works over a counter,
-- over WhatsApp, or shouted across a shop.

create table if not exists business_invites (
  code           text primary key,
  business_id    uuid not null references businesses (id) on delete cascade,
  role           member_role not null default 'cashier',
  can_see_profit boolean not null default false,
  created_by     uuid references auth.users (id),
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null default now() + interval '7 days',
  used_by        uuid references auth.users (id),
  used_at        timestamptz
);

create index if not exists business_invites_business_idx
  on business_invites (business_id);

alter table business_invites enable row level security;

-- Only the shop's owner ever reads its invites. Redeeming goes through the
-- function below, which runs as definer, so a joiner never needs to see the
-- table at all — otherwise anyone could enumerate codes.
create policy business_invites_owner on business_invites for select
  using (app.has_role(business_id, array['owner']::member_role[]));

-- Ambiguous characters left out: nobody reading a code aloud should have to
-- distinguish O from 0 or I from 1.
create or replace function public.generate_invite_code()
returns text
language sql
volatile
as $$
  select string_agg(
           substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789',
                  (random() * 30)::int + 1, 1),
           '')
  from generate_series(1, 6);
$$;

-- Owner creates an invite. Returns the code to read out.
create or replace function public.create_staff_invite(
  staff_role     text default 'cashier',
  sees_profit    boolean default false
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  my_business uuid;
  new_code    text;
  tries       int := 0;
begin
  select bm.business_id into my_business
  from business_members bm
  where bm.user_id = auth.uid()
    and bm.status = 'active'
    and bm.role = 'owner'
  limit 1;

  if my_business is null then
    raise exception 'only the shop owner can invite staff'
      using errcode = '42501';
  end if;

  if staff_role not in ('manager', 'cashier') then
    raise exception 'staff can be manager or cashier'
      using errcode = '22023';
  end if;

  -- Six characters from a 31-letter alphabet collide rarely, but "rarely" is
  -- not "never" once a shop has been running for a year.
  loop
    new_code := generate_invite_code();
    exit when not exists (select 1 from business_invites where code = new_code);
    tries := tries + 1;
    if tries > 20 then
      raise exception 'could not generate a free code';
    end if;
  end loop;

  insert into business_invites (code, business_id, role, can_see_profit, created_by)
  values (new_code, my_business, staff_role::member_role, sees_profit, auth.uid());

  return new_code;
end;
$$;

-- Anyone signed in can redeem a code. Returns the business joined.
create or replace function public.redeem_staff_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  invite     business_invites%rowtype;
  already    uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Same lock the shop-creation path uses, so redeeming and creating cannot
  -- race into two memberships for one person.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));

  select bm.business_id into already
  from business_members bm
  where bm.user_id = auth.uid() and bm.status = 'active'
  limit 1;

  if already is not null then
    raise exception 'you already belong to a shop — sign out first'
      using errcode = '23505';
  end if;

  select * into invite
  from business_invites
  where code = upper(btrim(invite_code))
  for update;

  if invite.code is null then
    raise exception 'that code is not recognised' using errcode = '22023';
  end if;
  if invite.used_at is not null then
    raise exception 'that code has already been used' using errcode = '22023';
  end if;
  if invite.expires_at < now() then
    raise exception 'that code has expired' using errcode = '22023';
  end if;

  insert into business_members (business_id, user_id, role, status, can_see_profit)
  values (invite.business_id, auth.uid(), invite.role, 'active', invite.can_see_profit);

  update business_invites
  set used_by = auth.uid(), used_at = now()
  where code = invite.code;

  insert into profiles (user_id, full_name, phone)
  values (
    auth.uid(),
    coalesce((select raw_user_meta_data ->> 'full_name'
                from auth.users where id = auth.uid()), ''),
    (select phone from auth.users where id = auth.uid())
  )
  on conflict (user_id) do nothing;

  return invite.business_id;
end;
$$;

-- What this user is allowed to do, for the app to gate its own UI.
create or replace function public.my_membership()
returns table (business_id uuid, role text, can_see_profit boolean)
language sql
stable
security definer
set search_path = public
as $$
  select bm.business_id, bm.role::text, bm.can_see_profit
  from business_members bm
  where bm.user_id = auth.uid()
    and bm.status = 'active'
  limit 1;
$$;

-- Who works here. The profiles policy deliberately lets a person read only
-- their own row, so listing colleagues has to come through a definer function
-- rather than by loosening that.
create or replace function public.list_staff()
returns table (
  user_id        uuid,
  full_name      text,
  phone          text,
  role           text,
  can_see_profit boolean,
  is_me          boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select bm.user_id,
         coalesce(p.full_name, ''),
         coalesce(p.phone, u.phone, ''),
         bm.role::text,
         bm.can_see_profit,
         bm.user_id = auth.uid()
  from business_members bm
  left join profiles p on p.user_id = bm.user_id
  left join auth.users u on u.id = bm.user_id
  where bm.status = 'active'
    and bm.business_id in (
      select business_id from business_members
      where user_id = auth.uid() and status = 'active'
    )
  order by
    case bm.role when 'owner' then 0 when 'manager' then 1 else 2 end,
    coalesce(p.full_name, '');
$$;

-- Owner removes someone. Marked removed rather than deleted so the audit
-- trail on their sales still resolves to a person.
create or replace function public.remove_staff(member_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  my_business uuid;
begin
  select bm.business_id into my_business
  from business_members bm
  where bm.user_id = auth.uid()
    and bm.status = 'active'
    and bm.role = 'owner'
  limit 1;

  if my_business is null then
    raise exception 'only the shop owner can remove staff'
      using errcode = '42501';
  end if;

  if member_user_id = auth.uid() then
    raise exception 'a shop cannot be left without its owner'
      using errcode = '22023';
  end if;

  update business_members
  set status = 'removed'
  where business_id = my_business and user_id = member_user_id;
end;
$$;

revoke all on function public.create_staff_invite(text, boolean) from public, anon;
revoke all on function public.redeem_staff_invite(text)          from public, anon;
revoke all on function public.my_membership()                    from public, anon;
revoke all on function public.remove_staff(uuid)                 from public, anon;
revoke all on function public.list_staff()                       from public, anon;

grant execute on function public.create_staff_invite(text, boolean) to authenticated;
grant execute on function public.redeem_staff_invite(text)          to authenticated;
grant execute on function public.my_membership()                    to authenticated;
grant execute on function public.remove_staff(uuid)                 to authenticated;
grant execute on function public.list_staff()                       to authenticated;

-- Staff need to see who they work with; the owner needs it to manage them.
drop policy if exists members_select on business_members;
create policy members_select on business_members for select
  using (app.is_member(business_id));
