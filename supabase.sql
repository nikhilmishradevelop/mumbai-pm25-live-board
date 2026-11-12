-- Live board for the Google Mumbai Data Challenge (unofficial). Paste all of this into Supabase > SQL Editor > New query > Run.
-- Visitors (anon key) can: read the truth table, call submit / delete_entry / leaderboard. They can NOT read anyone's predictions.
create extension if not exists pgcrypto with schema extensions;

-- the 192 scored rows (hour-ends 11 Nov 01:00 .. 13 Nov 00:00 IST, IDs as in Test.csv)
create table if not exists public.private_ids (id text primary key);
insert into public.private_ids
select 'MUM_' || s || '_' || to_char(t, 'YYYYMMDD"T"HH24MI') || '_IST'
from unnest(array[11606, 11611, 3409510, 3409511]) s,
     generate_series(timestamp '2026-11-11 01:00', timestamp '2026-11-13 00:00', interval '1 hour') t
on conflict do nothing;

-- OpenAQ readings, written every hour by update_truth.py (service key). n = readings in that hour; only n >= 3 is scored.
create table if not exists public.truth (id text primary key references public.private_ids(id), y double precision not null,
  n int not null, updated_at timestamptz not null default now());

-- one row per team: the 192 numbers of each of its two files as {ID: value}
create table if not exists public.entries (
  team text not null check (char_length(team) between 2 and 40),
  code_hash text not null,
  preds_a jsonb not null, preds_b jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create unique index if not exists entries_team_lower on public.entries (lower(team));

alter table public.private_ids enable row level security;
alter table public.truth enable row level security;
alter table public.entries enable row level security;
drop policy if exists "truth is public" on public.truth;
create policy "truth is public" on public.truth for select using (true);
-- no policy on entries: visitors only reach it through the functions below

create or replace function public._check_preds(p jsonb) returns void language plpgsql set search_path = public as $$
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Could not read the file.'; end if;
  if (select count(*) from jsonb_each(p)) <> 192 then raise exception 'Each file must contain the 192 rows of 11-12 Nov.'; end if;
  if exists (select 1 from jsonb_each(p) e
             where e.key not in (select id from public.private_ids)
                or case when jsonb_typeof(e.value) = 'number' then (e.value)::float8 not between 0 and 5000 else true end)
  then raise exception 'Every 11-12 Nov value must be a number between 0 and 5000.'; end if;
end $$;

create or replace function public.submit(p_team text, p_code text, p_a jsonb, p_b jsonb default null) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  p_team := btrim(p_team);
  if p_team is null or char_length(p_team) not between 2 and 40 then raise exception 'Team name must be 2-40 characters.'; end if;
  if p_code is null or char_length(p_code) < 4 then raise exception 'The edit code must be at least 4 characters.'; end if;
  perform public._check_preds(p_a);
  if p_b is not null then perform public._check_preds(p_b); end if;
  select code_hash into h from public.entries where lower(team) = lower(p_team);
  if h is null then
    if (select count(*) from public.entries) >= 1000 then raise exception 'The board is full.'; end if;
    insert into public.entries (team, code_hash, preds_a, preds_b) values (p_team, crypt(p_code, gen_salt('bf')), p_a, p_b);
    return 'saved';
  elsif h = crypt(p_code, h) then
    update public.entries set preds_a = p_a, preds_b = p_b, updated_at = now() where lower(team) = lower(p_team);
    return 'replaced';
  else
    raise exception 'That team name is taken. Enter its edit code to replace the files, or pick another name.';
  end if;
end $$;

create or replace function public.delete_entry(p_team text, p_code text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select code_hash into h from public.entries where lower(team) = lower(btrim(p_team));
  if h is null or h <> crypt(p_code, h) then raise exception 'Team name or edit code is wrong.'; end if;
  delete from public.entries where lower(team) = lower(btrim(p_team));
  return 'deleted';
end $$;

-- RMSE of each file on the hours with >= 3 readings so far; a team ranks by its better file (as on Zindi)
create or replace function public.leaderboard()
returns table (team_name text, best double precision, file_a double precision, file_b double precision, hours int, last_upload timestamptz)
language sql stable security definer set search_path = public as $$
  with t as (select id, y from public.truth where n >= 3),
  a as (select e.team, sqrt(avg(((p.value)::float8 - t.y) ^ 2)) r, count(*) c
        from public.entries e cross join lateral jsonb_each(e.preds_a) p join t on t.id = p.key group by e.team),
  b as (select e.team, sqrt(avg(((p.value)::float8 - t.y) ^ 2)) r
        from public.entries e cross join lateral jsonb_each(e.preds_b) p join t on t.id = p.key group by e.team)
  select e.team, least(a.r, coalesce(b.r, a.r)), a.r, b.r, coalesce(a.c, 0)::int, e.updated_at
  from public.entries e left join a on a.team = e.team left join b on b.team = e.team
  order by 2 nulls last, e.created_at;
$$;

revoke execute on function public._check_preds(jsonb) from public, anon, authenticated;
grant execute on function public.submit(text, text, jsonb, jsonb), public.delete_entry(text, text), public.leaderboard() to anon, authenticated;
