# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first storm, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

The business is **Northland Snow & Ice**, a solo operator (Sam Rivera) in Bloomington, Minnesota, Central time (`-06:00` in January), with one 1099 sub (Pat Okonkwo) paid $40 a clear. IDs and responses are illustrative. ZenSched IDs are integers. Watch what does **not** cross to ZenSched: customer contacts, gate codes, Sam's AP contact. ZenSched sees `Clear 2026-01-14 - Maple Ave`, a street address, a same-day event with that title, shifts, GPS punches, and Clear Proofs with surface / condition / after photos / salt.

The contracts are **Cedar Ridge HOA** (three driveways, $45 / $15 salt, SLA 07:00) and **Metro Plaza LLC** (one commercial lot, $150 / $40 salt, SLA 06:00). This kit does not talk to RealGreen or a municipal portal; Sam still emails the invoice.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Snow Service, timezone_offset = -06:00, state = NULL,
    default_operator_id = NULL, default_clear_minutes = 180,
    default_clear_start = 04:00, default_sla_deadline = 07:00,
    invoice_due_days = 30, invoice_prefix = INV, proof_form_id = NULL, irs_mileage_rate = 0.70
sqlite_query:   SELECT * FROM sla_at_risk;        → (none)
sqlite_query:   SELECT * FROM sites_uncleared;    → (none)
sqlite_query:   SELECT * FROM storms_open;        → (none)
sqlite_query:   SELECT * FROM clears_today;       → (none)
```

## Monday: "We're Northland Snow & Ice in Bloomington, Minnesota, Central time. I'm Sam Rivera, sam@northlandsnow.example, 612-555-0140. I've got one 1099, Pat Okonkwo, pat@northlandsnow.example, I pay them $40 a clear. Set us up."

```
sqlite_execute: UPDATE settings SET value = 'Northland Snow & Ice' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-06:00' WHERE key = 'timezone_offset';
sqlite_execute: UPDATE settings SET value = 'MN' WHERE key = 'state';
```

Agent (first metered call this session, rule 11):

> Saved. Since you're also an operator on the phone, I need to invite you to ZenSched as a worker so your clears show up in the app, and Pat too; that's $0.25 each, one time. If the account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
worker_invite:
  email: "sam@northlandsnow.example"
  first_name: "Sam"
  last_name: "Rivera"
  idempotency_key: "worker-sam@northlandsnow.example"
  → worker_id: 801, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO operators (operator_name, email, phone, zensched_worker_id, is_owner)
  VALUES ('Sam Rivera', 'sam@northlandsnow.example', '612-555-0140', 801, 1);
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '1' WHERE key = 'default_operator_id';

worker_invite:
  email: "pat@northlandsnow.example"
  first_name: "Pat"
  last_name: "Okonkwo"
  idempotency_key: "worker-pat@northlandsnow.example"
  → worker_id: 802, status: "invited"      ($0.25)

sqlite_execute:
  INSERT INTO operators (operator_name, email, zensched_worker_id, is_owner, payout_type, payout_value)
  VALUES ('Pat Okonkwo', 'pat@northlandsnow.example', 802, 0, 'per_clear', 40);
  → lastInsertRowid = 2
```

> You're both invited; install the app from the email. Next, the Clear Proof: it's free to create and every stop comes back with surface, condition, after photos, and salt. No signature pad on it, on purpose. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Clear Proof"
  idempotency_key: "form-clear-proof"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Clear proof", "identifier": "clear_proof_intro",
   "text": "Fill in before you leave the lot. Surface, condition, after photos, salt. Do not write customer names or gate codes here — those stay with the office."},
  {"type": "select", "label": "Surface", "identifier": "surface", "required": true,
   "options": ["Driveway", "Lot", "Walk", "All"]},
  {"type": "select", "label": "Condition", "identifier": "condition", "required": true,
   "options": ["Bare", "Packed", "Icy"]},
  {"type": "photo", "label": "After photos", "identifier": "after", "max_images": 4, "required": true},
  {"type": "select", "label": "Salt applied", "identifier": "salt_applied", "required": true,
   "options": ["Yes", "No", "Pretreated"]}
]
```

```
  → form_id: 601, fields: [ ...5 fields echoed with identifiers surface, condition, after, salt_applied... ]

sqlite_execute: UPDATE settings SET value = '601' WHERE key = 'proof_form_id';
```

> Clear Proof created; I'll attach it to every stop automatically. One thing to tell Pat: no customer names or gate codes in the form. Now the check-in policy: I'd like a 150 m radius (lots are large), a 45-minute early/late window so you can punch when you actually get there (and so an "I'm here now" window I open while you're parking still takes the punch), and a check-out reminder 15 minutes after a window ends. OK?

Owner: *"yes"*

```
policy_update:
  policy_id: 0
  settings_json: "{\"checkin_radius_m\": 150, \"checkin_slack_min\": 45, \"checkout_reminder_min_after\": 15}"
  → policy_id: 0, updated: [ "checkin_radius_m", "checkin_slack_min", "checkout_reminder_min_after" ]
```

## Monday afternoon: load the book

> *Cedar Ridge HOA, $45 a push, $15 salt, SLA 7am, net 30. Contact Dana at the office, billing hoa@cedarridge.example. Sites: 4100 Maple Ave, 880 Oak Circle, 12 Pine Ct, Bloomington MN 55431. Maple gate 4412 north side. Metro Plaza LLC, $150 a push, $40 salt, SLA 6am. Site: 5500 France Ave S, Edina MN 55435, commercial lot, plow from the north entrance.*

```
sqlite_execute:
  INSERT INTO contracts (contract_name, contract_type, contact_name, billing_email, payment_terms_days, per_clear_fee, salt_fee, sla_deadline)
  VALUES ('Cedar Ridge HOA', 'hoa', 'Dana', 'hoa@cedarridge.example', 30, 45, 15, '07:00');
  → 1
sqlite_execute:
  INSERT INTO contracts (contract_name, contract_type, billing_email, payment_terms_days, per_clear_fee, salt_fee, sla_deadline)
  VALUES ('Metro Plaza LLC', 'commercial', 'ap@metroplaza.example', 30, 150, 40, '06:00');
  → 2

sqlite_execute:
  INSERT INTO sites (contract_id, normalized_address, address, city, state, zip, street_name, place_label, surface, access_notes)
  VALUES (1, '4100 maple ave bloomington mn 55431', '4100 Maple Ave', 'Bloomington', 'MN', '55431',
          'Maple Ave', 'Driveway - Maple Ave', 'driveway', 'Gate 4412, north side.');
  → 1
sqlite_execute:
  INSERT INTO sites (contract_id, normalized_address, address, city, state, zip, street_name, place_label, surface)
  VALUES (1, '880 oak circle bloomington mn 55431', '880 Oak Circle', 'Bloomington', 'MN', '55431',
          'Oak Circle', 'Driveway - Oak Circle', 'driveway');
  → 2
sqlite_execute:
  INSERT INTO sites (contract_id, normalized_address, address, city, state, zip, street_name, place_label, surface)
  VALUES (1, '12 pine ct bloomington mn 55431', '12 Pine Ct', 'Bloomington', 'MN', '55431',
          'Pine Ct', 'Driveway - Pine Ct', 'driveway');
  → 3
sqlite_execute:
  INSERT INTO sites (contract_id, normalized_address, address, city, state, zip, street_name, place_label, surface, sla_deadline, access_notes)
  VALUES (2, '5500 france ave s edina mn 55435', '5500 France Ave S', 'Edina', 'MN', '55435',
          'France Ave S', 'Lot - France Ave S', 'lot', '06:00', 'North entrance.');
  → 4
```

Dana, gate 4412, and "north entrance" stay local. No ZenSched calls yet — pins happen when the storm opens.

> Booked **2 contracts, 4 sites**. Cedar Ridge $45 / $15 salt, 07:00. Metro Plaza $150 / $40 salt, 06:00. I'll pin them on the first storm.

## Tuesday 9pm: "Storm tonight, 4–8 inches. SLA 7am. Put every site on the phones, first stop 4:00."

```
sqlite_execute:
  INSERT INTO storms (storm_name, storm_date, storm_type, sla_deadline)
  VALUES ('Jan 14 snow 4-8in', '2026-01-14', 'snow', '07:00');
  → 1
  (triggers fill: storm_ref ST-2026-0001, sla_deadline 07:00)

sqlite_execute:
  INSERT INTO clears (storm_id, site_id) SELECT 1, site_id FROM sites WHERE is_active = 1;
  → 4 rows (clear_id 1..4)
  (trigger: scheduled_start 2026-01-14T04:00, duration 180, operator 1,
   fee/salt from each contract)

sqlite_query: SELECT clear_id, zensched_event_title, street_address, sla_deadline, needs_location, needs_event, needs_shift,
                     event_start_date, event_end_date, start_iso, end_iso, loc_idempotency_key, event_idempotency_key, shift_idempotency_key
              FROM clears_planned ORDER BY scheduled_start, street_address;
  → 1 | Clear 2026-01-14 - Maple Ave    | 4100 Maple Ave, Bloomington, MN 55431 | 07:00 | 1 | 1 | 1 | 2026-01-14 | 2026-01-14 | 2026-01-14T04:00:00-06:00 .. 07:00 | loc-site-1 | event-site-1-20260114 | shift-clear-1
    2 | Clear 2026-01-14 - Oak Circle   | 880 Oak Circle, Bloomington, MN 55431  | 07:00 | 1 | 1 | 1 | 2026-01-14 | 2026-01-14 | 2026-01-14T04:00:00-06:00 .. 07:00 | loc-site-2 | event-site-2-20260114 | shift-clear-2
    3 | Clear 2026-01-14 - Pine Ct      | 12 Pine Ct, Bloomington, MN 55431      | 07:00 | 1 | 1 | 1 | 2026-01-14 | 2026-01-14 | 2026-01-14T04:00:00-06:00 .. 07:00 | loc-site-3 | event-site-3-20260114 | shift-clear-3
    4 | Clear 2026-01-14 - France Ave S | 5500 France Ave S, Edina, MN 55435     | 06:00 | 1 | 1 | 1 | 2026-01-14 | 2026-01-14 | 2026-01-14T04:00:00-06:00 .. 07:00 | loc-site-4 | event-site-4-20260114 | shift-clear-4
```

France Ave inherits the site/contract 06:00 SLA. Gate 4412 is not in `zensched_event_title` or `zensched_location_name`.

> Putting this on ZenSched costs $0.03 per new address to geocode (four here); each clear then costs $0.35 in GPS check-in/out and reading the Clear Proof with its photos. OK to proceed for this and later storms?

Owner: *"yes"*

```
location_create:
  name: "Driveway - Maple Ave"
  street_address: "4100 Maple Ave, Bloomington, MN 55431"
  checkin_radius_m: 150
  idempotency_key: "loc-site-1"
  → location_id: 9301, lat: 44.8401, lng: -93.3290, pin_quality: "street",
    billing: { meter: "geocode", units: 1, price: 0.03 }
sqlite_execute: UPDATE sites SET zensched_location_id = 9301 WHERE site_id = 1;

location_create: name "Driveway - Oak Circle", street_address "880 Oak Circle, Bloomington, MN 55431", checkin_radius_m 150, idempotency_key "loc-site-2"   → 9302   ($0.03)
sqlite_execute: UPDATE sites SET zensched_location_id = 9302 WHERE site_id = 2;
location_create: name "Driveway - Pine Ct", street_address "12 Pine Ct, Bloomington, MN 55431", checkin_radius_m 150, idempotency_key "loc-site-3"         → 9303   ($0.03)
sqlite_execute: UPDATE sites SET zensched_location_id = 9303 WHERE site_id = 3;
location_create: name "Lot - France Ave S", street_address "5500 France Ave S, Edina, MN 55435", checkin_radius_m 150, idempotency_key "loc-site-4"       → 9304   ($0.03)
sqlite_execute: UPDATE sites SET zensched_location_id = 9304 WHERE site_id = 4;

event_create:
  location_id: 9301
  title: "Clear 2026-01-14 - Maple Ave"
  start_date: "2026-01-14"
  end_date:   "2026-01-14"
  idempotency_key: "event-site-1-20260114"
  → event_id: 7401
form_assign:
  form_id: 601
  event_id: 7401
  idempotency_key: "assign-proof-7401"
  → status: "assigned", form_id: 601, event_id: 7401, policy_id: 0
sqlite_execute: UPDATE clears SET zensched_event_id = 7401 WHERE clear_id = 1;

event_create: location 9302, title "Clear 2026-01-14 - Oak Circle",   start_date "2026-01-14", end_date "2026-01-14", idempotency_key "event-site-2-20260114" → 7402
form_assign:  form_id 601, event_id 7402, idempotency_key "assign-proof-7402"
sqlite_execute: UPDATE clears SET zensched_event_id = 7402 WHERE clear_id = 2;
event_create: location 9303, title "Clear 2026-01-14 - Pine Ct",      start_date "2026-01-14", end_date "2026-01-14", idempotency_key "event-site-3-20260114" → 7403
form_assign:  form_id 601, event_id 7403, idempotency_key "assign-proof-7403"
sqlite_execute: UPDATE clears SET zensched_event_id = 7403 WHERE clear_id = 3;
event_create: location 9304, title "Clear 2026-01-14 - France Ave S", start_date "2026-01-14", end_date "2026-01-14", idempotency_key "event-site-4-20260114" → 7404
form_assign:  form_id 601, event_id 7404, idempotency_key "assign-proof-7404"
sqlite_execute: UPDATE clears SET zensched_event_id = 7404 WHERE clear_id = 4;

shift_create:
  event_id: 7401
  worker_id: 801
  start: "2026-01-14T04:00:00-06:00"
  end:   "2026-01-14T07:00:00-06:00"
  idempotency_key: "shift-clear-1"
  → shift_id: 90001, status: "scheduled", forms_installed: [601]
shift_create: event 7402, worker 801, "2026-01-14T04:00:00-06:00" .. "2026-01-14T07:00:00-06:00", idempotency_key "shift-clear-2" → 90002
shift_create: event 7403, worker 801, "2026-01-14T04:00:00-06:00" .. "2026-01-14T07:00:00-06:00", idempotency_key "shift-clear-3" → 90003
shift_create: event 7404, worker 801, "2026-01-14T04:00:00-06:00" .. "2026-01-14T07:00:00-06:00", idempotency_key "shift-clear-4" → 90004

sqlite_execute: UPDATE clears SET zensched_shift_id = 90001 WHERE clear_id = 1;
sqlite_execute: UPDATE clears SET zensched_shift_id = 90002 WHERE clear_id = 2;
sqlite_execute: UPDATE clears SET zensched_shift_id = 90003 WHERE clear_id = 3;
sqlite_execute: UPDATE clears SET zensched_shift_id = 90004 WHERE clear_id = 4;
```

Nothing about Dana, gate 4412, or the north entrance is in `name`, `title`, or `notes`. Each site has its own same-day event.

> Opened **ST-2026-0001** for Jan 14, SLA 07:00 (Metro Plaza 06:00). Maple, Oak, Pine, and France Ave are pinned. Windows on the phones 4:00–7:00. Cedar Ridge $45 / $15 salt, Metro Plaza $150 / $40 salt. Gate codes are only on your computer; ZenSched sees "Clear 2026-01-14 - Maple Ave".

## Wednesday 4:08–5:40: three planned stops

4:08, outside 4100 Maple Ave: Sam taps **Check in** (GPS: 12 m from the pin, verified, $0.10). Plows the driveway, salts. Three after photos. Opens **Clear Proof**: Surface = Driveway; Condition = Bare; After = 3; Salt applied = Yes. Submits. **Check out** 4:22 ($0.10).

4:31 at 880 Oak Circle: Check in (9 m, verified). Packed at the apron, salted. Two after photos. Clear Proof: Driveway; Packed; Salt = Yes. Check out 4:44.

5:02 at 12 Pine Ct: Check in (14 m, verified). Bare, no salt (HOA asked plow-only). Two after photos. Clear Proof: Driveway; Bare; Salt = No. Check out 5:11.

## Wednesday 5:18: "I'm at France Ave now, sending Pat."

France already has a planned window 4:00–7:00 for Sam. The owner wants Pat on it.

```
sqlite_query:
  SELECT c.clear_id, c.zensched_event_id, c.zensched_shift_id, c.operator_id
  FROM clears c JOIN sites si ON si.site_id = c.site_id
  WHERE si.street_name LIKE 'France%' AND c.status = 'planned';
  → clear 4 | event 7404 | shift 90004 | operator 1
```

Planned window is still open, inside the 45-minute slack — but the owner asked for Pat, so this is an operator swap, not a second clear.

```
shift_cancel: shift_id 90004, reason "cancelled", idempotency_key "cancel-shift-90004"
sqlite_execute: UPDATE clears SET operator_id = 2, zensched_shift_id = NULL WHERE clear_id = 4;

shift_create:
  event_id: 7404
  worker_id: 802
  start: "2026-01-14T05:18:00-06:00"
  end:   "2026-01-14T06:00:00-06:00"
  idempotency_key: "shift-clear-4-2"
  → shift_id: 90005, status: "scheduled", forms_installed: [601]
sqlite_execute: UPDATE clears SET zensched_shift_id = 90005, scheduled_start = '2026-01-14T05:18' WHERE clear_id = 4;
```

> Window's on Pat's phone: 5:18–6:00 at France Ave. Metro Plaza's SLA is 06:00. He can check in now.

Pat checks in at 5:20 (22 m, verified). Lot, bare, pretreated earlier plus a salt pass. Four after photos. Clear Proof: Lot; Bare; Salt = Pretreated. Check out 5:41.

(If France had had **no** planned window, the agent would have inserted an `is_adhoc` clear, reused event 7404, and `shift_create`'d with `scheduled_start` = now — the same "I'm here now" path as property-preservation.)

## Wednesday 6:50: "What's at risk?"

Pine, Maple, Oak, and France are already punched. If Pine had never checked in:

```
sqlite_query: SELECT * FROM sla_at_risk;
  → (none — every planned clear has a check-in, or would list Pine with minutes_to_deadline ~10 and deadline_passed 0)
sqlite_query: SELECT * FROM sites_uncleared;
  → (none — all four completes are still being pulled, but if unlogged they still show as planned until results are written)
```

> Nothing at risk. All four sites have a check-in before their deadline. Say "log this storm" and I'll pull the proofs.

## Wednesday morning: "Log this storm."

```
shift_list: date_from "2026-01-14", date_to "2026-01-14", status "checked_out"
  → [ { shift_id: 90001, worker_id: 801, event_id: 7401, actual_in: "2026-01-14T04:08:10-06:00", actual_out: "2026-01-14T04:22:40-06:00" },
      { shift_id: 90002, worker_id: 801, event_id: 7402, actual_in: "2026-01-14T04:31:05-06:00", actual_out: "2026-01-14T04:44:20-06:00" },
      { shift_id: 90003, worker_id: 801, event_id: 7403, actual_in: "2026-01-14T05:02:00-06:00", actual_out: "2026-01-14T05:11:15-06:00" },
      { shift_id: 90005, worker_id: 802, event_id: 7404, actual_in: "2026-01-14T05:20:00-06:00", actual_out: "2026-01-14T05:41:30-06:00" } ]
(free)

shift_status: 90001 → punches: [ { type: "in", gps_verified: true, distance_from_site_m: 12 }, { type: "out", gps_verified: true, distance_from_site_m: 11 } ]
shift_status: 90002 → in verified 9 m
shift_status: 90003 → in verified 14 m
shift_status: 90005 → in verified 22 m
(free)
```

> Reading the four Clear Proofs with their after photos is about $0.60. Each bills once; after this I answer from the local record. OK?

Owner: *"go"*

```
form_submissions:
  form_id: 601
  event_id: 7401
  limit: 20
  → submissions: [
      { submission_id: 5501, worker_id: 801, event_id: 7401, submitted_at: "2026-01-14 04:21:40",
        data: { surface: "driveway", condition: "bare", salt_applied: "yes" },
        media: [ { field: "after", cdn_url: "https://cdn.zensched.com/m/.../a1.jpg" }, ... 3 after ... ] }
    ], count: 1, billing: { meter: "form_media", units: 1, price: 0.15 }

form_submissions: form_id 601, event_id 7402, limit 20      ($0.15)
  → [ { submission_id: 5502, data: { surface: "driveway", condition: "packed", salt_applied: "yes" }, media: [ 2 after ] } ]
form_submissions: form_id 601, event_id 7403, limit 20      ($0.15)
  → [ { submission_id: 5503, data: { surface: "driveway", condition: "bare", salt_applied: "no" }, media: [ 2 after ] } ]
form_submissions: form_id 601, event_id 7404, limit 20      ($0.15)
  → [ { submission_id: 5504, data: { surface: "lot", condition: "bare", salt_applied: "pretreated" }, media: [ 4 after ] } ]

sqlite_execute:
  UPDATE clears SET status = 'completed', surface = 'driveway', condition = 'bare', salt_applied = 'yes',
         photo_count = 3, report_dc_id = 5501,
         checked_in_at = '2026-01-14T04:08:10-06:00', checked_out_at = '2026-01-14T04:22:40-06:00', gps_verified = 1, checkin_distance_m = 12
  WHERE clear_id = 1;
sqlite_execute:
  UPDATE clears SET status = 'completed', surface = 'driveway', condition = 'packed', salt_applied = 'yes',
         photo_count = 2, report_dc_id = 5502,
         checked_in_at = '2026-01-14T04:31:05-06:00', checked_out_at = '2026-01-14T04:44:20-06:00', gps_verified = 1, checkin_distance_m = 9
  WHERE clear_id = 2;
sqlite_execute:
  UPDATE clears SET status = 'completed', surface = 'driveway', condition = 'bare', salt_applied = 'no',
         photo_count = 2, report_dc_id = 5503,
         checked_in_at = '2026-01-14T05:02:00-06:00', checked_out_at = '2026-01-14T05:11:15-06:00', gps_verified = 1, checkin_distance_m = 14
  WHERE clear_id = 3;
sqlite_execute:
  UPDATE clears SET status = 'completed', surface = 'lot', condition = 'bare', salt_applied = 'pretreated',
         photo_count = 4, report_dc_id = 5504,
         checked_in_at = '2026-01-14T05:20:00-06:00', checked_out_at = '2026-01-14T05:41:30-06:00', gps_verified = 1, checkin_distance_m = 22
  WHERE clear_id = 4;

sqlite_execute: UPDATE storms SET status = 'closed' WHERE storm_id = 1;

sqlite_query:   SELECT * FROM payouts_missing;
  → Pat Okonkwo | per_clear 40 | ST-2026-0001 | France Ave S | visit 4 | 2026-01-14 | bare
sqlite_execute: INSERT INTO payouts (operator_id, clear_id) VALUES (2, 4);      (trigger: amount 40)
```

> Logged four clears, storm closed.
> - **Maple Ave** 4:08–4:22, GPS-verified 12 m: driveway, **bare**, salted, 3 photos. 2h52 before 07:00. $45 + $15.
> - **Oak Circle** 4:31–4:44, verified 9 m: driveway, **packed**, salted, 2 photos. $45 + $15.
> - **Pine Ct** 5:02–5:11, verified 14 m: driveway, **bare**, no salt, 2 photos. $45.
> - **France Ave S** (Pat) 5:20–5:41, verified 22 m: lot, **bare**, pretreated, 4 photos. 40 minutes before the 06:00 SLA. $150 + $40. Pat is owed $40.
>
> Cedar Ridge $165 receivable. Metro Plaza $190. I'll draft the invoices when you say. These times and distances are your record — I will not say the lots were legally safe.

## Wednesday: "Invoice everyone, and what do I owe Pat."

```
sqlite_query: SELECT * FROM payouts_due;
  → Pat Okonkwo | per_clear 40 | ST-2026-0001 | France Ave S | 40.00 | operator_total_due 40.00

sqlite_query: SELECT * FROM receivables_by_contract;
  → Cedar Ridge HOA | hoa | 3 clears | 165.00
    Metro Plaza LLC | commercial | 1 clear | 190.00

sqlite_execute:
  INSERT INTO invoices (contract_id, invoice_date, due_date, total_amount, line_items)
  SELECT b.contract_id, date('now', 'localtime'),
         date('now', 'localtime', '+' || (SELECT payment_terms_days FROM contracts WHERE contract_id = 1) || ' days'),
         SUM(b.billable_total),
         json_group_array(json_object('storm_ref', b.storm_ref, 'storm_date', b.storm_date, 'street', b.street_name,
                                      'surface', b.surface, 'condition', b.condition, 'salt_applied', b.salt_applied,
                                      'status', b.status, 'fee', b.fee, 'salt_fee', b.salt_fee_billed,
                                      'other_fee', b.other_fee, 'billable', b.billable_total))
  FROM billable_clears b WHERE b.invoiced = 0 AND b.contract_id = 1 AND b.billable_total > 0 GROUP BY b.contract_id;
sqlite_execute: UPDATE clears SET invoiced = 1 WHERE invoiced = 0 AND site_id IN (SELECT site_id FROM sites WHERE contract_id = 1) AND status IN ('completed', 'skipped', 'cancelled');
  → INV-2026-0001 | 165.00

(same pair of statements for contract_id = 2 → INV-2026-0002 | 190.00)
```

> Pat: 1 clear on France Ave (bare / pretreated), **$40** due. Say "paid Pat" and I'll mark it.
>
> Two invoices, ready to paste (not into a portal this kit does not have):
>
> ```
> Northland Snow & Ice
> Invoice INV-2026-0001
> To: Cedar Ridge HOA (hoa@cedarridge.example)
> Date: Jan 14, 2026    Due: Feb 13, 2026 (net 30)
>
>   ST-2026-0001  Maple Ave    Driveway  Bare    Salted      $60.00
>   ST-2026-0001  Oak Circle   Driveway  Packed  Salted      $60.00
>   ST-2026-0001  Pine Ct      Driveway  Bare    No salt     $45.00
>
> Total due: $165.00
> ```
>
> ```
> Northland Snow & Ice
> Invoice INV-2026-0002
> To: Metro Plaza LLC (ap@metroplaza.example)
> Date: Jan 14, 2026    Due: Feb 13, 2026 (net 30)
>
>   ST-2026-0001  France Ave S  Lot  Bare  Pretreated  $190.00
>
> Total due: $190.00
> ```
>
> No gate codes. GPS-verified at each pin; photo submissions 5501–5504 on ZenSched. Say "sent" when they're out.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Dana, gate 4412, north entrance | SQLite **only** (`contracts.contact_name`, `sites.access_notes`) | Contacts and access codes never reach ZenSched |
| Cedar Ridge / Metro Plaza: terms, billing email, fees, SLA | SQLite (`contracts`) | Receivables |
| Each site address, normalized, with its ZenSched location id | SQLite (`sites`) | De-dup cache; the next storm skips the $0.03 geocode and keeps its pin |
| `Driveway - Maple Ave` / `Lot - France Ave S` and their street addresses and GPS pins | ZenSched (ID in `sites`) | Needed for geofenced check-in; labels carry the street, no names |
| One same-day event per site (`Clear 2026-01-14 - Maple Ave`) | ZenSched (ID in `clears`) | High-volume same-night; a second push would be a new storm |
| One shift per clear (04:00–07:00, or the ad hoc / swap window) | ZenSched (ID in `clears`) | The thing a GPS punch attaches to; never copied |
| Sam and Pat as ZenSched workers | ZenSched (IDs in `operators`) | Solo owner is also an operator; 1099 gets the same app |
| GPS punches, arrival time, distance from pin | ZenSched (originals); stamps copied once to `clears.checked_in_at` / `checked_out_at` / `gps_verified` / `checkin_distance_m` | Proof each clear happened where and when, and whether it beat the SLA |
| The Clear Proof form | ZenSched (ID in `settings`) | Installed on the phone per shift; no signature field |
| Four Clear Proof submissions, after photos | ZenSched (originals); surface, condition, salt, photo count, `report_dc_id` in `clears` | Read once (metered $0.15 each = $0.60); images stay on ZenSched |
| Check-in policy (150 m radius, 45 min slack, 15 min check-out reminder) | ZenSched (policy 0) | Radius and slack are enforced by the policy, not per location |
| Fees per clear, $165 / $190 invoices, aging | SQLite (`clears`, `billable_clears`, `invoices`, `invoices_outstanding`) | Receivables |
| Pat's $40 payout | SQLite (`payouts`) | Per clear, not hourly; owner's own clears never generate payouts |
