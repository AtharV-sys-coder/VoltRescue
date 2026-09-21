# VoltRescue — the short walkthrough

**Purpose:** what to say in the first two or three minutes, so that if Mr Menelick joins late, joins briefly, or simply says *"give me the short version"*, you have an answer ready rather than an improvisation.

Use this on its own when time is short. If he engages and wants more, it hands straight over to the full eighteen-minute script in `05_VoltRescue_Demo_Briefing.md`, section 2.

**Before you speak:** run `demo-prep.ps1`, have the browser open at `http://127.0.0.1:8815/` on the admin dashboard, and have `demo-cheatsheet.txt` visible on a second screen.

---

## 1. The two-and-a-half minute version

Spoken at a normal pace this runs to about two minutes forty. Everything in *italics* is a stage direction, not something you say.

---

**0:00 — What it is** *(dashboard already on screen)*

> "VoltRescue is a battery collection platform for Dar es Salaam. A resident with dead batteries requests a pickup from their phone, a collector comes and takes them, and the batteries are tracked all the way to a licensed recycler.
>
> The problem it solves is custody. Today, once a battery leaves someone's house, nobody can prove where it went. This makes that chain provable."

**0:25 — What is actually built** *(gesture at the dashboard)*

> "What you are looking at is not a mock-up. This is a working system with a database behind it. Everything on this screen was created by using the application.
>
> There are four kinds of user — the resident, the collector, the recycler, and your operations team — and each one sees only what they are entitled to see. A collector cannot see another collector's jobs. That is enforced on the server, not just hidden in the interface."

**0:55 — The one thing to understand** *(open a completed request's timeline)*

> "This is the part that matters. Every battery moves through twelve defined stages, from submitted to recycling completed. The system will not allow a stage to be skipped — a collector cannot mark a load as delivered if they never marked it collected.
>
> Every one of those steps is stamped with who did it and when, and it cannot be edited afterwards. If your operations team needs to force something through, they can, but it is recorded as an override under their name. That is your audit trail, and it is what a regulator or a corporate client would ask for."

**1:40 — Notifications** *(Alerts tab, briefly)*

> "The resident is kept informed by SMS and WhatsApp at each significant step, through Africa's Talking, which is the standard gateway for Tanzania. In this build the messages are recorded rather than sent, so we are not spending money on a demonstration. Switching to live is one credential in a configuration file, not a rewrite."

**2:05 — What is deliberately not built**

> "I want to be straight about the boundary. This phase is the operational backbone — requests, assignment, custody, handover, oversight, and reporting.
>
> What is not here is the intelligence layer: recognising a battery type from a photograph, predicting its scrap value, the rewards scheme, and the sustainability certificates. Those were deliberately deferred. The database already has the space reserved for them, so they are additions rather than rebuilds — but I did not want to show you a demonstration that pretends to do things it cannot."

**2:35 — Hand back**

> "That is the two-minute version. I can walk you through a battery's full journey across all four roles in about ten minutes if that is useful, or go straight to whichever part interests you most."

---

## 2. If you only get thirty seconds

> "VoltRescue tracks used batteries from a resident's door to a licensed recycler, through four roles and twelve verified stages, with a tamper-evident audit trail and SMS notifications at every step. The operational backbone is built and working. The AI valuation and rewards layer is deliberately Phase 2. I would value ten minutes of your time to show you the custody chain end to end."

---

## 3. Built versus deferred, on one page

If he asks for this in writing, or you need to answer quickly, this is the boundary.

| Built and working in Phase 1 | Deferred to Phase 2 |
|---|---|
| Resident pickup requests with GPS location | Battery type recognition from a photograph |
| Collector assignment and workload balancing | Scrap value prediction |
| Twelve-stage custody lifecycle with enforced transitions | Reward points and redemption |
| Recycler handover, receipt, validation and rejection | Recycling certificates for residents |
| Exception handling — no-shows, rejected loads, cancellations | Sustainability and carbon reporting |
| Four roles with server-enforced permissions | Commercial and analytics dashboards |
| Tamper-evident audit log of every action | Route optimisation for collectors |
| SMS and WhatsApp notifications (sandbox) | Live payment settlement |
| Operations dashboard, search, filtering, CSV export | Native mobile applications |
| Photographic evidence at pickup and handover | |

**The honest framing of the deferred column:** none of it is blocked by the current design. The data model reserves space for each item. They were left out because a proof of concept that does the basics reliably is worth more than one that does everything unconvincingly.

---

## 4. Three numbers worth knowing

Only use these if asked. Do not lead with them — a COO cares about the custody chain, not your test count.

- **Twelve stages** in the custody lifecycle, plus five exception states.
- **One hundred and seventy automated tests**, all passing, covering permissions, every lifecycle transition, and the failure paths.
- **Thirty-two API endpoints** across four roles, on thirteen database tables.

---

## 5. The two questions most likely to come first

**"Is this real or is it a prototype?"**

> "It is real in the sense that it works end to end and stores everything properly — you can do the whole journey right now and it will hold. It is a proof of concept in the sense that it runs on a single machine and the messaging is in sandbox. It is not yet hardened for public traffic, and I would not put residents on it tomorrow. What it proves is that the workflow and the custody model are right."

**"How long to a live pilot?"**

> "The functionality you have seen is the bulk of the work. What stands between this and a pilot is hardening rather than features: moving to a proper server, live messaging credentials, and a security review. I would want to scope that properly with you rather than guess a number in this meeting."

---

*Companion to `05_VoltRescue_Demo_Briefing.md` (full script and anticipated questions) and `04_VoltRescue_Final_Readiness_Report.md` (completion status and known limitations).*
