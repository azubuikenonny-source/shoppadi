-- One-off repair for the duplicate created by the race that 0005 fixes.
--
-- Signing in fired two concurrent create_business_for_me calls; both saw no
-- membership and both created a shop, two microseconds apart. All the actual
-- records landed under one of them, leaving the other completely empty.
--
-- Deliberately narrow: this only removes a business that holds nothing at all
-- AND whose owner also belongs to another business. A shop that is merely new
-- and empty is left alone, so running this on a fresh project does nothing.

with orphans as (
  select b.id
  from businesses b
  where not exists (select 1 from products      where business_id = b.id)
    and not exists (select 1 from sales         where business_id = b.id)
    and not exists (select 1 from customers     where business_id = b.id)
    and not exists (select 1 from invoices      where business_id = b.id)
    and not exists (select 1 from day_closes    where business_id = b.id)
    and not exists (select 1 from payments      where business_id = b.id)
    and not exists (select 1 from returns       where business_id = b.id)
    and exists (
      select 1
      from business_members mine
      join business_members other
        on other.user_id = mine.user_id
       and other.business_id <> b.id
      where mine.business_id = b.id
    )
),
cleared as (
  delete from business_members
  where business_id in (select id from orphans)
  returning business_id
)
delete from businesses
where id in (select id from orphans);
