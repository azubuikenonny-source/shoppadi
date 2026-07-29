-- ShopPadi row-level security (Phase 0)
-- Every business-scoped table: members read, role-gated writes.

-- ---------------------------------------------------------------- helpers
create schema if not exists app;

create or replace function app.is_member(bid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from business_members
    where business_id = bid and user_id = auth.uid() and status = 'active'
  );
$$;

create or replace function app.has_role(bid uuid, roles member_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from business_members
    where business_id = bid and user_id = auth.uid()
      and status = 'active' and role = any (roles)
  );
$$;

-- ---------------------------------------------------------------- enable RLS
alter table businesses       enable row level security;
alter table profiles         enable row level security;
alter table business_members enable row level security;
alter table products         enable row level security;
alter table product_units    enable row level security;
alter table stock_movements  enable row level security;
alter table customers        enable row level security;
alter table sales            enable row level security;
alter table sale_items       enable row level security;
alter table payments         enable row level security;
alter table returns          enable row level security;
alter table invoices         enable row level security;
alter table expenses         enable row level security;
alter table day_closes       enable row level security;
alter table whatsapp_orders  enable row level security;
alter table ai_messages      enable row level security;
alter table devices          enable row level security;
alter table subscriptions    enable row level security;
alter table app_config       enable row level security;

-- ---------------------------------------------------------------- businesses
create policy businesses_select on businesses for select
  using (app.is_member(id));
create policy businesses_insert on businesses for insert
  with check (auth.uid() is not null);   -- creator; membership row added in same rpc
create policy businesses_update on businesses for update
  using (app.has_role(id, array['owner']::member_role[]));

-- ---------------------------------------------------------------- profiles
create policy profiles_own on profiles for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------- membership
create policy members_select on business_members for select
  using (app.is_member(business_id));
create policy members_write on business_members for all
  using (app.has_role(business_id, array['owner']::member_role[]))
  with check (app.has_role(business_id, array['owner']::member_role[]));
-- bootstrap: a user may insert themself as owner of a business they just created
create policy members_bootstrap on business_members for insert
  with check (user_id = auth.uid() and role = 'owner'
              and not exists (select 1 from business_members m where m.business_id = business_members.business_id));

-- ---------------------------------------------------------------- catalog (owner/manager write)
create policy products_select on products for select using (app.is_member(business_id));
create policy products_write on products for all
  using (app.has_role(business_id, array['owner','manager']::member_role[]))
  with check (app.has_role(business_id, array['owner','manager']::member_role[]));

create policy product_units_select on product_units for select using (app.is_member(business_id));
create policy product_units_write on product_units for all
  using (app.has_role(business_id, array['owner','manager']::member_role[]))
  with check (app.has_role(business_id, array['owner','manager']::member_role[]));

-- movements: any member may insert sale-driven rows; ledger is append-only (no update/delete)
create policy stock_movements_select on stock_movements for select using (app.is_member(business_id));
create policy stock_movements_insert on stock_movements for insert
  with check (app.is_member(business_id));

-- ---------------------------------------------------------------- customers & sales
create policy customers_select on customers for select using (app.is_member(business_id));
create policy customers_write on customers for all
  using (app.is_member(business_id)) with check (app.is_member(business_id));

create policy sales_select on sales for select using (app.is_member(business_id));
create policy sales_insert on sales for insert with check (app.is_member(business_id));
-- void/return = update, owner/manager only; deletes never allowed
create policy sales_update on sales for update
  using (app.has_role(business_id, array['owner','manager']::member_role[]));

create policy sale_items_select on sale_items for select using (app.is_member(business_id));
create policy sale_items_insert on sale_items for insert with check (app.is_member(business_id));

create policy payments_select on payments for select using (app.is_member(business_id));
create policy payments_insert on payments for insert with check (app.is_member(business_id));

create policy returns_select on returns for select using (app.is_member(business_id));
create policy returns_write on returns for insert
  with check (app.has_role(business_id, array['owner','manager']::member_role[]));

-- ---------------------------------------------------------------- money ops (owner/manager)
create policy invoices_select on invoices for select using (app.is_member(business_id));
create policy invoices_write on invoices for all
  using (app.has_role(business_id, array['owner','manager']::member_role[]))
  with check (app.has_role(business_id, array['owner','manager']::member_role[]));

create policy expenses_select on expenses for select
  using (app.has_role(business_id, array['owner','manager']::member_role[]));
create policy expenses_write on expenses for all
  using (app.has_role(business_id, array['owner','manager']::member_role[]))
  with check (app.has_role(business_id, array['owner','manager']::member_role[]));

create policy day_closes_select on day_closes for select using (app.is_member(business_id));
create policy day_closes_insert on day_closes for insert with check (app.is_member(business_id));
-- discrepancies are permanent: no update/delete policies on day_closes

-- ---------------------------------------------------------------- integrations
create policy wa_orders_select on whatsapp_orders for select using (app.is_member(business_id));
create policy wa_orders_write on whatsapp_orders for all
  using (app.has_role(business_id, array['owner','manager']::member_role[]))
  with check (app.has_role(business_id, array['owner','manager']::member_role[]));

create policy ai_messages_owner on ai_messages for all
  using (app.has_role(business_id, array['owner']::member_role[]))
  with check (app.has_role(business_id, array['owner']::member_role[]));

create policy devices_own on devices for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy subscriptions_select on subscriptions for select
  using (app.has_role(business_id, array['owner']::member_role[]));
-- subscription writes happen only via service-role webhooks (bypass RLS)

create policy app_config_read on app_config for select using (auth.uid() is not null);

-- ---------------------------------------------------------------- cashier-safe product view
-- Cashiers query this instead of products: cost_price is nulled server-side,
-- so profit data physically never reaches a cashier session.
create view products_safe with (security_invoker = true) as
select
  p.id, p.business_id, p.name, p.sku, p.barcode, p.category, p.base_unit,
  case when app.has_role(p.business_id, array['owner','manager']::member_role[])
       then p.cost_price end as cost_price,
  p.selling_price, p.quantity, p.low_stock_level, p.vat_exempt, p.is_active, p.image_url,
  p.created_at, p.updated_at
from products p;
