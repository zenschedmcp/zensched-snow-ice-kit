# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "This is not RealGreen, and it is not a lawyer" section of `README.md`. Short version: this kit puts every lot on the phone, GPS-stamps the clear, and captures after photos before 7am. It does **not** know municipal ordinances, and it does not write a slip-and-fall defense. Gate codes stay on your computer; ZenSched sees a street address and a title like `Clear 2026-01-14 - Maple Ave`.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\snow-ops` (Windows) or `/Users/yourname/snow-ops` (Mac). Note the full path. It will hold customer contacts and gate codes, so keep it on an encrypted, backed-up disk, not a shared folder.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\snow-ops\\snow-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "My Snow Service". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my snow-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> We're Northland Snow & Ice in Bloomington, Minnesota, Central time. It's me, Sam Rivera, sam@example.com. Set me up.

The AI saves your settings, invites **you** to ZenSched as a worker ($0.25, once; you are the operator on the phone), calls `form_create` once (free) to build the Clear Proof you fill in at every lot (surface, condition, after photos, salt; no signature pad), stores the form id so every stop gets it, and sets the check-in policy: 150 m radius (lots are large), **45 minutes of slack** so an early, late, or on-the-spot punch is accepted, and a check-out reminder 15 minutes after the window. Install the app from the invitation email ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)).

If you work mall or campus lots: "Set the check-in radius to 250 m."

Agency mode: "Add my sub Pat Okonkwo, pat@example.com, I pay them $40 a clear" for each 1099 operator you dispatch. Brief every operator once: do not type customer names or gate codes into the Clear Proof.

## 6. Load contracts and sites (once per season)

> Cedar Ridge HOA, $45 a push, $15 salt, SLA 7am, net 30. Sites: 4100 Maple Ave, 880 Oak Circle, 12 Pine Ct, Bloomington MN 55431. Metro Plaza LLC, $150 a push, $40 salt, SLA 6am. Site: 5500 France Ave S, Edina MN 55435, commercial lot, north entrance.

The AI adds the contracts, caches each address, and does **not** geocode yet. Pins happen when you open the first storm.

## 7. Open a storm

> Storm tonight, 4–8 inches. SLA 7am. Put every site on the phones, first stop 4:00.

Behind the scenes the AI inserts the storm (`ST-2026-0001`, storm date = the SLA morning), generates one clear per active site, calls `location_create` for any unpinned address ($0.03 each, may trigger the $5 activation deposit the first time), opens **one same-day event per site** titled `Clear 2026-01-14 - Maple Ave`, attaches the Clear Proof with `form_assign`, and puts a window on each phone with `shift_create`.

## 8. The clear

Your phone shows the window with the address. At the lot, **Check in** (GPS-verified). Plow / salt. Open the **Clear Proof** on the shift: surface (Driveway / Lot / Walk / All), condition (Bare / Packed / Icy), after photos (required, up to 4), salt applied (Yes / No / Pretreated). Submit. **Check out**.

## 9. "I'm at this lot"

You decide to hit a site that was not on the planned list, or you arrived before the window:

> I'm at France Ave now.

The AI opens a 30-minute window on your phone starting now (one `shift_create` on that site's event for today; a few seconds) — or tells you the planned window already accepts the punch — and replies in one line. Check in, clear, record, check out. For a sub: "Pat at Maple now."

## 10. What's left / who missed 7am

> What's uncleared?

`sites_uncleared` — every active site on an open storm without a completed clear.

> What's at risk?

`sla_at_risk` — planned clears that have **not checked in**, with the deadline within 60 minutes or already past.

## 11. Log the results

> Log this storm.

The AI pulls the GPS-verified check-in and check-out for each window (free), reads each Clear Proof once (metered, so it tells you the cost first, $0.15 each because after photos are required), updates every clear with surface, condition, salt, photo count, and times, and tells you who beat 07:00. If a sub is paid per clear, the payout row is created now.

> Did Pat actually hit Maple this morning?

Answered from ZenSched's punch record: checked in 4:41 am, 14 m from the pin, out 4:55, lot / bare / salted, three after photos. Or: no check-in.

## 12. Money

> Invoice Cedar Ridge.

A plain-text invoice under their terms with one line per clear (storm ref, street, surface, condition, salt, fee). Nothing about gate codes.

> Who owes me money?

Open invoices aged current / 30 / 60 / 90+ days past due.

> Cedar Ridge paid INV-2026-0001.

Marks it paid.

Agency: "What do I owe Pat?" lists unpaid clears and the total; "paid Pat" marks them.

## What next

- `README.md` for the full explanation, the liability / photo boundaries, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
