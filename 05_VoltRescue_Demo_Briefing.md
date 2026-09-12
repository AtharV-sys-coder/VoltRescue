# VoltRescue — Demonstration Briefing

**Meeting:** Thursday 10 September 2026, 12:00 Irish time
**Audience:** Mr. Menelick Erick, Chief Operating Officer, TCC Ireland · plus academic supervisor
**Subject:** Phase 1 Proof of Concept — live demonstration and Phase 2 approval
**Prepared:** 9 September 2026

---

## How to use this document

Sections 1–4 are what you **do** before and during the meeting. Section 5 is the numbers you should be able to quote without looking. Sections 6–8 are the questions you will be asked, with answers written the way you should say them. Section 9 is what to do if something breaks.

Read section 9 first thing in the morning. Read section 5 twice.

---



## 1. Pre-meeting checklist

Do this **30 minutes before** the call, not five.


| #   | Step                                                | Command / action                                           | Confirms                                                                                   |
| --- | --------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| 1   | Start the server                                    | Right-click `start.ps1` → Run with PowerShell              | Console prints the address                                                                 |
| 2   | Note the address it prints                          | Currently `http://127.0.0.1:8815/`                         | The port can change; trust the console, not your memory                                    |
| 3   | **Run the pre-flight**                              | `powershell -ExecutionPolicy Bypass -File .\demo-prep.ps1` | Runs both test suites, then loads clean demo data, then prints **READY FOR DEMONSTRATION** |
| 4   | Open the app and log in as admin                    | `admin@voltrescue.local` / `VoltRescue!23`                 | Dashboard shows real KPI numbers                                                           |
| 5   | Log out again                                       |                                                            | You want to start the demo from the login screen                                           |
| 6   | Open four browser tabs                              | Login screen in each                                       | Lets you switch roles instantly instead of logging in and out on camera                    |
| 7   | Close everything else                               | Especially anything with notifications                     | Nothing embarrassing pops up while sharing                                                 |
| 8   | Have this document open on a second screen or phone |                                                            | Not on the shared screen                                                                   |


`demo-prep.ps1` takes about 45 seconds and does steps 3–4 of the old manual routine in the correct order. That order matters: **the test suites must run before the data reset, never after**, because the tests create records of their own and would put test rows back onto the dashboard. The script enforces this.

If you only want to reload the data — say you demoed once and want to go again — run `demo-reset.ps1` on its own. It takes 30 seconds.

### The four demo accounts


| Role          | Email                        | Name shown               | Purpose in the demo            |
| ------------- | ---------------------------- | ------------------------ | ------------------------------ |
| Citizen       | `citizen@voltrescue.local`   | Amina Hassan             | Submits the request            |
| Collector     | `collector@voltrescue.local` | Juma Mwangi              | Accepts, collects, hands over  |
| Recycler      | `recycler@voltrescue.local`  | GreenCycle Recycling Ltd | Receives, validates, completes |
| Administrator | `admin@voltrescue.local`     | Menelick Erick           | Oversees everything            |


Password for all four: `VoltRescue!23`

> The administrator account is named after him. Mention it lightly if it comes up — it shows the roles are real accounts, not hard-coded screens.

---



## 2. The demonstration script (18 minutes)

The story is **one battery's journey, followed by the control room**. Resist the urge to show features in the order they were built. Show them in the order the business experiences them.

### Opening — 90 seconds, no screen share yet

> "VoltRescue solves a chain-of-custody problem. When a household in Dar es Salaam wants to dispose of a car battery, there is currently no traceable route from that household to a licensed recycler. Batteries end up in informal scrap channels, the lead is recovered unsafely, and nobody can prove where anything went.
>
> What I am about to show you is a working system where every battery has a tracked custody chain from the resident's doorstep to the recycler's gate, with an audit record at every handover. It is a Phase 1 proof of concept — I will be equally clear about what it does not yet do."

Then share the screen.

### Act 1 — The resident (3 minutes)

1. Log in as **Amina Hassan** (citizen).
2. Submit a new request. Use a real-sounding address — **"Kariakoo Market, Ilala"**.
  - Pick a battery type and quantity.
  - **Show the map.** Click *Use my location*, then drag the pin. Say: *"The exact coordinates are captured, because 'near the market' is not an address a driver can navigate to."*
3. Submit. Show the confirmation and the status.
4. Point at the status: `PENDING_ASSIGNMENT`. Say: *"The system moved it there itself. The resident does not choose a status — the workflow does."*

**The line to land:** *"Nothing here is stored in the browser. That request is now a row in the database, and it exists identically for the collector, the recycler and the control room."*

### Act 2 — The control room assigns (2 minutes)

1. Switch to the **admin** tab. Show the dashboard.
2. Point at the KPI cards, then the new request sitting in *Pending assignment*.
3. Show the **collector workload** panel. Say: *"Before I assign this, I can see who is already carrying work."*
4. Assign it to **Juma Mwangi**.



### Act 3 — The collector (4 minutes)

1. Switch to the **collector** tab. The job is there.
2. **Accept** it. Then walk the statuses: *En route* → *Collected* → *In my custody*.
3. Upload an evidence photo. Any image will do. Say: *"Photographic evidence at the point of collection. Stamped with who uploaded it and when."*
4. Show the navigation link. Say: *"That opens Google Maps on the driver's phone with the resident's exact pin."*
5. **Hand over** to GreenCycle Recycling Ltd.

**The line to land:** *"Custody has just legally changed hands, and the system recorded it. That transfer record is the thing that makes the chain auditable."*

### Act 4 — The recycler (2 minutes)

1. Switch to the **recycler** tab. The inbound load is waiting.
2. **Confirm receipt** → **Validate** → **Complete**.



### Act 5 — The proof (4 minutes)

This is the part that wins the meeting. Do not rush it.

1. Go back to the **citizen** tab and open the request you just created.
2. Show the **full timeline** — every stage, the time, and the name of the person responsible.

> *"Twelve stages. Every one of them has a timestamp and a named actor. If a load is ever disputed, this is the record."*

1. Switch to **admin** → **Audit logs**. Show the same events from the compliance side.
2. Show the **notification statistics** line and click **Process notification queue**.

> *"Every status change generates an SMS and a WhatsApp message to the affected parties. In this pilot they are simulated, because we have no provider account yet — the system tells you honestly that it is in sandbox mode rather than pretending a message was delivered."*

1. Click **Export CSV**. Open it in Excel.

> *"Operations reporting on day one."*



### Act 6 — When things go wrong (2 minutes)

Most demos only show the happy path. Showing the failure path is what makes an operator trust you.

1. On the admin dashboard, find the `NO_SHOW` request (Kigamboni Ferry, Temeke).
2. Explain: *"The collector arrived, nobody was there. That is a real operational event and the system has a state for it."*
3. Show the **admin override** putting it back into the queue — and point out that the audit log records it *as an override*, with the name of the administrator who did it.

> *"Supervisors can intervene. They cannot intervene invisibly."*



### Close — 60 seconds

> "That is the full custody chain, working, with the data persisted and audited. Phase 1 is 97% complete against the scope we agreed. The remaining 3% is honest: no message has yet reached a real phone, because we have no Africa's Talking account. Everything else on the list is done and covered by 168 automated tests.
>
> What I need from Phase 2 is the hardening work — a production-grade host, real credentials, and a security pass — before this touches real residents."

---



## 3. What to show only if asked

Do not volunteer these; they lengthen the demo. Have them ready.


| If he asks about... | Show                                                                                         |
| ------------------- | -------------------------------------------------------------------------------------------- |
| Testing             | Run `tests\run.ps1` live. 126 assertions scrolling past in twelve seconds is very persuasive |
| Security / roles    | Log in as citizen, try to reach the admin dashboard, show the refusal                        |
| Data integrity      | The status history table in SQLite alongside the UI timeline                                 |
| Reporting           | The CSV export opened in Excel                                                               |
| Mobile              | Resize the browser narrow — the layout is mobile-first                                       |
| M-Pesa              | The sandbox connector button on the admin screen                                             |


---



## 4. Three things not to do

1. **Do not claim SMS is live.** It is not. The moment you overstate one thing, everything else you said gets re-examined. The system itself displays "sandbox" — let it be honest for you.
2. **Do not open the code** unless the supervisor asks. The COO is buying an operational capability, not PowerShell.
3. **Do not apologise for Phase 1 scope.** AI recognition and rewards were deliberately excluded and agreed. Say "deferred to Phase 2 as agreed", never "we didn't get to it".

---



## 5. The numbers to know cold

If you remember nothing else, remember these.

### Scale of what was built


| Metric             | Figure                                               |
| ------------------ | ---------------------------------------------------- |
| API endpoints      | **32**                                               |
| Database tables    | **13**                                               |
| User roles         | **4**                                                |
| Lifecycle statuses | **17** — 12 success stages, 5 failure states         |
| Audit action types | **16**                                               |
| Automated tests    | **168** — 42 unit, 126 integration — **all passing** |
| Phase 1 completion | **97%**                                              |
| Backend size       | ~842 lines                                           |
| Documentation      | 5 documents                                          |




### The twelve-stage lifecycle — be able to recite the shape

Submitted → Pending assignment → Collector assigned → Accepted → En route → Collected → **In collector custody** → Transfer scheduled → In transit → **Received by recycler** → Validated → Completed

The two bold ones are the custody handovers. Those are the commercially important events.

Five failure states: **Cancelled · Rejected · No-show · Transfer failed · Recycler rejected**

### The demo caseload on screen


| KPI                    | Value |
| ---------------------- | ----- |
| Total requests         | 17    |
| Submitted today        | 10    |
| Awaiting assignment    | 3     |
| Assigned / in progress | 4     |
| With the recycler      | 2     |
| Completed              | 6     |
| Exceptions             | 1     |
| Notification records   | 518   |
| Audit records          | 134   |




### Caseload cheat sheet — the exact records on screen

Know these so you never hunt for a record while sharing your screen.


| Need                                                  | Request                             | Where                                                                                                            |
| ----------------------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **A completed request with a full 12-stage timeline** | **#19 — Msimbazi Street, Kariakoo** | Amina Hassan (the citizen login). Has 12 timeline entries. Its comma also proves the CSV export quotes correctly |
| A second completed one                                | #24 — Upanga West, Ilala            | Amina Hassan, also 12 stages                                                                                     |
| **The no-show, for Act 6**                            | **#25 — Kigamboni Ferry, Temeke**   | Visible on the admin dashboard                                                                                   |
| A load sitting with the recycler                      | #35 — Ilala Boma, Ilala             | Recycler login sees this waiting to validate                                                                     |
| A load in transit                                     | #34 — Kinondoni Shamba              | Amina Hassan owns it — good for showing a citizen tracking a live job                                            |
| A collector currently en route                        | #32 — Ubungo Maziwa                 | Juma Mwangi                                                                                                      |
| Awaiting assignment                                   | #26, #27, #28                       | The admin queue you assign from                                                                                  |


**Amina Hassan** (your citizen login) owns four requests: #19 and #24 completed, #29 assigned, #34 in transit. That gives you both a finished journey and a live one from the same account.

Searching **"Kariakoo"** on the admin dashboard returns 2 rows. The dashboard shows 10 rows per page: page 1 is the live caseload, page 2 is completed history.

### What is deliberately excluded from Phase 1

AI battery recognition · AI scrap value prediction · Rewards engine · Certificates · Advanced analytics · Commercial dashboard · Sustainability reports · Carbon credits · Machine learning · Image analysis

Every one was agreed as deferred. Each has an architectural hook already in place.

---



## 6. Questions Mr. Menelick is most likely to ask

These are ordered by how likely a COO is to ask them. The answers are written to be spoken, not read.

### 6.1 Commercial and operational

**Q1 — "How much does it cost to run?"**

> "Three cost lines. Hosting — a small cloud server, roughly €20–40 a month at pilot scale. Messaging — Africa's Talking SMS in Tanzania is a few cents per message; at two messages per status change and twelve stages, budget around 8–10 messages per completed pickup. And a database. At a hundred pickups a month that is a very small number. The cost that matters is not the software, it is the collector's time and fuel — and the system is designed to reduce that by giving them ordered, geolocated jobs instead of phone calls."

**Q2 — "How many pickups can this handle in a day?"**

> "Honestly? In its current form, tens, not thousands. The Phase 1 host is single-threaded — it handles one request at a time. That was a deliberate constraint of the machine I built it on, and it is the first thing Phase 2 fixes. The design itself has no such limit; it is a database-backed REST API and it scales the way any of them do. But I will not tell you it is ready for volume today, because it is not."

**Q3 — "What happens when a collector has no phone signal?"**

> "Today, they cannot update the status until they are back in coverage. The pickup still happens — the paperwork just lands late. That is a genuine gap for Tanzanian field conditions and it is on the Phase 2 list as offline capture with sync-on-reconnect. It is a well-understood pattern and not a large piece of work, but it is not built."

**Q4 — "How do we onboard collectors and recyclers?"**

> "An administrator creates the account from the admin screen — I can show you. It takes about twenty seconds and automatically creates their collector profile with vehicle and area. There is no self-service registration for collectors, deliberately: you do not want anyone declaring themselves a licensed handler of hazardous waste."

**Q5 — "What does the collector actually see on their phone?"**

> "The same application. It is mobile-first and works in a phone browser — no app store, no installation, which matters when your collectors are using low-end Android devices with limited storage. They see only their own jobs, with a navigation link that opens Google Maps at the resident's exact pin."

**Q6 — "How does this make money, or save money?"**

> "Phase 1 does not monetise — it establishes the traceable chain. The commercial models it enables are the Phase 2 conversation: recyclers pay for guaranteed feedstock volume, producers pay for compliance evidence under extended producer responsibility, and residents can be paid a small incentive through M-Pesa. The custody data is the asset. Without it, none of those three models can be evidenced."



### 6.2 Compliance, data and risk

**Q7 — "Can we prove where a battery went, if a regulator asks?"**

> "Yes, and that is the core of the system. Every request has a status history with a timestamp and a named person at each of the twelve stages, plus a separate audit log, plus photographic evidence at collection and handover. Nothing can be back-dated through the interface, and a supervisor override is recorded *as* an override with their name on it. That is the answer to a regulator."

**Q8 — "Who owns the data, and where does it live?"**

> "Right now it lives in a single database file on the machine running it — this is a proof of concept on my laptop. For a pilot, that becomes a hosted database, and where it is hosted is a decision for you, not for me. If TCC Ireland is the data controller and residents in Tanzania are the data subjects, you have both GDPR and Tanzanian data protection obligations to reconcile. That needs a legal answer before we onboard a single real resident, and I would want that decided in Phase 2 planning rather than after."

**Q9 — "Is it secure?"**

> "Secure enough for a controlled pilot, not for production, and I will be precise about the difference. What is in place: token-based login, four roles with permissions enforced on the server rather than hidden in the interface, rate limiting against brute force, input validation, and a full audit trail. What is not: passwords use a hashing method that is too fast to resist a determined offline attack, the database queries are built as text rather than bound parameters, and there is no encryption in transit because it runs on a local machine. Those three are the top of the Phase 2 list. I would not put real resident data into this build."

**Q10 — "What is the biggest risk?"**

> "The messaging channel. Everything in the platform depends on residents and collectors being notified, and no message has yet reached a real handset because we have no Africa's Talking account. The entire framework is built and tested — retries, delivery tracking, failure handling — but the last hop is unproven. Getting a sandbox account and sending one real SMS is the single highest-value thing we can do next, and it costs almost nothing."

**Q11 — "What if the system goes down mid-collection?"**

> "The collector's job does not disappear — it is in the database, not in their browser. When the system comes back, the request is exactly where it was. What is missing today is automatic restart and monitoring; if it stops, somebody has to notice. That is standard operational tooling and it comes with the Phase 2 host migration."



### 6.3 Technology and delivery

**Q12 — "Why build this rather than buy something?"**

> "Two reasons. The custody model is specific — a resident-to-informal-collector-to-licensed-recycler chain in an African urban market is not what off-the-shelf waste software is built for; those assume commercial skips and weighbridges. And second, the data is the asset. If the traceability record sits in someone else's product, TCC does not own the thing that has value."

**Q13 — "How long to production?"**

> "Phase 2A, the hardening, is the honest answer to that question and it is six to eight weeks of focused work: move to a production host, fix the three security items, migrate the database, add TLS, prove the integrations. After that you have something you can put real residents on. The feature work after that is optional and can run in parallel with a live pilot."

**Q14 — "What did you actually build versus configure?"**

> "All of it. The backend, the database schema, the lifecycle engine, the four role interfaces, the notification framework and the test suite are original. What I did not write is the map tiles — that is OpenStreetMap — and the SMS delivery, which is Africa's Talking. Both are deliberate: you do not build a mapping stack for a pilot."

**Q15 — "Show me it is actually tested, not just working on your screen."**

> Run the test suite live. *"One hundred and sixty-eight automated checks. Forty-two test the logic in isolation, one hundred and twenty-six drive the real system over HTTP and then verify the database directly — so they cannot be fooled by an interface that looks right."*
>
> Then add the honest part: *"Worth telling you that this suite found three serious bugs in what I previously believed was a finished build, including one where any list of more than one row was silently truncating. That is exactly why the tests exist."*

**Q16 — "What is the technical debt you are carrying?"**

> "Seven items, all documented. The three that matter: the runtime host is a stopgap chosen because the machine I built on blocks the normal stack, the password hashing needs replacing, and the database queries need parameter binding. None of them affect what you have just seen working. All three get fixed in the same Phase 2 migration, which is why I have grouped them."



### 6.4 The questions that are harder to answer well

**Q17 — "What does not work?"**

Answer this one fast and without hedging. Hesitating here costs more than the answer does.

> "Four things. No message has reached a real phone. M-Pesa has never contacted Safaricom — it is a sandbox connector, and no money has moved. There is no offline mode for collectors. And there are no automated tests for the user interface, so I verified those screens by hand. Everything else on the Phase 1 list is working and tested."

**Q18 — "Would you put this in front of a real resident tomorrow?"**

> "No — and I would rather tell you that than have you find out. Two reasons: the password security is not production-grade, and there is no encryption in transit. Both are fixed by the same piece of Phase 2 work. Put me on a controlled pilot with TCC staff acting as residents and collectors and I would say yes today, because that is exactly what it is ready for."

**Q19 — "Your supervisor is here. What was the hardest part?"**

A good question to answer with substance rather than modesty.

> "Getting the workflow enforcement right. It is easy to build screens where the buttons only offer the next valid step — but then anyone who calls the API directly can put a request into any state they like. So the twelve-stage lifecycle is enforced on the server, in one place, and every transition writes its history, its audit record and its notifications in the same code path. It is impossible to change a status without those three things happening. That single design decision is what makes the chain of custody trustworthy rather than decorative."

**Q20 — "What would you do differently?"**

> "Write the tests first. My original suite checked that endpoints returned success codes, and everything passed. When I later wrote tests that checked the actual row counts, I found three serious bugs immediately. A test that only asks 'did this respond' is not a test."

**Q21 — "How much of this would survive if we changed direction?"**

> "The database design and the lifecycle model would survive almost entirely — those encode how the business works, not how the software was written. The interface and the runtime host are the replaceable parts. That is roughly the right balance for a proof of concept: the thinking is durable, the implementation is not precious."

---



## 7. Questions your supervisor may ask

Different audience, different concerns — academic rigour rather than operations.


| Question                                   | Short answer                                                                                                                                         |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| What is the architecture?                  | Three tiers: a single-page browser client, a REST API, and a relational store. The lifecycle engine sits in the API layer so no client can bypass it |
| Why SQLite?                                | Zero-configuration for a proof of concept. The schema is standard SQL and migrates to PostgreSQL without redesign                                    |
| How is authorisation enforced?             | Two layers: role checks on every route, and ownership scoping pushed into the SQL so an unauthorised row is never even selected                      |
| How did you validate correctness?          | 168 automated assertions, plus direct database verification independent of the API                                                                   |
| What is your evidence the design is sound? | The failure paths work as designed — no-show, gate rejection, and recovery — which is where weak designs break                                       |
| What would you research next?              | Offline-first synchronisation for low-connectivity field operations. It is the gap between this working in a demo and working in Dar es Salaam       |


---



## 8. Phase 2 — the ask

Have this ready. If the meeting goes well he will ask what you need.

### Phase 2A — Hardening · 6–8 weeks · **the prerequisite**

Production host · parameter binding · production password hashing · PostgreSQL migration · TLS · remove demo seeding · scheduled notification queue · authenticate the delivery webhook.

### Phase 2B — Proving the integrations · 2 weeks · **cheapest, highest value**

An Africa's Talking sandbox account and one real SMS end to end. A real WhatsApp message. An M-Pesa Daraja sandbox transaction. **Ask for the Africa's Talking account in this meeting — it costs almost nothing and it closes the single largest open risk.**

### Phase 2C — Functional depth · 6–8 weeks

Per-user channel preferences · proximity-based auto-assignment · route optimisation · offline capture · bulk admin operations · automated UI tests.

### Phase 3 — The deferred intelligence features

Only after 2A. Battery recognition, value prediction, rewards, certificates, carbon reporting — each already has a hook: evidence photos, battery type and quantity, the M-Pesa rail, and the custody history respectively.

**If you ask for one thing tomorrow, ask for the Africa's Talking sandbox account.**

---



## 9. If something goes wrong

Read this in the morning. Calm recovery in front of an operator is itself a demonstration of competence.


| Problem                        | Cause                                               | Fix, in under a minute                                                                                                                           |
| ------------------------------ | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Browser says it cannot connect | Server not running, or the port changed             | Look at the PowerShell console for the real address. If it says it cannot bind, open `.env`, change `APP_PORT` to the next number, save, restart |
| "Cannot bind port" on startup  | Windows is still holding the port after a hard kill | Change `APP_PORT` in `.env` and restart. One line                                                                                                |
| Login fails                    | Caps lock, or wrong account                         | Password is `VoltRescue!23` — capital V, capital R, exclamation mark                                                                             |
| A page looks empty             | Session expired                                     | Log out and back in                                                                                                                              |
| A status button is refused     | The lifecycle is enforcing order                    | **This is a feature — say so.** *"The system will not let me skip a stage. That refusal is the control working"*                                 |
| Dashboard shows odd data       | Tests were run after the reset                      | Re-run `demo-reset.ps1`, takes 30 seconds                                                                                                        |
| Map does not load              | No internet — tiles come from OpenStreetMap         | Coordinates still capture and save. Say so and move on                                                                                           |
| Something genuinely breaks     |                                                     | *"That is a defect and I will have it diagnosed by this afternoon."* Then continue. **Do not debug live**                                        |




### The recovery line, if you need it

> "Let me come back to that — I would rather show you the custody chain end to end than lose the thread here."

Then carry on. You know the system works; 168 passing tests say so.

---



## 10. The three sentences to close on

If the meeting is running short and you only get thirty seconds:

> "Phase 1 gives you a working, audited chain of custody from a resident's doorstep to a licensed recycler, with every handover timestamped and attributable.
>
> It is 97% complete against the agreed scope, verified by 168 automated tests, and I have been explicit in the documentation about the 3% that is not done.
>
> The next step is six to eight weeks of hardening — and one Africa's Talking account, which is the cheapest way to close the biggest remaining risk."

---

*Supporting documents:* `01_VoltRescue_Process_Flow_Guide.md` *(business process),* `02_VoltRescue_User_Guide.md` *(end-user instructions),* `03_VoltRescue_Technical_Design_Handbook.md` *(technical detail),* `04_VoltRescue_Final_Readiness_Report.md` *(assessment and roadmap).*