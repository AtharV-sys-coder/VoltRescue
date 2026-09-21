# VoltRescue — Final Readiness Report

**Document 4 of 4 · Phase 1 Proof of Concept**
**Assessment date:** 9 September 2026
**Assessed build:** `server.ps1` (842 lines), SQLite store, SPA frontend
**Application address:** `http://127.0.0.1:8815/` (set by `APP_PORT` in `.env`)
**Verification basis:** 170 automated assertions executed against the running system, plus a manual browser pass across all four roles

---

## Table of contents

1. Executive summary
2. Completion assessment
3. Component status: working, partial, missing, debt
4. Verification evidence
5. Remaining gaps
6. Technical risks
7. Production readiness assessment
8. Recommended next-phase roadmap
9. Deliverables index

---

## 1. Executive summary

VoltRescue has moved from a static UI prototype to a working system. Every screen is backed by a real HTTP API, every API is backed by SQLite, and no screen keeps state in the browser — there is no `localStorage` anywhere in the frontend, and the database is the only source of truth.

The twelve-stage pickup lifecycle is enforced server-side by a transition map rather than by UI convention, so an illegal move is refused with HTTP 409 no matter which client attempts it. Every transition writes a status-history row, an audit record, and notifications to the affected parties, inside the same code path — none of those can be skipped by calling a different endpoint.

**Three defects of real significance were found and fixed during this final verification pass**, all of which had been present in the previously "passing" build:

1. **Every API list containing two or more rows was collapsing to a single nested element.** A PowerShell array-return idiom was being double-wrapped, so twelve-stage timelines rendered as one entry and multi-row tables silently truncated. The earlier 24-assertion suite passed because it only checked HTTP status codes, never row counts.
2. **The notification retry queue existed as a table and a design, but the running host never wrote to it.** It is now fully implemented: persist-then-send, provider adapters, exponential backoff to four attempts, a terminal `failed_permanent` state, and delivery-report ingestion.
3. **Any authenticated user could attach evidence to any request.** Uploads are now restricted to the administrator, the assigned collector, and the receiving recycler.

The system is **ready for supervisor demonstration and pilot use on a controlled machine**. It is **not ready for production or internet exposure**, for reasons set out in section 7 — chiefly the password hashing scheme, string-concatenated SQL, and the single-threaded host.

---

## 2. Completion assessment

Scored against the scope defined for Phase 1. "Complete" means implemented, persisted, and covered by an automated assertion.

| # | Required capability | Status | Completion | Evidence |
|---|---|---|---:|---|
| 1 | User pickup request | Complete | 100% | Creation with GPS, validation, auto-advance to `PENDING_ASSIGNMENT` |
| 2 | Collector assignment | Complete | 100% | Admin assign, reassign, collector accept with ownership check |
| 3 | Pickup lifecycle tracking | Complete | 100% | All 12 stages plus 5 failure states enforced server-side |
| 4 | Recycler handover tracking | Complete | 100% | Custody transfer rows, receive, validate, complete, reject, re-dispatch |
| 5 | Administrative oversight | Complete | 100% | KPIs, workload, filters, search, sorting, pagination, export, override |
| 6 | Location tracking | Complete | 100% | Auto-detect, manual pin, stored coordinates, navigation links |
| 7 | SMS / WhatsApp notifications | Functionally complete, **not live** | 85% | Full framework and queue implemented; no provider key, so nothing has been sent to a handset |
| 8 | Status updates | Complete | 100% | Transition map, audit, timeline, timestamp, actor on every change |
| 9 | Reporting basics | Complete | 100% | Dashboard counters, collector workload, RFC-4180 CSV export |
| 10 | Secure authentication | Complete for POC | 90% | JWT, RBAC, rate limiting, validation — but hashing is not production-grade |
| 11 | Database persistence | Complete | 100% | 13 tables; no browser-side state anywhere |

**Weighted Phase 1 completion: 97%.**

The three points withheld are honest rather than cosmetic: item 7 cannot be called finished until a real message reaches a real phone, and item 10 must not be called finished while passwords are protected by salted SHA-256.

### Excluded scope — confirmed absent

The following were explicitly out of scope and are **not** implemented. Architecture hooks exist where noted; no placeholder pretends to work.

| Excluded feature | State |
|---|---|
| AI battery recognition | Absent. The `uploads` table is the future input surface |
| AI scrap value prediction | Absent. `battery_type` and `quantity` are the future feature inputs |
| Rewards engine | Absent. The M-Pesa sandbox connector is the future payout rail |
| Certificates | Absent |
| Advanced analytics | Absent. Only operational counters exist |
| Commercial dashboard | Absent |
| Sustainability impact reports | Absent |
| Carbon credits | Absent |
| Machine learning | Absent |
| Battery image analysis | Absent |

---

## 3. Component status

### 3.1 Working — verified by automated assertion

| Area | Components |
|---|---|
| **Authentication** | Registration with validation, login by email *or* phone, JWT issue and verification, expiry enforcement, tamper rejection, profile read and update, password reset request and confirm |
| **Authorisation** | Role checks on all 32 routes; ownership scoping pushed into SQL so unauthorised rows are never selected; upload ownership; override restricted to admin |
| **Pickup** | Create, list (scoped per role), detail with timeline and evidence, status update |
| **Lifecycle** | 12 success stages, 5 failure states, legal-transition enforcement, idempotent re-apply, admin override with audit marking, recovery paths from `NO_SHOW`, `TRANSFER_FAILED` and `RECYCLER_REJECTED` |
| **Collector** | Task list scoped to own assignments, accept, en-route, completed, custody, handover with recycler selection |
| **Recycler** | Inbound list, receive, validate, complete, reject at gate or after receipt |
| **Admin** | Dashboard KPIs, collector workload, search, status filter, pagination, CSV export, user and collector creation, audit log, status override, graceful shutdown |
| **Notifications** | Dual-channel fan-out, persist-then-send, provider adapter registry, exponential-backoff retry queue, permanent-failure retirement, delivery-report webhook, admin statistics and manual drain |
| **Evidence** | Base64 upload, 5 MB cap, MIME-driven extension, per-request folders, ownership enforcement, previews in the UI |
| **Audit** | 16 distinct action types including logins, failed logins, status changes with override flag, uploads, and notification failures |
| **Geolocation** | Browser geolocation, Leaflet/OpenStreetMap picker, stored coordinates, OpenStreetMap and Google Maps navigation links |
| **Security controls** | Rate limiting on login, registration and general API; input validation; identical error text for wrong password and unknown account |

### 3.2 Partially working

| Component | What works | What does not |
|---|---|---|
| Africa's Talking SMS | Adapter, endpoint selection, request shaping, response parsing, retry, delivery reports | No API key, so the live HTTP branch has never executed |
| Africa's Talking WhatsApp | Same framework, separate provider identity and delivery tracking | Never sent; the Content API request shape is unverified against the real service |
| Retry queue scheduling | Backoff, attempt ceiling, permanent failure, manual and post-failure draining | No timer or background worker — a retry due in two minutes only runs when something else triggers a drain |
| M-Pesa | Sandbox auth, STK push validation and persistence, callback endpoint, explicit `live = false` | Synthetic in the PowerShell host; only the PHP reference contains real cURL. Nothing has contacted Safaricom |
| PHP implementation | Complete and internally consistent as a reference design | Has never executed — Windows Application Control blocks unsigned PHP on this machine |

### 3.3 Missing

| Item | Reason |
|---|---|
| Automated UI regression tests | No browser test runner in this environment; the SPA was verified by hand |
| Live-provider contract tests | No credentials |
| Performance and load testing | Single-threaded host makes the numbers meaningless until the host changes |
| Concurrency tests | Two collectors accepting the same job simultaneously is untested |
| TLS | Loopback only |

### 3.4 Technical debt

| # | Debt | Assessment |
|---|---|---|
| D-1 | PowerShell `HttpListener` host: single-threaded, spawns a `sqlite3.exe` process per query | The largest structural constraint. Chosen because PHP is blocked on this machine, not because it is right |
| D-2 | SQL built by string concatenation with manual quoting | Correct today because `Q` is applied consistently, but one missed call is an injection. Parameter binding is the fix |
| D-3 | Salted SHA-256 in an envelope labelled `pbkdf2:` | The label is misleading and the scheme is too fast. Must become bcrypt or Argon2id |
| D-4 | `Init-Db` resets demo passwords on every start | Convenient for a demo, unacceptable anywhere else |
| D-5 | Sign-in screen offers one-click demonstration logins | Replaced the hard-coded admin credentials, which was worse. Still a demo affordance: remove the `DEMO_ACCOUNTS` block before any shared deployment |
| D-6 | `runtime/php/` — 119 MB, 84 files, cannot execute | Dead weight. Safe to delete; kept only because it was deliberately downloaded and can be re-fetched |
| D-7 | 500 responses echo the exception message | Useful now, information disclosure later |
| **Cleared** | Root `app.js` and `style.css` duplicated the live frontend | **Deleted.** Nothing referenced them |
| **Cleared** | Port hard-coded in five files | **Resolved.** `APP_PORT` in `.env` drives everything, and `POST /admin/shutdown` stops the port leaking |
| **Cleared** | Frontend injected stored user text straight into `innerHTML` | **Resolved.** An address or remark containing markup executed in the browser of anyone who viewed it, including administrators. All interpolated values now pass through an `esc()` helper |
| **Cleared** | The request form depended on a map library loaded from a public CDN | **Resolved.** With no internet the missing `L` global threw and took out the whole screen. It now falls back to manual coordinate entry |

---

## 4. Verification evidence

### 4.1 Automated results

| Suite | Assertions | Passed | Failed |
|---|---:|---:|---:|
| `tests/unit.ps1` | 42 | 42 | 0 |
| `tests/run.ps1` | 126 | 126 | 0 |
| **Total** | **170** | **170** | **0** |

The API suite runs in eleven labelled phases: smoke and authentication, input validation, role-based access control, the happy-path lifecycle, uploads and ownership, failure paths and recovery, transition rules, the notification framework, admin oversight and reporting, integration connectors, and database persistence.

### 4.2 Defects found and fixed during this pass

| Defect | Severity | Detail | Resolution |
|---|---|---|---|
| Multi-row API lists collapsed to one nested element | **Critical** | `Invoke-Select` returned `,@(...)` while call sites wrapped in `@(...)`, nesting the array. Timelines, collector lists and dashboard tables were all truncated | Unrolled return, `@()` at every call site, documented as a maintenance rule |
| Single-row lookups returned nothing | **Critical** | A `PSCustomObject` returns `$null` for `.Count`, so `if ($rows.Count)` was false for exactly one row — this broke `Get-UserFromReq`, and therefore every authenticated request | All `.Count` tests operate on `@(...)` |
| All notification reads returned empty | High | The error detector matched the substring "error", and `SELECT *` on `notifications` contains the column name `last_error` | Error detection now matches the sqlite CLI's actual error wording and requires valid JSON |
| Failed inserts were silent | High | `sqlite3.exe` reports on stderr and continues, so `SELECT last_insert_rowid()` returned 0 and execution carried on with a bogus id | `Invoke-Exec`/`Invoke-Scalar` throw on error; `Invoke-InsertGetId` rejects any non-positive id. Duplicate registration now returns a clean 409 |
| Any authenticated user could upload evidence to any request | **Security** | No ownership check on `POST /uploads` | `Test-UploadRight`: admin, assigned collector, or receiving recycler only |
| CSV export corrupted by commas in data | Medium | Fields were concatenated unquoted | RFC 4180 quoting via `Csv-Cell` |
| No retry, queue or live send in the running host | High | The framework existed only in the unused PHP reference | Fully implemented in `server.ps1` |
| A recycler could not refuse a load at the gate | Medium | `RECYCLER_REJECTED` was only reachable after formal receipt | Added `IN_TRANSIT_TO_RECYCLER → RECYCLER_REJECTED`; diagrams updated |
| Stored user text was injected into the DOM unescaped | **Security** | Addresses, remarks and notes were interpolated into `innerHTML` verbatim. A resident could store markup that executed in the administrator's browser — the lowest-trust input reaching the highest-privilege session | All interpolated values pass through an `esc()` helper. Verified with a payload that now renders as inert text |
| The pickup form died without internet | **High for the demonstration** | Leaflet loads from a public CDN. When it was unreachable the missing `L` global threw and the entire request screen failed to render | Falls back to manual coordinate entry with a sensible default; GPS capture still works |
| A failed call left screens on "Loading…" forever | Medium | No view or action handler caught errors, so any failure was silent apart from a console message | Central `handleError`, busy-state buttons that cannot double-submit, and a 401 that returns cleanly to sign-in |
| An RBAC test misreported a lookup failure as a security breach | Medium (test quality) | The test resolved a collector by array position against an unordered `SELECT`. When that yielded nothing the id became `0`, so every row appeared to violate scoping — alarming and wrong | Collectors are resolved by the identity that owns them, and the id is asserted non-zero. Confirmed stable over repeated runs; the endpoint itself was never at fault |

### 4.3 Data integrity confirmed directly against the database

Row counts were checked in SQLite independently of the API: twelve `status_history` rows for a completed request, one `assignments` row, two `custody_transfers` rows for a rejected-and-re-dispatched load, and audit entries for logins, failed logins, status changes, overrides and uploads.

---

## 5. Remaining gaps

| # | Gap | Impact | Recommended action |
|---|---|---|---|
| G-1 | No message has reached a real handset | The single largest unproven assumption in the platform | Obtain Africa's Talking sandbox credentials and run one end-to-end send before the pilot |
| G-2 | The retry queue has no scheduler | Retries are opportunistic | Add a scheduled task calling `POST /notifications/process`, or a background thread |
| G-3 | WhatsApp request shape unverified | May fail on first contact with the live API | Validate against the Content API in sandbox |
| G-4 | M-Pesa never contacted Safaricom | Payout rail unproven | Exercise the Daraja sandbox from the PHP reference |
| G-5 | Delivery webhook is unauthenticated | Anyone reachable can post a delivery status | Verify the provider signature or restrict by source IP |
| G-6 | No UI regression tests | Frontend changes are unguarded | Add browser automation in Phase 2 |
| G-7 | No concurrency testing | Double-accept behaviour unknown | Add a test; consider a conditional update on accept |
| G-8 | Screenshots not captured | The user guide has placeholders | Capture during the supervisor demonstration |

---

## 6. Technical risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-1 | Password hashing is too fast to resist offline cracking | Certain if the database leaks | **High** | Move to bcrypt/Argon2id with rehash-on-login before any real user data |
| R-2 | String-concatenated SQL becomes an injection on one missed `Q` | Low today, rises with every change | **High** | Parameter binding during the host migration |
| R-3 | Single-threaded host collapses under concurrent load | Certain beyond a handful of users | **High** | Host migration is a prerequisite for pilot scale, not an optimisation |
| R-4 | Process-per-query means tens of milliseconds of overhead per query | Certain | Medium | Same migration; a persistent connection removes it |
| R-5 | Demo seeding resets passwords on every start | Certain | **High** in production | Remove `Init-Db` seeding from any non-demo build |
| R-6 | Notification volume grows unbounded — two rows per event per recipient | Certain over time | Medium | Retention policy and an index on `created_at` |
| R-7 | SQLite single-writer locking under concurrent updates | Medium | Medium | PostgreSQL or MySQL at migration time |
| R-8 | No TLS; tokens travel in clear if ever moved off loopback | Low today | **High** if exposed | Reverse proxy with TLS before any network exposure |
| R-9 | The PHP reference has never run, yet is documented as the migration target | Medium | Medium | Execute it on an unrestricted machine before committing to it |

---

## 7. Production readiness assessment

| Dimension | Rating | Justification |
|---|---|---|
| Functional completeness | **Ready** | Every in-scope workflow works end to end and is covered by tests |
| Data integrity | **Ready** | Foreign keys, transition enforcement, complete audit trail, no client-side state |
| Authentication and authorisation | **Ready for POC, not production** | Model is correct; the hashing primitive is not |
| Data protection | **Not ready** | No TLS, no encryption at rest, no retention policy |
| Scalability | **Not ready** | Single-threaded, process-per-query, file-based database |
| Observability | **Partial** | Strong audit trail and notification statistics; no metrics, no structured logs, no alerting |
| Operational resilience | **Partial** | Graceful shutdown and retry queue exist; no supervision, no automatic restart, no backup schedule |
| Test coverage | **Good** | 170 assertions across unit and integration; no UI or load coverage |
| Documentation | **Ready** | Four documents covering process, end-user, technical and readiness |

### Verdict

> **Approved for supervisor demonstration and controlled pilot on a single trusted machine.**
> **Not approved for production, multi-user deployment, or any internet-facing exposure.**

The blocking items for production are precisely three: the password hashing scheme, the SQL construction method, and the runtime host. None of these are functional defects — the system behaves correctly — but each is a structural property that a production deployment cannot accept.

---

## 8. Recommended next-phase roadmap

### Phase 2A — Hardening (prerequisite for everything else)

The migration and the security fixes belong together, because the migration is the natural moment to fix them.

1. Move to a mainstream host — the existing PHP reference, or Node — on a machine without Application Control restrictions.
2. Replace all SQL string concatenation with bound parameters.
3. Replace password hashing with bcrypt or Argon2id, rehashing on next login.
4. Migrate SQLite to PostgreSQL; add indexes on `status`, `created_at`, and the foreign keys.
5. Terminate TLS at a reverse proxy; remove wildcard CORS.
6. Remove demo seeding, the pre-filled login form, and exception echoes in 500 responses.
7. Put the notification queue on a scheduler.
8. Authenticate the delivery webhook.

### Phase 2B — Proving the integrations

9. Africa's Talking sandbox: one real SMS and one real WhatsApp message, end to end, with the delivery report landing back in the database.
10. M-Pesa Daraja sandbox: a real STK push and callback.
11. Contract tests for both, running in CI.

### Phase 2C — Functional depth

12. Per-user channel preferences (the schema already supports this — channel is a column, not a flag).
13. Collector auto-assignment by proximity, using coordinates already being captured.
14. Route optimisation across a collector's open jobs.
15. Offline capture for collectors in low-coverage areas, syncing on reconnection.
16. Bulk operations and saved views for administrators.
17. Automated UI regression tests and load testing.

### Phase 3 — The deferred intelligence features

Only after 2A is complete. Each has a hook already in place:

| Feature | Existing hook |
|---|---|
| AI battery recognition | `uploads` — evidence photos are already captured and linked to requests |
| Scrap value prediction | `battery_type` and `quantity` on every request |
| Rewards engine | The M-Pesa sandbox connector, once proven |
| Certificates | `status_history` provides the complete verified chain of custody |
| Sustainability and carbon reporting | Completed-request volumes by battery type |
| Commercial dashboard | The existing admin dashboard, extended |

---

## 9. Deliverables index

Every artefact requested for Phase 1, and where it lives.

| Deliverable | Location |
|---|---|
| Architecture diagram | Document 3, §1 |
| Database ERD | Document 3, §5.1 |
| Full schema, indexes, constraints | Document 3, §5 |
| API documentation (32 endpoints) | Document 3, §6 |
| Role matrix | Document 3, §7.2; summarised in Document 2, Appendix |
| Status lifecycle diagram | Document 1, §7 (success and full failure-path versions) |
| Integration design | Document 3, §8–12 |
| Security design | Document 3, §13 |
| Audit logging design | Document 3, §14 |
| Deployment guide | Document 3, §16 |
| Monitoring and support | Document 3, §17 |
| Test plan and results | Document 3, §18 |
| Gap analysis | Document 3, §19; this document, §5 |
| Business process and journeys | Document 1 |
| End-user instructions and FAQs | Document 2 |
| Readiness report | This document |
| Maintenance pitfalls for new developers | Document 3, §4.16 |

---

*End of Document 4. See `01_VoltRescue_Process_Flow_Guide.md`, `02_VoltRescue_User_Guide.md`, and `03_VoltRescue_Technical_Design_Handbook.md`.*
