# CPUTemp package - build notes 

## What's solid
- `package.json`, `config`, `api.cgi` structure, `postinst` sudoers pattern —
  cloned directly from your real SourceManager files.
- `syno_cpu_temp.sh` — your original script, unmodified.
- `syno_cpu_temp.conf` — same key format as the original repo, with one new
  key added: `Log_Days` (retention, read/written by `cpu_temp_api.sh`).

## What's reconstructed, not copied
- `main.js` uses the "render directly into the DSM desktop document, no
  iframe" pattern we described fixing the click-to-front bug with on
  AQC_Unlock — but I don't have that literal file, so this is rebuilt from
  the pattern description, not copied. If you have `aqc_unlock.js` handy,
  worth a side-by-side check before relying on it.
- Lifecycle scripts (`preinst`/`postinst`/`preuninst`/`postuninst`/
  `start-stop-status`) use the standard Synology package conventions
  (`$PKG_NAME`-based paths, sudoers.d grant, no-daemon start-stop-status
  template) — not copied from one of your files since I didn't have a
  reference postinst. Worth comparing against whatever SourceManager's
  postinst actually does, particularly the sudoers install step.

## Task Scheduler - confirmed 2026-07-31
Verified live against DS218 (DSM 7) and Webber (DSM 6.2.4):
- `SYNO.Core.TaskScheduler` (not `.Root`) works on both DSM 6 and 7 -
  just switch `version=1` (DSM 6) vs `version=4` (DSM 7), including a
  `"version":4` key nested inside `schedule` itself for v4.
- v4's `repeat_date` must be `1001` for daily-repeat tasks (`0` is
  rejected: "Invalid repeat [0] for date_type [0] for v4"). v1 uses
  plain `0`.
- v4 has `repeat_min`; v1 doesn't.
- `method=create` confirmed working with this shape on both versions.
- `method=set_enable` (v2, `status` array of `{id, real_owner, enable}`)
  is used to disable the task without deleting it - this one comes
  from public reverse-engineering (github.com/N4S4/synology-api#158),
  not a live test on your NAS.
- **`method=set` (for editing an existing task's schedule) is NOT
  verified** - `task_setup.sh` assumes it takes the same shape as
  `create` plus `id`. First thing to check if changing the frequency
  on an already-scheduled task misbehaves.

## Needs your input before it's real
- **`os_min_ver": "6.0-0"`** in `package.json` is a placeholder — I don't
  have your DSM 6.0 minimum build number memorized and won't guess it.
  Confirm/replace before building.
- **Task Scheduler / frequency setting**: not wired up at all yet. The
  Settings window has the dropdown UI but it's inert ("Not yet active"
  note shown to the user) until we get `SYNO.Core.TaskScheduler`'s
  create/set params confirmed — either via `method=get` on an existing
  task, or a captured browser request from Edit Task > Schedule > OK.
- **Icons**: `config` references `images/icon_{0}.png` but no icon files
  are included — you'll need to drop in `icon_256.png`, `icon_72.png`,
  `icon_32.png` (or whatever sizes DSM expects; check SourceManager's
  `images/` folder for the actual set it uses) plus
  `synology/PACKAGE_ICON.PNG` and `PACKAGE_ICON_256.PNG` at package root.

## How the main window flow works
1. Open → `api.cgi?action=run` → sudo'd `cpu_temp_api.sh run` → runs
   `syno_cpu_temp.sh` (creates the log header on first run, same as it
   does standalone) → then prunes log entries older than `Log_Days`.
2. → `api.cgi?action=getlog` → returns the log file contents.
3. Settings window: `getsettings`/`setsettings` read and rewrite
   `Log` and `Log_Days` in `syno_cpu_temp.conf` directly (plain file
   edit via python3, no Synology API needed since it's a file the
   package fully owns).

## Not yet tested on a real NAS
None of this has been run against DSM. Before relying on it: verify
`sudo -n` actually works for the package's service account the way it
did for SourceManager (same grant pattern, but worth confirming with a
real install), and sanity-check the log-pruning regex against a real
log file your script has written.
