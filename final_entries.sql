-- Step 5 (12 Nov): one final entry per team (no edit code, no replacing, no deleting), and the board shows only the best file's RMSE.
drop function if exists public.submit(text, text, jsonb, jsonb);
alter table public.entries drop column if exists code_hash;
create function public.submit(p_team text, p_a jsonb, p_b jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare canon text;
begin
  select name into canon from public.zindi_teams where lower(name) = lower(btrim(p_team));
  if canon is null then raise exception 'Use your team or user name exactly as it appears on the Zindi leaderboard.'; end if;
  if p_a is null or p_b is null then raise exception 'Please upload both of your selected files.'; end if;
  perform public._check_preds(p_a);
  perform public._check_preds(p_b);
  if exists (select 1 from public.entries where lower(team) = lower(canon)) then
    raise exception 'This team already has an entry. Entries are final.';
  end if;
  insert into public.entries (team, preds_a, preds_b) values (canon, p_a, p_b);
  return 'saved';
end $$;
grant execute on function public.submit(text, jsonb, jsonb) to anon, authenticated;

drop function if exists public.leaderboard();
create function public.leaderboard()
returns table (team_name text, best double precision, hours int)
language sql stable security definer set search_path = public as $$
  with t as (select id, y from public.truth where n >= 3),
  a as (select e.team, sqrt(avg(((p.value)::float8 - t.y) ^ 2)) r, count(*) c
        from public.entries e cross join lateral jsonb_each(e.preds_a) p join t on t.id = p.key group by e.team),
  b as (select e.team, sqrt(avg(((p.value)::float8 - t.y) ^ 2)) r
        from public.entries e cross join lateral jsonb_each(e.preds_b) p join t on t.id = p.key group by e.team)
  select e.team, least(a.r, b.r), coalesce(a.c, 0)::int
  from public.entries e left join a on a.team = e.team left join b on b.team = e.team
  order by 2 nulls last, e.created_at;
$$;
grant execute on function public.leaderboard() to anon, authenticated;
