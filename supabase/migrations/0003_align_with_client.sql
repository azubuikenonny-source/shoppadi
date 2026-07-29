-- Columns the app added after the first two migrations were written.
-- Run this in the SQL editor before turning sync on.

-- Invoices are documents: the customer's name and phone are snapshotted so an
-- old invoice does not change when the customer record is edited later.
alter table invoices
  add column if not exists customer_name  text not null default '',
  add column if not exists customer_phone text,
  add column if not exists issued_at      timestamptz not null default now(),
  add column if not exists note           text,
  add column if not exists sale_id        uuid references sales (id) on delete set null;

-- Which wallet a refund was transferred back through.
alter table returns
  add column if not exists channel transfer_channel;

-- Who counted the till, and the shop's own key/value settings.
alter table day_closes
  add column if not exists note text;

create table if not exists app_settings (
  business_id uuid not null references businesses (id) on delete cascade,
  key         text not null,
  value       text not null,
  updated_at  timestamptz not null default now(),
  primary key (business_id, key)
);

alter table app_settings enable row level security;

create policy app_settings_select on app_settings for select
  using (app.is_member(business_id));
create policy app_settings_write on app_settings for all
  using (app.has_role(business_id, array['owner','manager']::member_role[]))
  with check (app.has_role(business_id, array['owner','manager']::member_role[]));

create trigger app_settings_touch before update on app_settings
  for each row execute function set_updated_at();
