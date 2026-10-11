# Elysium admin audit — 2026-10-11

Scope: admin.html, public booking flow, Supabase project jbwebwdockhgivltgjdu.

## Fixed

- Light blue/white admin theme; readable status colors, responsive controls, visible keyboard focus and reduced-motion support.
- Supabase bookings fetched in stable, ordered 500-row pages; totals no longer silently stop at the API's row cap.
- Failed or unavailable report data displays an unavailable state instead of invented zero totals. Dashboard totals also clear after fetch failure.
- Stale requests cannot repopulate an admin session after sign-out or supersede a newer refresh. Protected booking details are cleared on sign-out.
- Payment controls reset for each booking and disable for cancelled/refunded bookings.
- Completing a booking requests the updated row; a denied/no-row update cannot appear successful.
- Station calendar uses actual booking/resource timestamps, includes previous-day bookings continuing after midnight and handles Stockholm's 23/25-hour DST days.
- Overlap is based on exact intersecting intervals, not the number of bookings occupying an hour. Adjacent bookings are not conflicts.
- PC01–PC20 and PS5-01/02 normalize to the 22 calendar stations. Missing or mismatched resource assignments are flagged.
- Occupied calendar cells open booking details. Modal includes dialog attributes and Escape handling.
- CSV remains semicolon-delimited with UTF-8 BOM and escaped quotes; formula-leading values are neutralized. Download URL cleanup is deferred.
- Database permission migration restricts authenticated direct booking updates to status. Direct status changes can only complete a booking; cancellation uses its checked RPC and payment changes use the audited RPC. Database triggers are not callable directly by public/anon/authenticated.

## Verification performed

- JavaScript syntax: node --check; no duplicate HTML IDs.
- Node VM regression suite: overnight visibility, DST 23/25-hour boundaries, true/false overlaps, cancellation, PS5 mapping, report sums and exclusion of cancelled bookings, unavailable data, payment controls, session cleanup, search, payment/date filters, price sorting, HTML escaping and CSV formula guard.
- Real booking/payment/cancellation RPCs tested using temporary QA data in subtransactions which were deliberately rolled back. Assertions covered PC price, resource assignment, payment audit and resource release.
- Full 20-PC group and 2-PS5 group creation, group pricing, zero remaining PC availability, rejected overlap and overnight ending date asserted in rolled-back transactions.
- No customer emails sent by tests: all generated database rows and pg_net queue inserts were rolled back before transaction commit. Follow-up confirmed zero QA bookings and unchanged total booking count (8).
- Live database has 20 active PCs and 2 active PS5 stations, active priced packages and overnight opening hours.
- RLS enabled on all 10 public tables. Anonymous booking reads are denied at table privileges. Authenticated role without staff identity sees zero bookings.
- Authenticated UPDATE grants checked after migration: status only. Trigger function execute permission revoked and verified.
- Email Edge Function source reviewed: server-held credentials, idempotency keys, atomic claims, failure records. Existing logs show 3 confirmations and 1 cancellation marked sent; this means provider accepted, not verified inbox delivery.
- Public admin login screen opened in cloud browser before deployment. Public release confirmation is recorded in the delivery message.

## Remaining verification / limitations

- Actual staff browser login/logout, authenticated UI interactions, focus management, and visual checks at mobile/tablet/desktop sizes require a signed-in browser session. Not certified complete until these pass.
- CSS responsiveness reviewed in source; this is not equivalent to visual device testing.
- No new real email delivery tested. No automatic retry job added; stalled processing/retry recovery needs further work before claiming resilient email delivery.
- Email endpoints accept the configured legacy JWT at the platform gateway and check Bearer presence internally; review a dedicated webhook secret and request authorization before widening exposure. No credentials printed or changed.
- Supabase advisor warns that leaked-password protection is disabled. Review Auth settings and plan support; not changed in this audit.
- Intentional SECURITY DEFINER RPCs for public availability/booking and authenticated staff operations remain. Their warning notices are not automatically proof of a vulnerability; checked staff RPCs validate the active profile.
- Calendar explicitly displays bookings, not blocked_times or live Gizmo state. If blocked-time planning is required, that UI remains to be implemented.
- Multi-request pagination is not a transaction snapshot; an external concurrent booking update during a large refresh can require another refresh.
- Public availability currently treats booking_date as the opening day's date; a new start after midnight is not accepted as part of the preceding opening day. Existing overnight bookings are handled correctly.

## Repeat checks

Run `node tests/admin.test.cjs` from the repository root. Database migration is recorded under supabase/migrations and was applied non-destructively without deleting customer data.
