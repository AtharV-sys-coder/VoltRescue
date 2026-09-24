# VoltRescue POC platform — architecture and readiness

Phase 1 only: pickup, assignment, custody, notifications (sandbox), admin, auth, SQLite. AI, rewards, certificates, carbon, and commercial analytics are **not** implemented.

**Run locally:** `powershell -ExecutionPolicy Bypass -File .\start.ps1` then open [http://127.0.0.1:8815/](http://127.0.0.1:8815/). Demo login: `admin@voltrescue.local` (also `citizen@`, `collector@`, `recycler@voltrescue.local`) with password `VoltRescue!23`.

## Architecture

```
Citizen / Collector / Recycler / Admin  (browser SPA: public/)
                    |
                    |  JWT  +  REST /api/*
                    v
         PowerShell HttpListener  (server.ps1)
                    |
         +----------+-----------+------------------+
         |                      |                  |
    sqlite3.exe            uploads/           Africa's Talking
    data/voltrescue.sqlite  evidence photos    SMS + WhatsApp
                                               (sandbox if no API key)
                    |
              M-Pesa sandbox STK (no live debit)
                    |
              OSM / Leaflet GPS + Google Maps nav links
```

Windows Application Control blocks unsigned PHP on this machine. `api/*.php` remains a reference implementation. The **runnable** POC is `server.ps1` + `tools/sqlite3.exe`. Session tokens live in `sessionStorage` only; SQLite is the source of truth.

## Database ERD

```
users 1--1 collectors
users 1--1 recyclers
users 1--* pickup_requests
pickup_requests 1--1 assignments --* collectors
pickup_requests 1--* custody_transfers -- recyclers
pickup_requests 1--* status_history
pickup_requests 1--* uploads
users 1--* notifications
users 1--* audit_logs
          mpesa_sandbox_tx
          rate_limits
          notification_queue
```

Tables match `api/schema.sql`: `users`, `collectors`, `recyclers`, `pickup_requests`, `assignments`, `custody_transfers`, `status_history`, `notifications`, `audit_logs`, plus `uploads`, `mpesa_sandbox_tx`, `rate_limits`.

## Status lifecycle

Happy path:

`REQUEST_SUBMITTED` → `PENDING_ASSIGNMENT` → `COLLECTOR_ASSIGNED` → `PICKUP_ACCEPTED` → `COLLECTOR_EN_ROUTE` → `PICKUP_COMPLETED` → `IN_COLLECTOR_CUSTODY` → `TRANSFER_SCHEDULED` → `IN_TRANSIT_TO_RECYCLER` → `RECEIVED_BY_RECYCLER` → `RECYCLER_VALIDATED` → `PROCESS_COMPLETED`

Failure states: `CANCELLED`, `REJECTED`, `NO_SHOW`, `TRANSFER_FAILED`, `RECYCLER_REJECTED`.

Each legal transition writes `status_history`, an `audit_logs` row, notification rows (SMS + WhatsApp channels), and timestamps. Admins may override.

## Role matrix

| Capability | Citizen | Collector | Recycler | Admin |
|---|---|---|---|---|
| Register / login | Yes | Yes | Yes | Seeded |
| Create pickup | Yes | No | No | Yes |
| View own / assigned / incoming | Own | Assigned | Transfers | All |
| Accept assignment / status / handover | No | Yes | No | Oversight |
| Confirm / validate / complete | No | No | Yes | Yes |
| Assign collectors, users, CSV, audit | No | No | No | Yes |
| M-Pesa sandbox auth | No | No | No | Yes |

## REST APIs

| Method | Path | Auth |
|---|---|---|
| GET | `/api/health` | Public |
| GET | `/api/meta/lifecycle` | Public |
| POST | `/api/auth/register` | Public (rate limited) |
| POST | `/api/auth/login` | Public (rate limited) |
| GET/PUT | `/api/auth/me` | JWT |
| POST | `/api/auth/password-reset` | Public |
| POST | `/api/auth/password-reset/confirm` | Public |
| POST | `/api/pickup/create` | Citizen / admin |
| GET | `/api/pickup` | Role-scoped list |
| GET | `/api/pickup/{id}` | JWT |
| PUT | `/api/pickup/status` | JWT + transition rules |
| GET | `/api/collector/tasks` | Collector / admin |
| POST | `/api/collector/accept` | Collector |
| POST | `/api/collector/handover` | Collector |
| POST | `/api/recycler/confirm` | Recycler / admin |
| GET | `/api/admin/dashboard` | Admin |
| GET | `/api/admin/export` | Admin CSV |
| POST | `/api/admin/assign` | Admin |
| GET/POST | `/api/admin/users` | Admin |
| GET | `/api/audit/logs` | Admin |
| GET | `/api/notifications` | JWT |
| POST | `/api/uploads` | JWT (base64 image) |
| GET | `/api/mpesa/sandbox/auth` | Admin |
| POST | `/api/mpesa/sandbox/stk` | JWT |
| POST | `/api/mpesa/callback` | Public stub |

Validation: required fields, phone `255XXXXXXXXX`, quantity ≥ 1, password length, illegal status transitions → 409.

## Integration design

**Notifications:** `Notify` writes SMS and WhatsApp rows with provider `africas_talking`. If `AFRICAS_TALKING_API_KEY` is empty, status is `queued_sandbox` (no live send). PHP `NotificationService.php` is the interface/adapter sketch for a future worker (retry + `notification_queue`).

**M-Pesa:** sandbox auth token and STK record only. No live debit. Credentials from `.env`.

**Maps:** Leaflet + OpenStreetMap tiles, geolocation and pin. Stored `latitude`/`longitude`. Navigation links to OSM and Google Maps.

## Security design

- JWT HS256 (`JWT_SECRET` in `.env`), TTL 8 hours
- Password hashes `pbkdf2:salt:sha256(salt|password)` (POC-grade, not Argon2)
- Role checks on every mutating route
- SQLite parameterized via quoting helper (POC; migrate to bound params in production)
- Rate limits on login/register
- CORS `*` for local POC only
- Uploads stored under `uploads/` with path recorded in DB
- Do not commit real AT/M-Pesa keys

## Deployment (this PC)

1. Keep `tools/sqlite3.exe` next to the project.
2. Copy `.env.example` → `.env` and set secrets.
3. `.\start.ps1` binds the port given by `APP_PORT` in `.env` (currently **8815**). If HTTP.sys (PID 4) owns it, change `APP_PORT` — that single value drives `server.ps1`, `start.ps1` and `tests/run.ps1`. Prefer `POST /api/admin/shutdown` over killing the process, which is what strands the port.
4. Optional later: XAMPP/PHP when Application Control allows `php.exe`.

## Test plan and latest run

`tests/run.ps1` covers health, login reject, four-role login, RBAC, pickup create, assignment, accept, illegal skip, custody steps, recycler complete, dashboard, audit, notifications, M-Pesa sandbox, lifecycle meta.

**2026-09-09:** Passed=24 Failed=0.

Not a full unit-test framework (Pester/PHPUnit). No automated UI browser suite in this environment (IDE browser tools unavailable).

## Correction plan (original UI vs now)

| Area | Status |
|---|---|
| Working | Auth, pickup CRUD-style flow, assignment, collector/recycler dashboards, admin KPIs/filter/export, timeline, OSM pin, audit, notification persistence, M-Pesa sandbox |
| Partial | Africa's Talking (logged, not live), WhatsApp (same), upload (JSON base64, not multipart), PHP API unused |
| Missing (intentionally Phase 2) | AI recognition, scrap value ML, rewards, certificates, commercial/sustainability dashboards, carbon credits |
| Technical debt | HttpListener port collisions, SQL string building, SHA256-PBKDF2, no background queue worker, leftover PHP tree, root `index.html` is a redirect only |

## Gap analysis and readiness

| Check | Result |
|---|---|
| Buttons call APIs (SPA) | Yes |
| No localStorage as source of truth | Yes (`sessionStorage` token only) |
| Status lifecycle | Implemented and tested |
| Notifications | DB rows; live SMS needs AT key |
| Audit | Working |
| Custody collector → recycler | Tested end-to-end |
| Admin oversight | Working |
| AT / M-Pesa | Sandbox-ready connectors |
| Geolocation | Working in SPA |

**Completion (Phase 1 POC):** about **90%** of the master prompt. Remaining ~10%: live AT delivery, real retry queue, production hash/KMS, bound SQL, dedicated reverse proxy, PHP or Node rewrite, automated UI tests.

**Production readiness:** **not production.** Suitable as a supervisor demo / sandbox POC on localhost. Do not expose the port to the internet.

**Risks:** HttpListener + HTTP.sys leftover ports; single-process server; SQLite file locking; demo passwords in the login form; notification “sent” only if a real AT key is set (unverified against AT sandbox in this run).

**Phase 2 roadmap:** live Africa's Talking + WhatsApp templates; M-Pesa Daraja live after sandbox UAT; replace PowerShell host with PHP/Laravel or Node; Argon2 + HTTPS; AI battery recognition hooks; rewards and certificates; carbon/sustainability reports.
