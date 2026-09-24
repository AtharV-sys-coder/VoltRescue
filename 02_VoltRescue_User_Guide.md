# VoltRescue — User Guide

**Document 2 of 3** · End-user manual (non-technical)
**Audience:** Citizens, collectors, recycler staff, administrators, support desk
**System version:** VoltRescue POC — Dar es Salaam pilot, Phase 1
**Application address:** `http://127.0.0.1:8815/`
**Companion documents:** `01_VoltRescue_Process_Flow_Guide.md` (business process), `03_VoltRescue_Technical_Design_Handbook.md` (technical)

---

## Table of contents

1. Introduction
2. Getting Started
3. Citizen / User Guide
4. Collector Guide
5. Recycler Guide
6. Admin Guide
7. Notifications
8. Frequently Asked Questions (42)
9. Troubleshooting Guide
10. Support Guide
11. Best Practices
12. Appendix

---

## 1. Introduction

### 1.1 System overview

VoltRescue arranges the safe collection and recycling of spent batteries in Dar es Salaam. You raise a request, a collector comes to your address, and the batteries are delivered to a licensed recycling partner. Every step is tracked and every party is notified.

Everybody uses the **same website**. What you see after you log in depends on your role. There is nothing to install: VoltRescue runs in a normal phone or desktop browser. It is designed for phones first, and it uses a dark theme so it is comfortable to read outdoors and in low light.

### 1.2 Supported users

| Role | Who it is for | What they do |
|---|---|---|
| **Citizen / User** | Households and small businesses | Request pickups, track progress |
| **Collector** | Field agents with vehicles | Accept jobs, collect batteries, deliver to recyclers |
| **Recycler Partner** | Licensed processing companies | Confirm receipt, validate, complete processing |
| **Administrator** | Operations control | Assign work, monitor everything, manage users, report |

### 1.3 Starting the application

The POC runs on a local machine rather than the public internet.

1. Open the `VoltRescue` folder.
2. Right-click `start.ps1` and choose **Run with PowerShell**. A black window opens and stays open — this is the server. Do not close it while people are using the system.
3. Open a browser and go to **`http://127.0.0.1:8815/`**.

> **Do not** open `index.html` by double-clicking it from the folder. That file is only a redirect. The application must be reached through the address above, otherwise nothing will load and no data will save.

### 1.4 Demo accounts

The pilot database is seeded with one account per role. All of them use the password **`VoltRescue!23`**.

| Role | Sign in with |
|---|---|
| Citizen | `citizen@voltrescue.local` |
| Collector (Juma) | `collector@voltrescue.local` |
| Collector (Neema) | `neema.collector@voltrescue.local` |
| Recycler (GreenCycle Dar) | `recycler@voltrescue.local` |
| Administrator | `admin@voltrescue.local` |

> *Screenshot placeholder: `docs/screenshots/01-login.png` — the VoltRescue login screen.*

---

## 2. Getting Started

### 2.1 Registration

Registration is for citizens, collectors, and recyclers. Administrator accounts are created by an existing administrator.

1. Open `http://127.0.0.1:8815/`.
2. Press the **Register** tab.
3. Fill in:
   - **Name** — your full name, or the business name.
   - **Email** — a valid email address, used as your username.
   - **Phone** — Tanzanian format, twelve digits beginning `255`, for example `255712345678`. Do not type `+`, spaces, or a leading zero.
   - **Password** — at least eight characters.
   - **Role** — Citizen, Collector, or Recycler.
4. Press **Create account**.

You are logged in immediately and taken to the screen for your role. A welcome alert is recorded for you.

**If registration is refused:**

| Message | Meaning | What to do |
|---|---|---|
| *Phone must be 255XXXXXXXXX* | Wrong phone format | Remove `+`, spaces, and the leading zero: `0712345678` becomes `255712345678` |
| *Password must be at least 8 characters* | Password too short | Choose a longer password |
| *Phone or email already registered* | The account exists | Use the Login tab, or the reset password tab |
| *Missing name, phone, email or password* | A field is blank | Complete every field |

> *Screenshot placeholder: `docs/screenshots/02-register.png` — the registration form.*

### 2.2 Login

1. Press the **Login** tab.
2. In **Email or phone** type either your email address **or** your phone number — both work.
3. Type your password.
4. Press **Log in**.

You land directly on the right screen for your role: citizens on the pickup request form, collectors on their assignments, recyclers on incoming loads, administrators on the operations dashboard.

Beneath the form, during the pilot only, there is a row of buttons labelled **Citizen, Collector, Recycler and Admin** under the heading "Pilot demonstration accounts". Pressing one signs you straight into that demonstration account, which saves retyping when you need to see the same pickup from more than one point of view. These buttons exist for the pilot and are removed before the system is given to real users.

**Your session lasts eight hours.** After that you will be asked to sign in again, and the system returns you to the sign-in screen by itself rather than showing an error. Closing the browser tab also ends the session — this is deliberate, so a shared phone does not stay logged in.

### 2.3 Password reset

1. On the sign-in screen press the **Reset password** tab.
2. Type the phone number registered to your account.
3. Press **Send reset code**. You will always see a neutral confirmation message, whether or not the number exists — this protects other people's privacy.
4. The reset code is delivered by SMS and WhatsApp. **In the pilot, no live messages are sent**; ask the administrator to read the code from the Alerts records for you.
5. Type the code into the **Code** box, type your new password (at least eight characters) into **New password**, and press **Confirm new password**.
6. Sign in with the new password.

**Codes expire after thirty minutes** and can be used only once. If yours has expired, request another.

### 2.4 Profile management

1. Press your name in the top navigation bar.
2. Change your **Name** or **Email**.
3. Press **Save**.

Your role and phone number are shown but cannot be changed here — they affect access and message delivery, so an administrator must change them for you.

> *Screenshot placeholder: `docs/screenshots/03-profile.png` — the profile screen.*

---

## 3. Citizen / User Guide

### 3.1 How to create a pickup request

1. Log in. You land on **Request pickup**. (If you are elsewhere, press **Request pickup** in the top bar.)
2. **Area** — choose Kariakoo, Kinondoni, Temeke, Ilala, or Ubungo.
3. **Address / landmark** — type the street, building, or a landmark a driver would recognise. Be specific: *"Mtaa wa Msimbazi, opposite the blue mosque, green gate"* is far better than *"Kariakoo"*.
4. **Battery type** — Lead-acid, Li-ion, Mixed household, or Automotive. If the load is mixed, choose **Mixed household** and explain in remarks.
5. **Quantity** — how many batteries. Must be at least one. An approximate count is fine; the collector verifies on site.
6. **Remarks** — anything the collector should know: gate access, opening hours, heavy items, leaking cells, an alternative phone number.
7. **Location on the map** — this is the most important field for a smooth pickup. Either:
   - press **Use my location** and allow your browser to share GPS (best when you are standing at the address), **or**
   - click the map at your address, or drag the pin onto it.
   The map opens over Dar es Salaam. Zoom in until you can see your street before placing the pin.
8. Press **Request pickup**.

You will see a green confirmation showing your **request number** and status, and the screen switches to **Track status**. Write the request number down — support will ask for it.

> *Screenshot placeholder: `docs/screenshots/04-request-form.png` — the pickup request form with the map.*

**If the request is refused:**

| Message | What to do |
|---|---|
| *location, battery_type and quantity (>=1) are required* | Fill the address, choose a battery type, and enter at least 1 |
| *Authentication required* | Your session expired — sign in again |
| *Too many requests. Retry shortly.* | You are submitting too fast; wait a minute |

### 3.2 How to track a request

1. Press **Track status**.
2. Each request appears as a card showing the request number, the address, the current status, a progress bar, and the quantity and type.
3. Press **Open timeline** on any card.

The timeline shows every stage the request has passed through, with the exact time, the person responsible, and any note they added. Below it, **Evidence** shows photos taken by the collector or recycler, if any.

> *Screenshot placeholder: `docs/screenshots/05-track-timeline.png` — a request timeline.*

**Reading the progress bar.** The bar has twelve segments, one for each stage from submission to completion. Filled segments are stages you have passed. If your request has failed or been cancelled, the status text tells you so directly.

### 3.3 How to receive updates

You receive an alert at every change: when the request is submitted, when a collector is assigned, when they accept, when they set off, when the batteries are collected, when the load reaches the recycler, and when processing is complete.

Alerts are sent by SMS and WhatsApp to the phone number on your account, and are always readable in the app under **Alerts** in the top bar.

> **Important during the pilot:** no SMS provider account is connected yet, so no messages arrive on your handset. Every alert is still recorded and visible on the **Alerts** screen. Use that screen as your inbox.

### 3.4 How to contact support

Use **Alerts** and your **timeline** first — most questions ("has anyone been assigned?", "when did they collect?") are answered there.

If you still need help, contact the operations administrator with:
- your **request number**,
- the **status shown** on your screen,
- what you **expected** to happen,
- the **date and time** the problem occurred.

See section 10 for the full support process.

---

## 4. Collector Guide

### 4.1 Login

Sign in with the email or phone your administrator registered for you. You land straight on **Collector assignments**. Bookmark the address on your work phone.

### 4.2 View assignments

The assignments screen lists every job assigned to you, most recently updated first. Each card shows:

- request number and address,
- current status and a progress bar,
- quantity and battery type,
- the citizen's name,
- the GPS coordinates with a **Navigate** link,
- the action buttons available at this stage.

If you have no work, the screen says *No assignments yet*. Assignments come from the administrator; you cannot pick jobs yourself.

> *Screenshot placeholder: `docs/screenshots/06-collector-assignments.png` — the collector assignments list.*

### 4.3 Accept assignment

On a card marked `COLLECTOR_ASSIGNED`, press **Accept assignment**. The status becomes `PICKUP_ACCEPTED`, your acceptance time is recorded, and the citizen is told you are handling the job.

Accept promptly. Until you accept, the operations team does not know whether the job is really covered.

### 4.4 Update status

Move the job forward with the buttons on the card. Each press is recorded permanently with your name and the time — press them when the thing actually happens, not in advance.

| Press this | When | New status |
|---|---|---|
| **Mark COLLECTOR_EN_ROUTE** | You set off towards the address | `COLLECTOR_EN_ROUTE` |
| **Mark PICKUP_COMPLETED** | The batteries are loaded on your vehicle | `PICKUP_COMPLETED` |
| **Mark IN_COLLECTOR_CUSTODY** | You are formally responsible for the load | `IN_COLLECTOR_CUSTODY` |
| **No-show** | Nobody is there, or there is nothing to collect | `NO_SHOW` |

The buttons change as the job progresses — only the next legal step is offered. This is intentional and prevents mistakes.

**Navigate to the pickup.** Press the **Navigate** link on the card. It opens directions to the exact point the citizen pinned, in OpenStreetMap or Google Maps. If a card has no GPS point, phone the citizen using the details on the request.

### 4.5 Upload photos

Evidence photos protect you. Take one of the load at collection and one at handover.

1. Press **Timeline** on the request card.
2. Scroll to **Evidence**.
3. Choose the photo kind: **pickup**, **handover**, or **receipt**.
4. Press to choose a file — your phone offers the camera.
5. Press **Upload evidence**.

The photo appears immediately in the Evidence list, stamped with your name and the time. Maximum size is five megabytes; JPG, PNG, and WebP are accepted.

> *Screenshot placeholder: `docs/screenshots/07-evidence-upload.png` — uploading an evidence photo.*

### 4.6 Transfer to recycler

Once a request is `IN_COLLECTOR_CUSTODY`:

1. On the card, open the **recycler dropdown** and choose the partner receiving the load.
2. Press **Transfer to recycler**.

The system creates a custody transfer record naming you, the recycler, and the date, then moves the request to `TRANSFER_SCHEDULED` and on to `IN_TRANSIT_TO_RECYCLER`. The recycler is alerted that a load is coming.

Drive to the site and hand over the batteries. **Your custody ends only when the recycler presses Confirm receipt** — watch for the status change before you leave, and if it does not appear, ask their staff to confirm on their screen while you are there.

---

## 5. Recycler Guide

### 5.1 Login

Sign in with your company account. You land on **Incoming batteries**.

### 5.2 View incoming transfers

The screen lists loads that concern your company: in transit, received, validated, rejected, and completed. Requests still with citizens or collectors are not shown — you only see loads once a collector has dispatched them to you.

Each card shows the request number, the collecting address, quantity and battery type, and the current status.

> *Screenshot placeholder: `docs/screenshots/08-recycler-incoming.png` — the recycler incoming list.*

### 5.3 Confirm battery receipt

When the collector's vehicle arrives:

1. Find the request marked `IN_TRANSIT_TO_RECYCLER`.
2. Check the physical load against the card: quantity, type, condition.
3. Press **Confirm receipt**.

Status becomes `RECEIVED_BY_RECYCLER` and custody formally transfers to your company at that moment.

**If the load is wrong** — wrong chemistry, badly damaged cells, quantity far from the request — press **Reject** instead. Status becomes `RECYCLER_REJECTED` and the load returns to the collector's responsibility for rescheduling. Reject before you accept the material, not after.

### 5.4 Update processing status

1. **Validate materials** — after weighing, sorting, and inspecting, press this. Status becomes `RECYCLER_VALIDATED`, confirming the load is genuinely processable.
2. **Complete processing** — once the load has entered your processing intake, press this. Status becomes `PROCESS_COMPLETED` and the citizen is told the job is finished.

Complete the job on the same day you take it in, so the operations dashboard reflects reality.

> *Screenshot placeholder: `docs/screenshots/09-recycler-actions.png` — receipt, validate, and complete buttons.*

---

## 6. Admin Guide

### 6.1 Dashboard

Sign in as an administrator and you land on the operations dashboard. It has four parts, top to bottom: a toolbar (search, status filter, Filter, Export CSV), six KPI counters, the request table, and the user management panel.

**The six counters:**

| Counter | Meaning | Act when |
|---|---|---|
| **today** | Requests created today (UTC) | Compare against expected demand |
| **pending assignment** | Waiting for a collector | Anything above zero needs your attention now |
| **assigned** | Assigned, accepted, or en route | Rising and not clearing means collectors are stuck |
| **recycler pending** | In transit or at the recycler awaiting action | Chase the recycling partner |
| **completed** | Fully processed | Your throughput figure |
| **failed** | Cancelled, rejected, no-show, transfer failed, recycler rejected | Investigate every one |

> *Screenshot placeholder: `docs/screenshots/10-admin-dashboard.png` — the operations dashboard with KPI counters.*

### 6.2 Request monitoring

The table shows ten requests per page, newest first, with request number, citizen, location, quantity, status, and the action controls.

- **Search** — type into the search box to match location, citizen name, or battery type, then press **Filter**.
- **Filter by status** — choose any of the seventeen statuses from the dropdown, then press **Filter**.
- **Paging** — **Prev** and **Next** under the table; the row count and page number are shown.
- **Collector workload** — printed beneath the table as each collector's name and their number of open jobs. Use it to balance assignments.

### 6.3 Assignment management

For any request row:

1. Choose a collector from the dropdown in the last column.
2. Press **Assign**.

The status moves to `COLLECTOR_ASSIGNED` and the collector is alerted with the request number and address.

**Reassignment** works the same way: choosing a different collector on an already-assigned request replaces the assignment and clears the previous acceptance, so the new collector must accept for themselves.

### 6.4 Status override

Override is the exception tool. Use it when reality and the system disagree — a collector whose phone battery died, a load recovered after a failed transfer, a request that must be closed administratively.

1. Find the request row.
2. Choose the target status in the second dropdown (it shows the current status pre-selected).
3. Press **Override**.

The change is applied even if it breaks the normal sequence. **It is recorded as an override**, with your name, the old status, the new status, and the time. Use it sparingly and tell the affected collector or recycler what you did.

### 6.5 Audit logs

Press **Audit logs** in the user management panel. The screen lists actions newest-first with time, action, actor, and the record affected.

Recorded actions include: `LOGIN`, `LOGIN_FAILED`, `REGISTER`, `PASSWORD_RESET`, `PROFILE_UPDATE`, `PICKUP_CREATE`, `STATUS_CHANGE`, `USER_CREATE`, `UPLOAD`, `MPESA_SANDBOX`, `MPESA_CALLBACK`, and `ERROR`.

This is the record you use to answer "who did what, and when". Press **Back** to return to the dashboard.

> *Screenshot placeholder: `docs/screenshots/11-audit-logs.png` — the audit log screen.*

### 6.6 User management

The panel below the request table lists every user with name, role, and phone, and provides the creation form.

To create a user: fill in name, phone (`255...`), email, choose the role, optionally set a password (the default `VoltRescue!23` is pre-filled), and press **Create user**. Give the person their password through a private channel and ask them to change it.

You can create administrators here. Keep the number small.

### 6.7 Collector management

Creating a user with the role **collector** automatically creates their collector profile. Collectors appear in the assignment dropdown on every request row and in the workload summary. Use the workload figures to spread jobs fairly and to spot a collector who has accepted work but is not progressing it.

### 6.8 Recycler management

Creating a user with the role **recycler** automatically creates the partner company profile — company name, site location, contact person, and phone. Recyclers appear in the collector's transfer dropdown, so a partner must exist before any load can be sent to them.

### 6.9 Export

Press **Export CSV** in the toolbar to download every request with request number, citizen, location, battery type, quantity, status, and creation time. The file is `voltrescue-requests.csv` and opens directly in Excel. Use it for weekly and monthly reporting.

Locations and names that contain commas or quotation marks are quoted correctly, so a place name such as *Msimbazi, Kariakoo* stays in one column instead of splitting across two.

### 6.10 Message delivery monitoring

Beneath the audit log link the dashboard shows a live summary of the messaging system: how many messages were produced per channel and state, how many are waiting in the retry queue, and whether the platform is running against a **live** provider or in **sandbox** mode. In the POC it will always say sandbox, because no Africa's Talking key is configured.

Press **Process notification queue** to retry queued messages immediately rather than waiting for the next automatic attempt. A short confirmation tells you how many were processed and how many remain. If the pending count keeps climbing, the provider is unreachable and someone should check the credentials and the network.

*Screenshot placeholder: `docs/screenshots/12-notification-queue.png` — the delivery summary and queue control.*

---

## 7. Notifications

### 7.1 SMS

SMS is the primary channel and targets **Africa's Talking**, the preferred vendor for Tanzania. Messages go to the phone number on your account. Every message is stored with its delivery state before any send is attempted.

### 7.2 WhatsApp

WhatsApp runs alongside SMS through the same provider, and each event produces its own WhatsApp record so delivery can be tracked separately per channel. Live WhatsApp sending is switched off in the POC.

### 7.3 Email

**Email is not implemented.** Email addresses are used only as usernames. There is no email notification channel in Phase 1.

### 7.4 The Alerts screen

Every role has **Alerts** in the top bar. It lists your fifty most recent messages with the channel, the delivery state, the message text, and the time.

During the pilot **Alerts is your real inbox**, because no live provider is connected. Delivery states you will see:

| State | Meaning |
|---|---|
| `queued_sandbox` | Stored, nothing sent — no provider key configured (normal in the POC) |
| `sent` | Handed to the provider successfully |
| `failed` | The provider refused or was unreachable; the error is stored and a retry is queued |

> *Screenshot placeholder: `docs/screenshots/12-alerts.png` — the Alerts screen.*

---

## 8. Frequently Asked Questions

**General**

**1. What is VoltRescue?**
A platform for requesting, tracking, and recording the collection of spent batteries in Dar es Salaam, from the household to a licensed recycler.

**2. Do I need to install an app?**
No. It runs in any modern phone or desktop browser.

**3. Which address do I open?**
`http://127.0.0.1:8815/`. Do not double-click `index.html` in the folder — that is only a redirect.

**4. Is it free for citizens?**
Yes. The POC does not charge citizens and does not process any payment.

**5. Does it work on a phone?**
Yes — it was designed phone-first, which is how collectors use it.

**6. Does it work offline?**
No. The server must be running and reachable, because everything is saved in the database rather than on your device.

**7. Which languages are supported?**
English only in Phase 1. Swahili is a Phase 2 candidate.

**Accounts and access**

**8. Can I register as an administrator?**
No. Self-registration allows citizen, collector, and recycler only. An existing administrator creates admin accounts.

**9. Why is my phone number rejected?**
The format must be twelve digits starting `255`, with no `+`, spaces, or leading zero. `0712345678` becomes `255712345678`.

**10. Can I log in with my phone instead of my email?**
Yes. The sign-in box accepts either.

**11. How long does a session last?**
Eight hours, or until you close the browser tab.

**12. I forgot my password. What now?**
Use the **Reset password** tab with your registered phone number. In the pilot, ask the administrator to read the code from the alert records.

**13. Can I change my phone number or role myself?**
No. An administrator must do it, because both affect access and message delivery.

**14. Can two people share one account?**
They should not. Every action is recorded against the account that performed it, so sharing destroys accountability.

**Pickup requests**

**15. How do I request a pickup?**
Log in as a citizen, complete the form on **Request pickup**, set the map pin, and press **Request pickup**.

**16. How accurate must the map pin be?**
As accurate as you can manage. It becomes the collector's navigation target. Zoom in to street level before placing it.

**17. Can I submit a request without GPS?**
Yes, coordinates are optional — but the collector then has only your written address, which slows the pickup.

**18. What is the minimum quantity?**
One battery.

**19. I do not know exactly how many batteries I have.**
Give your best estimate. The collector counts on site.

**20. Can I cancel a request?**
Cancellation is a supported status. Contact the administrator to have it applied; there is no self-service cancel button in Phase 1.

**21. Can I edit a request after submitting?**
No. Contact the administrator, or cancel and submit a corrected request.

**22. How long until a collector is assigned?**
It depends on operations staffing. Administrators are alerted the moment your request arrives.

**23. How do I know the collector is coming?**
The status changes to `COLLECTOR_EN_ROUTE` and you receive an alert.

**Collectors**

**24. Can I choose which jobs I take?**
No. An administrator assigns work. You accept or, if you cannot do it, tell the administrator to reassign.

**25. Why can I only press one button on a card?**
The system only offers the next legal step in the lifecycle. This prevents accidental jumps.

**26. Nobody was at the address. What do I press?**
**No-show**. The administrator then reassigns or cancels the request.

**27. Do I have to upload photos?**
It is not enforced by the software, but it is strongly expected — a photo at collection and one at handover protects you if a load is disputed.

**28. What photo sizes are allowed?**
Up to five megabytes, in JPG, PNG, or WebP.

**29. When does my custody end?**
Only when the recycler presses **Confirm receipt**. Wait for that status change before you leave the site.

**Recyclers**

**30. Why can I not see all requests?**
You see only loads dispatched to your company. Everything else is not your concern and is hidden.

**31. The delivered load does not match the request. What do I do?**
Press **Reject** before accepting the material. The load returns to the collector's responsibility.

**32. What is the difference between confirming receipt and validating?**
Confirming receipt means the load physically arrived and custody passed to you. Validating means you have weighed, sorted, and inspected it and it is genuinely processable.

**Administrators, notifications, and data**

**33. Why do I see no SMS on my handset?**
No Africa's Talking API key is configured in the pilot, so messages are stored with the state `queued_sandbox` and nothing is sent. Read them on the **Alerts** screen.

**34. When will live SMS work?**
As soon as a valid Africa's Talking key is placed in the environment file and the server is restarted. No other change is needed.

**35. Can VoltRescue take payments?**
No. The M-Pesa connector is **sandbox only**. It records a simulated transaction and cannot move real money.

**36. Where is the data stored?**
In a single SQLite database file, `data/voltrescue.sqlite`, inside the project folder. It is the only source of truth.

**37. Is my data lost if I clear my browser?**
No. Only your login token lives in the browser. Every record is in the database.

**38. Can an administrator change any status?**
Yes, using **Override** — and every override is recorded with their name and the time.

**39. Can audit logs be edited or deleted?**
Not through the application. There is no interface for altering audit records.

**40. Can I get the data into Excel?**
Yes. Administrators press **Export CSV** on the dashboard.

**41. Does the system score batteries or estimate their value?**
No. AI recognition and scrap-value prediction are explicitly out of Phase 1 scope.

**42. Are recycling certificates issued?**
Not in Phase 1. Certificates, rewards, and carbon tracking are Phase 2.

---

## 9. Troubleshooting Guide

### 9.1 Login issues

| Symptom | Likely cause | Fix |
|---|---|---|
| *Invalid credentials* | Wrong password, wrong identifier, or account deactivated | Retype carefully; try phone instead of email; ask the admin to confirm the account is active |
| *Too many requests. Retry shortly.* | Too many attempts too quickly | Wait one minute and try again |
| Page will not load at all | The server is not running, or the wrong address | Run `start.ps1` and open `http://127.0.0.1:8815/` |
| *This site can't be reached* / connection refused | The server window was closed, or the port changed | Restart `start.ps1` and check the address it prints in the black window |
| Logged out unexpectedly | Session expired after eight hours, or the tab was closed | Sign in again |
| The map does not appear on the request form | No internet connection, so the map library could not load | The form still works. The pickup point defaults to Dar es Salaam city centre — press **Use my location**, or type the coordinates into the boxes shown in place of the map |
| You are returned to the sign-in screen unexpectedly | Your eight-hour session expired | Sign in again. Nothing you already submitted is lost |

### 9.2 Assignment issues

| Symptom | Likely cause | Fix |
|---|---|---|
| Collector sees *No assignments yet* | Nothing assigned to them yet | The administrator must assign a request |
| *Not assigned to this collector* | Trying to accept somebody else's job | Refresh; ask the admin who owns it |
| *Collector profile missing* | The account has the collector role but no collector profile | Admin recreates the collector via user management |
| Admin dropdown has no collectors | No collector accounts exist | Create at least one collector user |
| Request stuck at *pending assignment* | Nobody has assigned it | Assign a collector from the dashboard |
| Reassignment did not clear acceptance | It does clear it — the new collector must accept | Ask the new collector to press Accept |

### 9.3 Status update issues

| Symptom | Likely cause | Fix |
|---|---|---|
| *Illegal transition X to Y* | Trying to skip a stage | Follow the sequence; only an admin override can skip |
| Expected button is missing | The request is not at the stage that offers it | Check the current status on the card |
| *Collector does not hold this request* | Trying to hand over a load you are not holding | Move the request to `IN_COLLECTOR_CUSTODY` first |
| *request_id and status required* | The page sent an incomplete update | Refresh the page and retry |
| *Request not found* | Wrong request number, or it was never saved | Check the number on the dashboard |
| Status did not change on another person's screen | They are looking at an old page | Refresh — there is no automatic live refresh in Phase 1 |

### 9.4 Notification issues

| Symptom | Likely cause | Fix |
|---|---|---|
| No SMS on the handset | No provider key configured (normal in the pilot) | Read alerts in the app; add an Africa's Talking key for live sending |
| Alerts screen is empty | No events yet for this account | Create or progress a request |
| State shows `queued_sandbox` | Sandbox mode | Expected in the POC |
| State shows `failed` | The provider refused or was unreachable | Check the stored error and the provider credentials; a retry is queued |
| WhatsApp never arrives | Live WhatsApp sending is disabled in Phase 1 | Expected; the record is still stored |

### 9.5 Upload issues

| Symptom | Likely cause | Fix |
|---|---|---|
| *Max 5MB* | The photo is too large | Reduce the resolution or retake at a lower quality |
| *request_id and file required* | No file chosen | Choose a file before pressing upload |
| Upload form is not shown | You are signed in as a citizen | Citizens do not upload; collectors and recyclers do |
| Photo does not display | The file was moved or deleted on the server | Re-upload |
| Camera does not open on the phone | Browser permission denied | Allow camera access in the browser settings |

### 9.6 Dashboard and reporting issues

| Symptom | Likely cause | Fix |
|---|---|---|
| *Insufficient role permission* | Not signed in as an administrator | Sign in with an admin account |
| Search returns nothing | Filter too narrow, or a stale status filter | Clear the search box, set status to *All statuses*, press Filter |
| CSV downloads empty | No requests match | Check that requests exist |
| Counters look wrong | "Today" is counted in UTC, not local time | Expected in Phase 1 |

---

## 10. Support Guide

### 10.1 Who to contact

| Issue | Contact |
|---|---|
| Cannot log in, forgotten password, account changes | Operations administrator |
| Pickup not assigned, collector late, wrong status | Operations administrator |
| Load rejected, recycler dispute | Operations administrator, who involves the recycling partner |
| Server will not start, error messages, technical faults | Technical owner of the pilot (see Document 3) |
| Scope and roadmap questions | Project supervisor — Mr. Menelick Erick |

### 10.2 Information required

Have this ready before you report a problem. Support cannot investigate without it.

1. **Your role and account** (email or phone).
2. **The request number**, if the problem concerns a pickup.
3. **The current status** shown on your screen.
4. **What you did** — the exact button you pressed.
5. **What you expected** to happen.
6. **What actually happened** — the exact message shown, word for word.
7. **The date and time** of the problem.
8. **A screenshot**, if you can take one.

### 10.3 Issue reporting process

1. **Check the timeline and Alerts first.** Most questions about progress are answered there.
2. **Check section 9** of this guide for your symptom.
3. **Report to the administrator** with the eight items above.
4. **The administrator reproduces it** and checks the audit log for the time in question.
5. **Resolution:** either an operational fix (reassign, override, reset a password) or escalation to the technical owner.
6. **Confirmation:** the administrator tells you what was done, and any override is visible in the audit log.

**Priority guidance**

| Priority | Example | Expectation |
|---|---|---|
| High | Nobody can log in; server down; a load is in custody with no record | Immediate |
| Medium | A request stuck unassigned; a status will not advance | Same working day |
| Low | Cosmetic issues, wording, feature requests | Logged for Phase 2 |

---

## 11. Best Practices

### 11.1 For users (citizens)

- Place the map pin precisely at your gate, not just in the neighbourhood.
- Write a landmark in the address: a driver reads it aloud to a passer-by.
- Say in remarks if cells are leaking or damaged — this is a safety matter.
- Keep the request number.
- Do not raise duplicate requests for the same batteries; it distorts the operations queue.
- Store batteries upright, away from children and water, until collection.
- Be reachable on the phone number in your account.

### 11.2 For collectors

- Accept assignments quickly, so operations know the job is covered.
- Press each status **when it happens**, not in a batch at the end of the day.
- Always **Navigate** from the card rather than typing an address from memory.
- Photograph the load at collection and at handover.
- Never leave a recycler site before the receipt is confirmed on their screen.
- Use **No-show** honestly — it is data, not a failure.
- Carry appropriate protective equipment for damaged or leaking cells.

### 11.3 For recyclers

- Inspect before confirming: once you confirm receipt, custody is yours.
- Reject at the gate, not after unloading.
- Validate and complete on the same day so the dashboard reflects reality.
- Keep your company contact details current with the administrator.

### 11.4 For administrators

- Clear the **pending assignment** counter to zero every working day.
- Use the collector workload line to balance jobs rather than always assigning the same person.
- Treat **Override** as an exception tool and note why in the audit trail.
- Review the **failed** counter daily; each one is either a service problem or a data problem.
- Export CSV weekly for reporting and as an informal backup.
- Change the seeded demo passwords before any real pilot use.
- Keep the number of administrator accounts small.
- Never post real Africa's Talking or M-Pesa credentials into chat or documents.

---

## 12. Appendix

### 12.1 Status definitions

| Status | Meaning |
|---|---|
| `REQUEST_SUBMITTED` | The citizen has raised the request |
| `PENDING_ASSIGNMENT` | In the operations queue awaiting a collector |
| `COLLECTOR_ASSIGNED` | A named collector has been given the job |
| `PICKUP_ACCEPTED` | The collector has accepted it |
| `COLLECTOR_EN_ROUTE` | The collector is travelling to the address |
| `PICKUP_COMPLETED` | The batteries have been handed over at the door |
| `IN_COLLECTOR_CUSTODY` | The collector formally holds the material |
| `TRANSFER_SCHEDULED` | A recycling partner has been chosen |
| `IN_TRANSIT_TO_RECYCLER` | The load is on the road to the recycler |
| `RECEIVED_BY_RECYCLER` | The recycler physically has the load |
| `RECYCLER_VALIDATED` | Materials weighed, sorted, and accepted |
| `PROCESS_COMPLETED` | The job is finished and closed |
| `CANCELLED` | Called off by the citizen or operations |
| `REJECTED` | Declined by operations |
| `NO_SHOW` | Nothing to collect on arrival |
| `TRANSFER_FAILED` | Delivery to the recycler did not succeed |
| `RECYCLER_REJECTED` | The recycler refused the load on inspection |

### 12.2 Role definitions

| Role | Can do | Cannot do |
|---|---|---|
| **Citizen** | Register, log in, submit requests, track own requests, read own alerts, edit own profile | See others' requests, assign collectors, change status, upload evidence, open admin screens |
| **Collector** | Log in, view own assignments, accept, update status, upload evidence, transfer to a recycler, navigate | Create requests, assign work, see unassigned jobs, override status, open admin screens |
| **Recycler** | Log in, view incoming loads, confirm receipt, reject, validate, complete, upload receipt evidence | See requests not sent to them, assign collectors, override status, open admin screens |
| **Administrator** | Everything above, plus create users, assign and reassign collectors, override status, read audit logs, export CSV, check the M-Pesa sandbox | Move real money, delete audit history |

### 12.3 Glossary

| Term | Meaning |
|---|---|
| **Africa's Talking** | The SMS and WhatsApp provider VoltRescue is built to use |
| **Alert** | A notification record shown in the app and sent by SMS/WhatsApp |
| **Assignment** | The link between a request and the collector responsible for it |
| **Audit log** | The permanent, unalterable record of who did what and when |
| **Chain of custody** | The documented sequence of who physically held the batteries |
| **Custody transfer** | The record of a load moving from a collector to a recycler |
| **CSV** | A spreadsheet file format; the export opens in Excel |
| **Dashboard** | The administrator's operations screen |
| **Evidence photo** | A picture uploaded to prove the state of a load |
| **GPS pin** | The map marker giving the exact pickup coordinates |
| **KPI** | Key performance indicator — the counters on the dashboard |
| **Lifecycle** | The fixed sequence of statuses a request passes through |
| **M-Pesa** | Mobile money service; connected in **sandbox only**, no real money |
| **Override** | An administrator forcing a status outside the normal sequence |
| **POC** | Proof of concept — a working demonstration, not a production system |
| **Recycler partner** | A licensed company that processes the batteries |
| **Request number** | The unique identifier of a pickup, shown as `#12` |
| **Role** | Citizen, collector, recycler, or administrator |
| **Sandbox** | A test mode that records actions without real-world effect |
| **Session** | The eight-hour period you stay signed in |
| **SQLite** | The database file where all VoltRescue data lives |
| **Status** | The current stage of a request |
| **Timeline** | The list of every status a request has passed through |

---

*End of Document 2. For the business process see `01_VoltRescue_Process_Flow_Guide.md`. For technical detail see `03_VoltRescue_Technical_Design_Handbook.md`. For the readiness assessment and roadmap see `04_VoltRescue_Final_Readiness_Report.md`.*
