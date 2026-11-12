"""Fetch the OpenAQ hourly PM2.5 readings for the 4 challenge stations (11-12 Nov 2026) and save them in the Supabase `truth` table.
Standard library only, so it runs on a bare GitHub Actions runner.
Secrets come from the environment (OPENAQ_KEY, BOARD_WRITE_TOKEN) or, locally, from ../.secrets/ files. Never printed.
The write token can only call put_truth (writer.sql); the Supabase URL and publishable key below are public by design.
Usage: python update_truth.py [--dry-run] [--check submission.csv ...]"""
import csv, json, math, os, pathlib, ssl, sys, time, urllib.parse, urllib.request
try:
    import certifi; CTX = ssl.create_default_context(cafile=certifi.where())   # some local Pythons have no system certificates
except ImportError:
    CTX = ssl.create_default_context()
SENSORS = {11606: 12236418, 11611: 12236426, 3409510: 12238567, 3409511: 12238576}   # location_id -> OpenAQ sensor (Stations.csv)
HERE = pathlib.Path(__file__).resolve().parent
SUPABASE_URL = "https://kpbsmoupajiuxgazebgk.supabase.co"
SUPABASE_KEY = "sb_publishable_WQ6aHckixs5FQHWj2SMg8w_l6B6QzKu"
def secret(env, fname):
    v = os.environ.get(env)
    if v: return v.strip()
    p = HERE.parent / ".secrets" / fname
    return p.read_text().strip() if p.exists() else None
def valid_ids():   # the 192 scored rows: hour-ends 11 Nov 01:00 .. 13 Nov 00:00 IST, IDs as in Test.csv
    out = []
    for loc in SENSORS:
        for k in range(48):
            d, h = 11 + (k + 1) // 24, (k + 1) % 24
            out.append(f"MUM_{loc}_202611{d:02d}T{h:02d}00_IST")
    return out
VALID = set(valid_ids()); assert len(VALID) == 192
def get(url, key, tries=5):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"X-API-Key": key, "User-Agent": "mumbai-pm25-live-board"})
            with urllib.request.urlopen(req, timeout=60, context=CTX) as r: return json.load(r)
        except Exception as e:
            err = e; time.sleep(5 * (i + 1))
    raise RuntimeError(f"OpenAQ request failed after {tries} tries: {type(err).__name__}")
def fetch():
    key = secret("OPENAQ_KEY", "openaq_key"); assert key, "no OpenAQ key"
    q = urllib.parse.urlencode(dict(datetime_from="2026-11-11T00:00:00+05:30", datetime_to="2026-11-13T01:00:00+05:30", limit=1000))
    rows = []
    for loc, sid in SENSORS.items():
        for r in get(f"https://api.openaq.org/v3/sensors/{sid}/hours?{q}", key)["results"]:
            end = r["period"]["datetimeTo"]["local"]   # e.g. 2026-11-11T01:00:00+05:30 (hour END, IST)
            assert end.endswith("+05:30"), end
            i = f"MUM_{loc}_{end[0:4]}{end[5:7]}{end[8:10]}T{end[11:13]}{end[14:16]}_IST"
            if i in VALID and r.get("value") is not None:
                rows.append(dict(id=i, y=float(r["value"]), n=int((r.get("coverage") or {}).get("observedCount") or 0)))
        time.sleep(1)
    return rows
def upload(rows):
    tok = secret("BOARD_WRITE_TOKEN", "board_write_token"); assert tok, "no write token"
    h = {"apikey": SUPABASE_KEY, "Content-Type": "application/json"}
    body = json.dumps(dict(p_token=tok, p_rows=rows)).encode()
    req = urllib.request.Request(SUPABASE_URL + "/rest/v1/rpc/put_truth", data=body, headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=60, context=CTX) as r: print("saved", r.read().decode(), "rows in Supabase")
def check(rows, path):   # RMSE of a submission on hours with >= 3 readings, the same rule as the board
    y = {r["id"]: r["y"] for r in rows if r["n"] >= 3}
    p = {row["ID"]: float(row["Target"]) for row in csv.DictReader(open(path))}
    e = [p[i] - v for i, v in y.items()]
    print(f"{path}: RMSE {math.sqrt(sum(x * x for x in e) / len(e)):.2f} on {len(e)} station-hours")
if __name__ == "__main__":
    rows = fetch(); scored = [r for r in rows if r["n"] >= 3]
    print(f"fetched {len(rows)} station-hours, {len(scored)} with >= 3 readings, latest hour-end {max(r['id'][-17:-4] for r in rows) if rows else '-'}")
    args = sys.argv[1:]
    if "--check" in args:
        for path in args[args.index("--check") + 1:]: check(rows, path)
    if "--dry-run" not in args: upload(rows)
