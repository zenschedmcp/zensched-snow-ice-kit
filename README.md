# ZenSched Snow & Ice Reference Kit

A copy-pasteable setup for a solo plow operator, or a 2–8 truck shop that dispatches subcontracted (1099) operators, that wants an AI assistant to run storm dispatch, same-night GPS-verified clears, after-photo proof before 7am, receivables from HOAs / commercial lots / municipalities, and sub payouts. ZenSched handles the phone app, the GPS check-in at each lot or driveway, the per-site same-day event and per-clear shift, and the Clear Proof. A small local database on your computer holds your contracts, the sites you plow, every storm and every clear with its GPS stamps, invoices, and payouts.

**You do not need to know how to program or write SQL to use this.** You tell your AI assistant "storm tonight, SLA 7am, put every site on the phones", text it "I'm at Maple now", ask "what's uncleared", "what's at risk", "log this storm", "invoice Cedar Ridge", "who owes me money", "what do I owe Pat", and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## This is not RealGreen / Boss LM / GPS Insight — and it is not a lawyer

**What this kit is:** a way for a snow-and-ice contractor to get every stop onto the phone when a storm opens (or on the spot when a truck rolls up), prove with a GPS-verified check-in that each clear happened at that address at that time, record what the surface looked like after the pass (driveway / lot / walk, bare / packed / icy, salt, after photos), flag lots that have not checked in before the SLA clock (usually 07:00), and turn those records into invoices, receivables follow-up, mileage totals, and 1099 payouts, with an AI assistant doing the clerical work.

**What it is not:**

- **It is not RealGreen, Boss LM, GPS Insight, or a municipal plow portal.** Those platforms run seasonal routing, weather triggers, and customer portals. This kit does not ingest NOAA alerts, does not auto-dispatch from a radar map, and does not push proof into a property-manager portal. You still send the invoice (and any portal photos) the way your contracts require. The Clear Proof and the GPS punches are *your* record so you can invoice and, if it comes to it, show when the truck was at the pin.
- **It does not write a slip-and-fall defense, and it does not know what "bare pavement" means in a contract.** `sla_at_risk` is the deadline you typed (default 07:00), not a rules engine. When you ask "are we covered", the AI will tell you who checked in, at what time, how far from the pin, and what the form said — and will say a court or insurer decides the rest. Never treat a completed Clear Proof as legal sign-off that a surface was safe.
- **It does not watermark photos.** ZenSched records the GPS punch coordinates and the upload time server-side, and the Clear Proof's after photos are stored with the submission, but the exported image is **not** stamped with the date, time, and coordinates. If an insurer or court later wants a readable stamp on the image itself, shoot with your phone camera's timestamp / GPS overlay turned on (or a GPS-stamp camera app) and upload *that* image.
- **It is not a gate-code manager.** Customer contacts and access notes stay on your computer.

If any of that is a deal-breaker, this kit is not for you. If you want every lot GPS-stamped before 7am, a photo report you can invoice from, and a list of who has not checked in yet, read on.

## What lives where

**ZenSched (source of truth for where the operator was and when):**

- Locations (one per site address, cached locally so a repeat lot is created once; the check-in radius is a policy setting)
- Workers (you, in solo mode; you plus your 1099s in agency mode, each with the mobile app)
- Events (one per site per calendar day — high-volume same-night work, not a 60-day job)
- Shifts (one per clear: a window from the default start, usually 04:00, through the SLA, with a push notification to the operator)
- GPS punches (check-in / check-out with distance-from-the-pin verification)
- The Clear Proof form (surface, condition, after photos, salt) and every submission with its photos

**Local SQLite database (`snow-ops.db`, on your computer):**

- Contracts: HOAs, commercial lots, municipalities, residential driveways, with payment terms, a per-push fee, a salt fee, and an SLA clock
- Sites: every lot or driveway you plow, normalized, with its ZenSched location id and access notes (gate, north entrance, hydrant) — **access notes never leave your computer**
- Operators: you (and your 1099s); payout split per sub (per clear, or percent of the bill)
- Storms: one weather event / "push", dated on the SLA morning
- Clears: one row per site per storm, the ZenSched event (same-day, per site) and shift id, the Clear Proof's surface / condition / salt / photo count / submission id, and the GPS stamps copied once
- Mileage with the IRS rate snapshot and deduction
- Invoices per contract with aging; payouts per 1099 per clear
- Your settings (timezone, default operator, clear length and start, SLA deadline, invoice terms and prefix, mileage rate, Clear Proof form id)

**Never duplicated:** the live schedule, punches, and photos stay in ZenSched. The local database stores *references* to them plus the few facts you need to answer "did Pat go", "was Maple bare", and "who owes me" without paying to re-read records.

### Privacy note

Everything that identifies a customer contact or opens a gate lives only in the local database: `contracts.contact_name` and `sites.access_notes`. `SKILL.md` forbids the AI from putting either into any ZenSched field, including location names, event titles, notes, and cancellation reasons (subs see those). **Site street addresses do go to ZenSched** — the geofence cannot work without them. ZenSched receives, per stop, the street address, a location label (`Lot - Maple Ave`), an event title made of the storm date and the street (`Clear 2026-01-14 - Maple Ave`), and the Clear Proof. The form itself tells the operator not to write names or codes in it.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `event_create`, `shift_create`, `shift_status`, `form_submissions`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `snow-ops.db` on your computer.

When you say "storm tonight, SLA 7am", the AI opens a storm dated on that morning, generates one clear per active site, pins every new lot on ZenSched, opens a **same-day event** so an unplanned "I'm here now" later is one call, and puts a window on each phone. You see the stop in the app, check in at the curb (GPS-verified), plow, fill in the Clear Proof with after photos, check out. When you roll up to a lot that was not on the list, you text the AI "I'm at Maple now" and a window is on your phone before you drop the blade. All night you can ask "what's uncleared" and "what's at risk" — at-risk means **not checked in before the deadline**. After the push you say "log this storm" and the AI pulls the verified times and the proofs, and tells you what is now receivable. "Invoice Cedar Ridge" produces a plain-text invoice under their terms; "who owes me money" ages what is open; "what do I owe Pat" lists their clears. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\snow-ops`
- Mac: `/Users/yourname/snow-ops`

The database file will be created automatically inside this folder the first time the AI uses it. This folder will contain customer contacts and gate codes; keep it on an encrypted, backed-up disk, not in a shared folder.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\snow-ops.db` (Windows) or `/snow-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "snow-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/snow-ops/snow-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\snow-ops\\snow-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Snow Service" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my snow-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run each statement and confirm the tables exist. The `snow-ops.db` file now exists in your folder with default settings (04:00 start, 180-minute windows, 07:00 SLA, net 30, $0.70/mile) you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 snow-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> We're Northland Snow & Ice in Bloomington, Minnesota, Central time. It's me, Sam Rivera, sam@example.com. Set me up.

It writes those to the `settings` table, **invites you to ZenSched as a worker** (you are the operator on the phone; $0.25, one time), creates the Clear Proof form on ZenSched (free), saves the form id so every stop gets it automatically, and sets the check-in policy. In agency mode you then say "add my sub Pat Okonkwo, pat@example.com, I pay them $40 a clear" (or "60%") for each operator you dispatch.

**Check-in radius and slack.** ZenSched enforces the radius through the account's policy, not per address, and with geofencing on it raises anything under 100 m to about 91 m (300 ft). This kit asks for **150 m** so a commercial lot and its entrance are covered. For mall and campus lots where you park a long way from the pin, ask the AI to "set the check-in radius to 250 m" (`policy_update`), or to move the pin onto the entrance (`location_update`, free; the `sites` cache keeps it). The kit sets `checkin_slack_min` to **45**: that is the early/late tolerance around a shift, so you can punch at 3:50 for a 4:00 window, and an "I'm here now" window the AI opened a minute after you parked still accepts the punch. `remote_checkin` turns GPS verification off for every visit and should be a last resort, because it also turns off the proof.

**Forgotten check-outs.** The kit sets a check-out reminder 15 minutes after the window ends (`checkout_reminder_min_after`).

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocoding, $0.03; skipped for a cached repeat address), inviting a worker ($0.25, including yourself), each GPS-verified check-in or check-out ($0.10), and reading a Clear Proof ($0.15 with the after photos, which the form requires; each record is billed once, ever). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A clear at a new address costs $0.03 + $0.20 + $0.15 = **$0.38**; every further storm at that address, and every clear at a cached address, costs **$0.35**. Four crews × 40 sites is 160 clears: about **$56 per storm** once the lots are pinned, plus $0.03 per brand-new address. A season of 12 storms on a cached book is about $670. The AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Storm tonight, 4–8 inches, SLA 7am, put every site on the phones."
- "What's uncleared?" / "What's at risk?"
- "I'm at Maple now." / "Pat at France Ave now."
- "Log this storm." / "What did Maple look like?"
- "Did Pat actually hit Maple this morning?"
- "Invoice Cedar Ridge." / "Invoice everyone."
- "Who owes me money?" / "Cedar Ridge paid INV-2026-0001."
- "What do I owe Pat?" / "Paid Pat."
- "Mileage for January?"

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### Planned windows and "I'm here now"

ZenSched only records a GPS check-in against a scheduled shift, and operators decide to hit a lot between two planned stops — or a lot that was added after the storm opened. The kit handles that two ways, and `SKILL.md` teaches both:

- **Planned windows.** When a storm opens, the AI creates one clear window on the SLA morning for each active site (default start 04:00, 180 minutes, so the window covers the 07:00 clock). You can give it a route ("first stop 4:00") or leave the default and rearrange later.
- **"I'm here now."** You (or a sub, through you) text the AI "I'm at Maple now". If that site already has a planned window, the AI tells you to punch it (45 minutes of slack). If not, it inserts a clear with `scheduled_start` = now, creates a shift from now to now + 30 minutes on that site's **existing same-day event**, and replies in one line. The operator punches within the minute. Because every site gets its location and today's event when the storm opens, this is a single ZenSched call.

The `checkin_slack_min` policy setting (45 minutes in this kit) is what makes both work: early or late punches around a planned window are accepted, and an ad hoc window created a minute after the operator parked accepts the punch too. This is the kit's answer to a platform gap: ZenSched has no "check in now at location X" without a shift, so the agent creates the shift. It is one round-trip, not zero.

One non-cancelled clear per site per storm. A second push is a new storm ("open push 2").

### What "invoice" means here

"Invoice Cedar Ridge" records the invoice in your database (number, date, due date under that contract's terms, total, which clears with condition / salt and the fee breakdown) and the AI writes out a plain-text invoice you can paste into an email, with a line per clear (storm ref, street, surface, condition, salt, fee). It does **not** generate a PDF, submit it to RealGreen, or collect payment. Invoices never carry a gate code. When the contract pays, tell the AI ("Cedar Ridge paid INV-2026-0001") and it marks it paid. "Who owes me money" ages what is open into current / 30 / 60 / 90+ days past due. Seasonal retainers are informational on the contract; they are not auto-billed.

### What "payouts" means here (agency mode)

Subs are paid per clear, not by the hour. Each sub has a split: `$40 per clear` (one payout when a clear they completed is logged), or `60%` of what the contract is billed for that clear. When results are logged, payout rows are created with the amount; "what do I owe Pat" lists unpaid work and the total, and "paid Pat" marks them. Your own clears never generate payouts. The kit does not calculate taxes, issue 1099s, or pay anyone. If you also want an hours record, ZenSched's `timesheet_export(mode="hours")` is free; `mode="raw"` (one row per punch, free) is the export to hand an insurer if asked for the underlying GPS record.

## Mobile app for operators

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

In solo mode you invite yourself; the email arrives at your own address, you install the app, and your clear windows appear as they are created. Each one shows the address and time; you check in on arrival (GPS-verified), plow, fill in the Clear Proof with after photos, and check out. Subs get the same email when you add them. iOS is TestFlight for now: builds expire every 90 days and the install is unfamiliar; ask which phones your 1099s carry.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `snow-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set, or daylight saving changed | "Set my timezone offset to -06:00 in settings" (use your own offset; Central is -06:00 in winter, -05:00 in summer) |
| Clear not on my phone | Planned locally but the ZenSched shift was never created (`needs_shift = 1`) | "Put tonight's clears on my phone"; the AI finishes the storm-open steps |
| Check-in rejected: too early / too late | Slack window too small for a dense route | "Set the check-in slack to 60 minutes" (`checkin_slack_min`, max 240), or have the AI `shift_update` the window before you punch |
| Check-in rejected: not at the location, at a mall or campus lot | You parked outside the policy radius, or the pin is on the road | "Set the check-in radius to 250 m" (`policy_update(0, {"checkin_radius_m": 250})`; never "on that location"), or "move the pin onto the entrance" (`location_update`, free; the cached site keeps it), or `location_refine` ($0.10) |
| "I'm here now" took too long and the punch was refused | Window opened more than `checkin_slack_min` after the operator arrived | Have the AI `shift_update` the window to the real arrival time; raise the slack |
| Sub says they cleared but there is no check-in | They never punched, or the phone was elsewhere | `shift_status` says `scheduled` / `missed`, or shows a punch with a large distance; that is the answer. `sla_at_risk` lists anyone still not checked in |
| Forgot to check out | Shift still `checked_in` | Tell the AI the real time; the 15-minute check-out reminder is already on |
| Clear Proof not on the phone | Form not assigned to that site's event | "Attach the Clear Proof to Maple" (`form_assign(form_id, event_id=...)`). That installs the form for operators already scheduled on the event; do **not** cancel and recreate the shift (a recreate with the same `shift-clear-{clear_id}` key would replay the cancelled shift for 24 hours) |
| A sub typed a name or a gate code into the notes | Briefing slipped | The AI keeps it local and flags it; remind the sub. Codes stay on your computer, not the form |
| Same lot geocoded twice | Address typed differently ("Ave" vs "Avenue", "#12" vs "Ste 12") | Tell the AI it is the same site; it merges the `sites` rows and keeps one location |
| `shift_create` fails: date outside the event | The clear is on a different day than the event (events are same-day) | The AI opens a new one-day event for that site and date (free) and retries |
| Second clear on the same site the same storm is rejected | One non-cancelled clear per site per storm | "Open push 2" as a new storm, or cancel the first clear first |
| After photos have no date/time stamp on them | ZenSched does not watermark images | Turn on your camera's timestamp / GPS overlay before shooting if an insurer wants a readable stamp |
| Mileage deduction looks off | `irs_mileage_rate` still last year's | "Set the mileage rate to 0.72"; existing trips keep their snapshot |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI drafts "the lot was legally safe" | It is not following rule 1 | Remind it: report who punched, when, the distance, and the form. Do not assert coverage |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, form submissions and photos); SQLite is authoritative for contracts, sites, roster, storms, clears, mileage, billing, and payouts; each side stores only the other's IDs, plus a per-clear summary and the GPS stamps cached locally because submission reads are metered. The PII boundary is enforced by data placement (contact / access-code columns exist only locally, and the views compute the ZenSched-safe `zensched_location_name` / `zensched_event_title` strings) and by `SKILL.md` rules 1–2; there is no technical control stopping a misbehaving agent, so review the rules if you swap models.

**Data model decisions.**

- **Contracts → sites (places) → storms → clears.** The process-serving analog is `cases` → `serve_addresses` → `attempts`. The property-preservation analog is `clients` → `places` → `work_orders` → `visits`. Snow is a standing book of lots (`sites`, which *is* the address cache) under who pays (`contracts`), activated by a weather event (`storms`). `clears` is the driving table: one row, one shift, per site per storm.
- **One event per site per calendar day.** High-volume same-night clearing is the property-preservation shape, not a 60-day roll. `event_create` is `start_date = end_date = the clear date`; the clear stores `zensched_event_id`; `clears_planned` / `clears_today` expose a sibling clear's event on the same site and date so an ad hoc punch is one `shift_create`. A second push is a new storm and a new one-day event. The 60-day event cap is irrelevant because every event is one day.
- **One shift per site per event.** `CREATE UNIQUE INDEX idx_clears_one_per_site_storm ON clears(storm_id, site_id) WHERE status != 'cancelled'`. Cancelled rows drop out so a replacement can be inserted. A second pass the same night is a new storm, not a second clear on the first.
- **Planned windows vs ad hoc.** Both are `clears` rows; `is_adhoc` distinguishes them for `operator_activity`. A planned window has `scheduled_start` filled by trigger (`storm_date` + `default_clear_start`, 04:00). An ad hoc one has `scheduled_start` = now and gets a shift immediately — but only if that site has no planned clear on the open storm. The kit relies on `checkin_slack_min` (45) so both accept real-world punch times. There is no punch-without-shift path on the platform; this is the workaround.
- **`sites` is an address de-dup cache and the stop list.** `normalized_address` is `UNIQUE`; the agent normalizes and looks it up before any `location_create`. A hit reuses `zensched_location_id`, saving the $0.03 and preserving a hand-tuned pin. `street_name` (no house number) is stored so event titles read `Clear 2026-01-14 - Maple Ave`; `place_label` defaults to `Lot - Maple Ave`. `contract_id` is `ON DELETE RESTRICT`.
- **`storm_date` is the SLA morning.** Overnight work that starts at 22:00 on the 13th for a 07:00 clock on the 14th uses `storm_date = 2026-01-14` and a 04:00 default start, so the event and the deadline share a calendar day. If the owner schedules an evening start, `scheduled_start` may fall on the previous date and the agent opens that date's one-day event.
- **SLA clock is computed, not stored on the clear.** `sla_deadline_at` = `storm_date` + `COALESCE(site.sla_deadline, contract.sla_deadline, storm.sla_deadline, settings.default_sla_deadline, '07:00')`. `sla_at_risk` is planned clears with `checked_in_at IS NULL` whose deadline is within 60 minutes or already past. Completed clears never appear there, even if the punch was late.
- **`sites_uncleared`** lists every active site on a forecast/active storm that does not have a completed clear, including sites the agent never generated a row for (`needs_clear = 1`).
- **`storm_ref`.** Filled by trigger as `ST-{YYYY of storm_date}-{storm_id:04d}` when NULL.
- **Solo mode is the default; agency mode is additive.** The owner is invited as a worker and stored on `operators` with `is_owner = 1`; `settings.default_operator_id` points at that row and `fill_clear_defaults` assigns it when `operator_id` is NULL. Subs are further `operators` rows with `payout_type` `CHECK IN ('per_clear','percent')`.
- **`billable_total` is computed in a view, not stored.** Fee columns on `clears` (`fee`, `salt_fee`, `other_fee`) are snapshots filled by trigger from the contract's defaults. `completed` → fee + salt (if `salt_applied` ∈ `yes`,`pretreated`) + other; `skipped` / `cancelled` → `other_fee`; `planned` → 0. `receivables_by_contract`, the invoice `INSERT … SELECT`, `payouts_due`, and the `fill_payout_amount` trigger all read from `billable_clears`. `seasonal_fee` on the contract is informational and is never auto-billed.
- **Payouts key on a clear.** `payouts.clear_id` is `UNIQUE`. `fill_payout_amount` uses `payout_value` for `per_clear` and `billable_total × payout_value / 100` for `percent`; no `payout_type` leaves `amount` NULL and `payouts_due.needs_amount = 1`. Owner rows never appear.
- **`scheduled_start` is local wall-clock time without an offset** (`2026-01-14T04:00`, `CHECK`-constrained to reject a trailing offset or `Z`). NULL on insert is filled by trigger. `clears_planned` / `clears_today` / `clears_upcoming` emit `start_iso` and `end_iso` by appending `settings.timezone_offset`. Day-based views use `date('now', 'localtime')` because the SQLite MCP server runs on the owner's computer, whose clock is in the business's time zone.
- **`clears_today` includes completed.** The day's board shows what is done vs still out. `clears_upcoming` is planned only, next 7 days. `clears_planned` is the any-date source `clears_upcoming` reads.
- **No signature field on the form.** ZenSched replaces the Submit button with the signature pad when a form has a `signature` field, and the proof here is GPS + photos, not a wet signature. `after` is a required `photo` field (`max_images: 4`), so every submission bills $0.15.
- **GPS stamps are copied once.** `checked_in_at`, `checked_out_at`, `gps_verified`, `checkin_distance_m` are filled from `shift_status` when results are pulled, so "did Pat go" is answered locally. ZenSched remains the original.
- **`mileage`** snapshots `rate` from `settings.irs_mileage_rate` (seeded `0.70`, the 2025 IRS business rate; update yearly) and computes `deduction` by trigger. `clear_id` is nullable for salt reloads.
- `clears.zensched_shift_id`, `operators.zensched_worker_id`, `sites.normalized_address`, `storms.storm_ref`, `payouts.clear_id`, and `invoices.invoice_number` are `UNIQUE`. `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session. Deleting a contract is `RESTRICT` while sites exist; deleting a storm cascades to clears and payouts and sets `mileage.clear_id` NULL; deleting an operator sets `clears.operator_id` NULL and removes their payouts; `sites` is `ON DELETE RESTRICT` while clears reference it.

**Clear Proof form.** Created once with `form_create(title, fields_json, idempotency_key="form-clear-proof")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's form validator (`_validate_fields`): 5 fields, all valid, no signature. Every field carries an explicit `identifier` so submission `data` keys are stable (`surface`, `condition`, `after`, `salt_applied`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters); every option label here is ≤ 30 characters, so nothing truncates: `surface` ∈ `driveway`, `lot`, `walk`, `all`; `condition` ∈ `bare`, `packed`, `icy`; `salt_applied` ∈ `yes`, `no`, `pretreated`. Attaching is `form_assign(form_id, event_id=...)` per site-day event, once, before the first shift on that event.

**Idempotency keys.** Deterministic, derived from local IDs so a retried or re-run agent turn cannot duplicate:

- location: `loc-site-{site_id}`
- event: `event-site-{site_id}-{YYYYMMDD of the clear date}`
- shift: `shift-clear-{clear_id}` (an operator swap on the same clear appends `-2`)
- assignment: `assign-proof-{event_id}`
- cancel: `cancel-shift-{shift_id}`
- worker: `worker-{email}`
- form: `form-clear-proof`

ZenSched caches idempotent responses for 24 hours. The views emit `loc_idempotency_key`, `event_idempotency_key`, and `shift_idempotency_key` per row.

**Timestamps.** `shift_create` / `shift_update` take `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-01-14T04:00:00-06:00`), never `Z`. The views build these strings so the agent does not have to. `checked_in_at` / `checked_out_at` keep the offset ZenSched returns.

**Metered reads.** `form_submissions(form_id, event_id=...)` returns every submission on that site's event for that day; the agent skips submission ids already stored, which are free to skip because each submission bills once ever. `form_export` covers a storm in one call. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**Check-in policy.** The radius is enforced by `policy_update(0, '{"checkin_radius_m": N}')`, not by `location_create(checkin_radius_m=...)`, which is informational; with geofencing on, values under 100 m are raised to about 91 m. `checkin_slack_min` (0–240) is the early/late window around a shift and is the setting that makes planned and ad hoc clears practical; the kit uses 150 m / 45 min / 15-minute check-out reminder.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. `payouts_due` uses a window function (`SUM() OVER`), which needs SQLite ≥ 3.25 (2018); `better-sqlite3` bundles a current SQLite. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 62 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 9 tables, 14 views, and 12 triggers present; every view on an empty database; `sites.normalized_address`, `operators.zensched_worker_id`, `clears.zensched_shift_id`, and `payouts.clear_id` `UNIQUE`; the one-clear-per-site-per-storm partial unique (second insert rejected, cancelled row frees the slot); the `number_storm` trigger (`ST-YYYY-0001`, explicit ref kept) and `fill_storm_defaults` (`07:00` from settings); `fill_clear_defaults` (04:00 start, 180 minutes and the default operator, following a changed setting, explicit values kept, fee / salt snapshots from the contract, snapshot after a changed default); `clears_planned` / `clears_upcoming` (`start_iso` / `end_iso` with offset for `HH:MM` and `HH:MM:SS` inputs and 180/20-minute durations, the three idempotency keys, `needs_location` / `needs_event` / `needs_shift` before and after ids are set, sibling same-day event reuse, different-day `needs_event`, same-day `event_start_date` = `event_end_date`, titles `Clear {storm_date} - {street}` with no contact name or gate code, 7-day window, cancelled excluded, site SLA override 06:00 vs contract 07:00); `clears_today` including completed; `updated_at` triggers on contracts and storms; `needs_location` (unpinned site listed, pinned site dropped); `sites_uncleared` (planned listed, completed dropped, inactive site dropped, site with no clear row `needs_clear = 1`); `sla_at_risk` (planned + no check-in + deadline within 60 minutes or past, `deadline_passed`, completed excluded even when the punch was late); `storms_open` (active listed, closed dropped); `billable_clears` for completed (45), salted completed (60), pretreated (190), planned (0), skipped (`other_fee` 12), cancelled (`other_fee` 8), salt + other (215); `receivables_by_contract` totals and the drop-off after invoicing; invoice numbering, total, due date from the contract's terms, `line_items` JSON with no gate or contact; `invoices_outstanding` aging buckets `current` / `90+` / `60` / `30` with `days_past_due` and paid excluded; payouts for `per_clear` (40), `percent` (50% of 215 = 107.50), no split (NULL), the `UNIQUE` clear key, owner exclusion, `needs_amount`, `operator_total_due`, paid rows dropping out; `payouts_missing` for a per-clear sub; the mileage trigger (23.4 × 0.70 = 16.38, explicit rate kept, nullable clear, recompute on update) and `mileage_by_month`; `operator_activity` counts and `gps_verified_pct` (100.0) with the owner included; every `CHECK` (contract type, storm type, storm status, clear status, site surface, payout type, `storm_date` format, `sla_deadline` format, `scheduled_start` format with offset / `Z` / space / prose rejected, duration range 5–720, miles ≥ 0); foreign keys rejecting an unknown contract, site, and storm, `RESTRICT` on contracts and sites, `SET NULL` / cascade on operator delete, storm delete cascading clears and setting `mileage.clear_id` NULL with the site surviving, and invoice cascade on a siteless contract delete. The Clear Proof `fields_json` was validated against ZenSched's `_validate_fields` (5 fields, no signature, identifiers stable, option keys untruncated). 198 checks, all passing. Both load-and-exercise runs passed.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
