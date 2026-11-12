# Mumbai PM2.5 Live Board (unofficial)

Live, unofficial scores for the Zindi **Google Mumbai Data Challenge** on the private window (11-12 Nov 2026).
Teams upload their two selected files once; the board rescores them every hour as new readings arrive.

- **Page:** `index.html` (GitHub Pages). It reads only the 192 values for 11-12 Nov from each file and scores them on the server.
  Nobody can read anyone's predictions, only the scores.
- **Truth:** hourly PM2.5 from [OpenAQ](https://openaq.org) for the four challenge sensors (CPCB / IITM monitors). Only hours with
  at least 3 readings count. RMSE is pooled over the four stations; a team ranks by its better file, as on Zindi.
- **Not official.** Zindi uses its own copy of the data and may count hours differently.
- **Team names** must match a name on the Zindi leaderboard (list read 12 Nov, `zindi_teams.json`), any capitalisation.

## How it is built
- Database: Supabase (free). Setup in order: `supabase.sql`, `writer.sql`, `teams.sql`.
- `update_truth.py` (standard library only) fetches the readings and writes them through `put_truth`, a function that only accepts
  a write token whose SHA-256 is stored in the database. It runs every hour from `.github/workflows/update_truth.yml`.
- Repository secrets: `OPENAQ_KEY`, `BOARD_WRITE_TOKEN`. The Supabase URL and publishable key in the code are public by design.
