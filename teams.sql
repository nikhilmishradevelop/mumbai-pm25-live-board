-- Step 3 (12 Nov): both files required, and the team name must be one of the 122 names on the Zindi leaderboard
-- (read 12 Nov ~13:15 IST, file zindi_teams.json; any capitalisation is accepted, the board shows Zindi's spelling).
create table if not exists public.zindi_teams (name text primary key);
create unique index if not exists zindi_teams_lower on public.zindi_teams (lower(name));
insert into public.zindi_teams (name) values
('bambai'),
('Shardul'),
('invouniesnry'),
('dhruvawani17'),
('Gaurav'),
('Neurix'),
('harshalkadam'),
('Sky force'),
('Chill&Drill'),
('Raj_Patil'),
('tiramisu'),
('harshal96'),
('PrimitMistry'),
('xtero9'),
('aahana77'),
('vikky'),
('ankitgpt18'),
('devnikhilmishra'),
('WeAreGood'),
('Binary Architect'),
('youngaura'),
('AQI Oracles'),
('Aman_Pundhir'),
('snub'),
('CHARLIE'),
('siddh'),
('Ansh0808'),
('axhhed'),
('aaryan_thakur69'),
('Technocrats'),
('dhruvy1'),
('Weather Warriors'),
('Shubhami9'),
('akshai'),
('Climate_Warriors'),
('Bughunter'),
('out_of_your_league'),
('DeepChavan'),
('sayedathar11'),
('maneshjadhav'),
('Mahim_0907'),
('guglxni'),
('indcoder'),
('skasliwal'),
('Jiyaan'),
('hitanshuac'),
('Tourist'),
('Sayak_'),
('abhisheksingh'),
('dhruval30'),
('Quantum Syndicate'),
('ubaid'),
('Blue_bottle'),
('SohamKanse'),
('Hackcoders'),
('pri21'),
('aqe17'),
('kaka20'),
('CoE AI VJTI'),
('immortalfoodie'),
('Panvelkar'),
('sarveshmohite'),
('Sumanth'),
('RugvedBane'),
('manaswi'),
('Gojo_06'),
('pradyumntandon'),
('HackVenger'),
('WolfHat'),
('Iamironman'),
('Akarsh_k'),
('Kryptonite'),
('aqeel1709'),
('kadamshravani187'),
('letsdeepchat'),
('vijaylaxmi'),
('Aarya_Chaudhari'),
('tanujamodakm'),
('akashadsare'),
('Prawns'),
('Bogosorters'),
('Archit47'),
('harshvt'),
('AryanMashalkar'),
('shewbham'),
('Nexora'),
('Air Aware'),
('Vipin'),
('Ramjas'),
('Simanga'),
('Tejaswi_Jadhav'),
('ananya_s'),
('hello23'),
('ASHISH_SHARMA_123'),
('The Outliers'),
('Ayan70781'),
('vinitialize'),
('KaifAnsari1'),
('Half-DASH'),
('DataBuddhaa'),
('JustDoingIt'),
('Playmakers'),
('sumansahoo16'),
('Jisoo'),
('Krishnadas'),
('Owaiskhan15'),
('Mugunth'),
('akshay_wagh'),
('thivya'),
('Vicky123'),
('Anant_Singh97'),
('HarshPicha'),
('saxenawave'),
('AdityaC07'),
('Sakshi07'),
('riddhesh'),
('kakashi'),
('Ishmeet'),
('kadamsumeet'),
('Demigod'),
('Young Money'),
('daniil_zindi')
on conflict do nothing;
alter table public.zindi_teams enable row level security;
drop policy if exists "team list is public" on public.zindi_teams;
create policy "team list is public" on public.zindi_teams for select using (true);

delete from public.entries where preds_b is null;
alter table public.entries alter column preds_b set not null;

drop function if exists public.submit(text, text, jsonb, jsonb);
create function public.submit(p_team text, p_code text, p_a jsonb, p_b jsonb) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare h text; canon text;
begin
  select name into canon from public.zindi_teams where lower(name) = lower(btrim(p_team));
  if canon is null then raise exception 'Use your team or user name exactly as it appears on the Zindi leaderboard.'; end if;
  if p_code is null or char_length(p_code) < 4 then raise exception 'The edit code must be at least 4 characters.'; end if;
  if p_a is null or p_b is null then raise exception 'Please upload both of your selected files.'; end if;
  perform public._check_preds(p_a);
  perform public._check_preds(p_b);
  select code_hash into h from public.entries where lower(team) = lower(canon);
  if h is null then
    insert into public.entries (team, code_hash, preds_a, preds_b) values (canon, crypt(p_code, gen_salt('bf')), p_a, p_b);
    return 'saved';
  elsif h = crypt(p_code, h) then
    update public.entries set preds_a = p_a, preds_b = p_b, updated_at = now() where lower(team) = lower(canon);
    return 'replaced';
  else
    raise exception 'This team already has an entry. Enter its edit code to replace the files.';
  end if;
end $$;
grant execute on function public.submit(text, text, jsonb, jsonb) to anon, authenticated;
