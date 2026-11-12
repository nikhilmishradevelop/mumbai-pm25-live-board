-- Step 4 (12 Nov): entries can no longer be deleted from the page (a team can still replace its files with its edit code).
drop function if exists public.delete_entry(text, text);
