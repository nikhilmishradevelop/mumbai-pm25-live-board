-- Step 2: a write password that can ONLY update the readings table (used by update_truth.py / the hourly GitHub job).
-- Only its SHA-256 fingerprint is stored here; the password itself stays in .secrets/board_write_token and the GitHub secret.
create table if not exists public.board_writer (token_sha256 text primary key);
alter table public.board_writer enable row level security;   -- no policy: nobody reads it through the API
insert into public.board_writer values ('__HASH__') on conflict do nothing;
create or replace function public.put_truth(p_token text, p_rows jsonb) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare k int;
begin
  if not exists (select 1 from public.board_writer where token_sha256 = encode(digest(p_token, 'sha256'), 'hex')) then raise exception 'not allowed'; end if;
  insert into public.truth (id, y, n, updated_at)
  select r->>'id', (r->>'y')::float8, (r->>'n')::int, now() from jsonb_array_elements(p_rows) r
  where r->>'id' in (select id from public.private_ids)
  on conflict (id) do update set y = excluded.y, n = excluded.n, updated_at = excluded.updated_at;
  get diagnostics k = row_count; return k;
end $$;
revoke execute on function public.put_truth(text, jsonb) from public;
grant execute on function public.put_truth(text, jsonb) to anon, authenticated;
