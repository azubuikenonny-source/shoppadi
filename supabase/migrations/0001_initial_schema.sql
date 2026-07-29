-- ShopPadi initial schema (Phase 0)
-- Money is ALWAYS bigint kobo. Quantities are numeric(14,3) in base units.

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------- enums
create type member_role as enum ('owner', 'manager', 'cashier');
create type member_status as enum ('invited', 'active', 'removed');
create type payment_method as enum ('cash', 'transfer', 'pos', 'card', 'credit', 'split');
create type transfer_channel as enum ('opay', 'palmpay', 'moniepoint', 'bank', 'other');
create type payment_provider as enum ('paystack', 'flutterwave', 'opay', 'palmpay', 'moniepoint', 'manual');
create type sale_status as enum ('completed', 'voided', 'returned', 'partially_returned');
create type stock_movement_type as enum ('purchase', 'sale', 'adjustment', 'return');
create type invoice_status as enum ('draft', 'sent', 'partial', 'paid', 'overdue', 'cancelled');
create type refund_method as enum ('cash', 'transfer', 'debt_credit');
create type wa_order_status as enum ('new', 'confirmed', 'rejected', 'fulfilled');
create type plan_tier as enum ('free', 'pro', 'business');

-- ---------------------------------------------------------------- core
create table businesses (
  id              uuid primary key default uuid_generate_v4(),
  name            text not null,
  currency        text not null default 'NGN',
  address         text,
  phone           text,
  logo_url        text,
  vat_enabled     boolean not null default false,
  vat_rate        numeric(5,2) not null default 7.50,
  receipt_footer  text,
  closing_hour    smallint not null default 20,      -- 24h clock, for day-summary push
  plan            plan_tier not null default 'free',
  next_receipt_no integer not null default 1,
  next_invoice_no integer not null default 1,
  -- shop's own wallet/bank accounts, printed on receipts ("Transfer to: ...")
  payout_accounts jsonb not null default '[]',       -- [{channel, account_no, account_name}]
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null default '',
  phone      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table business_members (
  business_id uuid not null references businesses (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  role        member_role not null default 'cashier',
  status      member_status not null default 'active',
  -- manager visibility toggle (section 6 of design doc)
  can_see_profit boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (business_id, user_id)
);

-- ---------------------------------------------------------------- catalog
create table products (
  id              uuid primary key default uuid_generate_v4(),
  business_id     uuid not null references businesses (id) on delete cascade,
  name            text not null,
  sku             text,
  barcode         text,
  category        text,
  base_unit       text not null default 'piece',     -- piece | sachet | kg | ...
  cost_price      bigint not null default 0,         -- kobo, per base unit
  selling_price   bigint not null default 0,         -- kobo, per base unit
  quantity        numeric(14,3) not null default 0,  -- cached rollup of stock_movements, base units
  low_stock_level numeric(14,3) not null default 0,
  vat_exempt      boolean not null default false,
  is_active       boolean not null default true,
  image_url       text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index products_business_idx on products (business_id) where is_active;
create index products_barcode_idx on products (business_id, barcode) where barcode is not null;

create table product_units (
  id             uuid primary key default uuid_generate_v4(),
  business_id    uuid not null references businesses (id) on delete cascade,
  product_id     uuid not null references products (id) on delete cascade,
  unit_name      text not null,                      -- carton | pack | dozen | ...
  factor_to_base numeric(14,3) not null check (factor_to_base > 0),
  selling_price  bigint not null,                    -- kobo, per this unit
  barcode        text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index product_units_product_idx on product_units (product_id);

create table stock_movements (
  id          uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses (id) on delete cascade,
  product_id  uuid not null references products (id) on delete cascade,
  type        stock_movement_type not null,
  qty         numeric(14,3) not null,                -- signed, base units (sale rows are negative)
  unit_cost   bigint,                                -- kobo, set on purchase
  note        text,
  ref_sale_id uuid,                                  -- backlink for sale/return movements
  created_by  uuid references auth.users (id),
  created_at  timestamptz not null default now()
);
create index stock_movements_product_idx on stock_movements (product_id, created_at);

-- ---------------------------------------------------------------- customers & sales
create table customers (
  id             uuid primary key default uuid_generate_v4(),
  business_id    uuid not null references businesses (id) on delete cascade,
  name           text not null,
  phone          text,
  whatsapp_phone text,
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index customers_business_idx on customers (business_id);

create table sales (
  id               uuid primary key default uuid_generate_v4(),
  business_id      uuid not null references businesses (id) on delete cascade,
  customer_id      uuid references customers (id) on delete set null,
  receipt_no       integer not null,
  subtotal         bigint not null default 0,
  discount         bigint not null default 0,
  vat_amount       bigint not null default 0,
  total            bigint not null default 0,
  amount_paid      bigint not null default 0,        -- total - amount_paid > 0 => debt
  payment_method   payment_method not null default 'cash',
  transfer_channel transfer_channel,
  status           sale_status not null default 'completed',
  sale_date        date not null default current_date,
  created_by       uuid references auth.users (id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (business_id, receipt_no)
);
create index sales_business_date_idx on sales (business_id, sale_date);
create index sales_customer_idx on sales (customer_id) where customer_id is not null;

create table sale_items (
  id                 uuid primary key default uuid_generate_v4(),
  business_id        uuid not null references businesses (id) on delete cascade,
  sale_id            uuid not null references sales (id) on delete cascade,
  product_id         uuid not null references products (id),
  unit_id            uuid references product_units (id),
  qty                numeric(14,3) not null,          -- in the sold unit
  qty_base           numeric(14,3) not null,          -- stock decrement, base units
  unit_price         bigint not null,                 -- kobo, per sold unit
  unit_cost_snapshot bigint not null default 0        -- kobo per base unit at sale time (exact COGS)
);
create index sale_items_sale_idx on sale_items (sale_id);

create table payments (
  id           uuid primary key default uuid_generate_v4(),
  business_id  uuid not null references businesses (id) on delete cascade,
  sale_id      uuid references sales (id) on delete set null,
  invoice_id   uuid,                                  -- fk added after invoices table
  amount       bigint not null,                       -- kobo; negative = refund out
  method       payment_method not null default 'cash',
  channel      transfer_channel,
  provider     payment_provider not null default 'manual',
  provider_ref text,
  verified     boolean not null default false,        -- true once webhook-confirmed
  created_by   uuid references auth.users (id),
  created_at   timestamptz not null default now()
);
create index payments_business_idx on payments (business_id, created_at);
create index payments_sale_idx on payments (sale_id) where sale_id is not null;

create table returns (
  id            uuid primary key default uuid_generate_v4(),
  business_id   uuid not null references businesses (id) on delete cascade,
  sale_id       uuid not null references sales (id) on delete cascade,
  items         jsonb not null,                       -- [{sale_item_id, qty}]
  restock       boolean not null default true,
  refund_method refund_method not null default 'cash',
  amount        bigint not null default 0,
  reason        text,
  created_by    uuid references auth.users (id),
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------- invoices & money ops
create table invoices (
  id           uuid primary key default uuid_generate_v4(),
  business_id  uuid not null references businesses (id) on delete cascade,
  invoice_no   integer not null,
  customer_id  uuid references customers (id) on delete set null,
  items        jsonb not null default '[]',           -- [{description, qty, unit_price}]
  subtotal     bigint not null default 0,
  vat_amount   bigint not null default 0,
  total        bigint not null default 0,
  amount_paid  bigint not null default 0,
  due_date     date,
  status       invoice_status not null default 'draft',
  pdf_url      text,
  payment_link text,
  created_by   uuid references auth.users (id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (business_id, invoice_no)
);
alter table payments
  add constraint payments_invoice_fk foreign key (invoice_id) references invoices (id) on delete set null;

create table expenses (
  id           uuid primary key default uuid_generate_v4(),
  business_id  uuid not null references businesses (id) on delete cascade,
  category     text not null default 'other',         -- rent|transport|supplies|salaries|utilities|other
  amount       bigint not null,
  note         text,
  expense_date date not null default current_date,
  created_by   uuid references auth.users (id),
  created_at   timestamptz not null default now()
);
create index expenses_business_date_idx on expenses (business_id, expense_date);

create table day_closes (
  id             uuid primary key default uuid_generate_v4(),
  business_id    uuid not null references businesses (id) on delete cascade,
  close_date     date not null default current_date,
  closed_by      uuid references auth.users (id),
  expected_cash  bigint not null default 0,
  counted_cash   bigint not null default 0,
  discrepancy    bigint generated always as (counted_cash - expected_cash) stored,
  channel_totals jsonb not null default '{}',         -- {cash, opay, palmpay, moniepoint, bank, card}
  note           text,
  created_at     timestamptz not null default now()
);
create index day_closes_business_idx on day_closes (business_id, close_date);

-- ---------------------------------------------------------------- integrations
create table whatsapp_orders (
  id             uuid primary key default uuid_generate_v4(),
  business_id    uuid not null references businesses (id) on delete cascade,
  customer_phone text not null,
  raw_message    text not null,
  parsed_items   jsonb,
  status         wa_order_status not null default 'new',
  sale_id        uuid references sales (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table ai_messages (
  id          uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses (id) on delete cascade,
  thread_id   uuid not null,
  role        text not null check (role in ('user', 'assistant')),
  content     text not null,
  created_at  timestamptz not null default now()
);

create table devices (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  fcm_token  text not null unique,
  platform   text not null default 'android',
  last_seen  timestamptz not null default now()
);

create table subscriptions (
  business_id        uuid primary key references businesses (id) on delete cascade,
  plan               plan_tier not null default 'free',
  provider           payment_provider,
  provider_ref       text,
  current_period_end timestamptz,
  status             text not null default 'active',
  updated_at         timestamptz not null default now()
);

create table app_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
insert into app_config (key, value) values
  ('tax', '{"vat_rate": 7.5, "disclaimer": "Estimate only — not tax advice. Confirm with a professional."}');

-- ---------------------------------------------------------------- triggers
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['businesses','profiles','business_members','products','product_units',
                           'customers','sales','invoices','whatsapp_orders','subscriptions']
  loop
    execute format('create trigger %I_touch before update on %I
                    for each row execute function set_updated_at()', t, t);
  end loop;
end $$;

-- keep products.quantity as an exact rollup of the movement ledger
create or replace function apply_stock_movement() returns trigger
language plpgsql as $$
begin
  update products set quantity = quantity + new.qty where id = new.product_id;
  return new;
end $$;

create trigger stock_movements_apply
  after insert on stock_movements
  for each row execute function apply_stock_movement();

-- per-business receipt numbering (client passes receipt_no from this when online;
-- offline clients reserve via sync — see design doc section 5)
create or replace function next_receipt_no(bid uuid) returns integer
language sql as $$
  update businesses set next_receipt_no = next_receipt_no + 1
  where id = bid
  returning next_receipt_no - 1;
$$;

create or replace function next_invoice_no(bid uuid) returns integer
language sql as $$
  update businesses set next_invoice_no = next_invoice_no + 1
  where id = bid
  returning next_invoice_no - 1;
$$;

-- ---------------------------------------------------------------- views
create view customer_balances as
select
  c.business_id,
  c.id as customer_id,
  c.name,
  c.phone,
  c.whatsapp_phone,
  coalesce(sum(s.total - s.amount_paid), 0)::bigint as balance,
  min(s.sale_date) filter (where s.total > s.amount_paid) as oldest_debt_date
from customers c
left join sales s
  on s.customer_id = c.id
 and s.status = 'completed'
 and s.total > s.amount_paid
group by c.business_id, c.id;
