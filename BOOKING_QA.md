# Sluttestning av kundbokning – 2026-10-11

**Helhetsstatus: inte slutgodkänt.** Databaslogik och automatiserade JavaScript-tester är godkända inom nedanstående omfattning. Visuell webbläsartestning, faktisk mejlleverans och vissa återhämtningsflöden återstår.

## Resultat per funktion

| Funktion | Status | Faktiskt verifierat / begränsning |
|---|---|---|
| PC, alla paket | GODKÄND | 60/180/300 minuter, 49/129/199 kr per plats. Samtliga antal 1–20 i transaktion. |
| PS5, alla paket | GODKÄND | Samma tre paket; 1–2 zoner. Totalt 66 kombinationer för PC och PS5. |
| Antal och stationskoppling | GODKÄND | Rätt antal aktiva kopplingar; 20 PC och 2 PS5 i databasen. |
| Prisberäkning | GODKÄND | Serverns paketpris × antal för alla 66 kombinationer; klientens totalsumma med syntetiska data. |
| Datum och tidszon | GODKÄND | Stockholm-datum, kalenderårsskifte, dag 90 tillåten/dag 91 nekad, passerade datum nekade. |
| Öppettider | GODKÄND | Alla sju veckodagar: öppning tillåten, före öppning nekad, exakt stängning tillåten, efter stängning nekad. Aktiva öppettider hämtas från databasen. |
| Bokningar över midnatt | GODKÄND | Faktiskt kalenderdatum skickas; UI anger +1 dag. 20 PC fullbokade 23:00–02:00; PS5 kan sluta exakt 03:00. |
| Dubbelbokningsskydd | GODKÄND | Extra bokning vid full kapacitet nekad; överlappande direkt stationskoppling nekad av exclusion constraint; intilliggande intervall fria. |
| Samtidiga verkliga klienter / belastning | EJ TESTAD | Typbaserat transaktionslås och databasconstraint granskade/testade, men inga parallella webbläsare eller belastningstest. |
| Blockerade stationer | GODKÄND | Blockering på följande kalenderdag minskar föregående kvälls tillgänglighet; exakt slutgräns frigör stationen. |
| Formulärvalidering | GODKÄND | 24 negativa DB-fall plus 3 telefonfall. Klienttest av ogiltig e-post. Null, fel typ, datum, tid, paket, antal och kontaktuppgifter stoppas. |
| Tillgänglighet vid snabba ändringar | GODKÄND | Syntetiska asynkrona test: gamla svar får inte ersätta nytt datum/val. Nätfel visas separat från fullbokning. |
| Bokningsbekräftelse i sidan | GODKÄND | Syntetiskt lyckat RPC; bekräftelsen använder inskickade uppgifter även om val ändras under väntan. Vald tid rensas efter framgång. |
| Personalavbokning | GODKÄND | Alla 66 testbokningar avbokas via personal-RPC; aktiva stationskopplingar frigörs; anonym avbokning nekas. |
| Kundens egen avbokning | UNDERKÄND | Kundsidan saknar självbetjäning och säker kundtoken. Personalavbokning finns. |
| Supabase/RLS | GODKÄND | RLS på samtliga 10 tabeller; anonym SELECT av bokningar förbjuden; mejltokenverifiering endast service_role. Detta är en avgränsad kontroll, inte en fullständig säkerhetsrevision. |
| Mejlkö och intern autentisering | GODKÄND | Bekräftelse/avbokning skapar två autentiserade pg_net-anrop per test, innan rollback. Rätt intern token accepteras; fel token nekas. |
| Mejlens programlogik | GODKÄND | Båda Edge Functions körda med ersatt DB/Resend: obehörigt anrop, idempotens, mallvariabler, lyckat svar, leverantörsfel, nätfel och felaktigt anrop. |
| Faktisk mejlleverans och mallutseende | EJ TESTAD | Inga mejl skickade. Resends externa mallrendering, inkorg, SPF/DKIM/DMARC och leverans kan inte godkännas av dessa tester. |
| Automatisk återhämtning av misslyckade mejl | UNDERKÄND | Fel registreras och ny intern begäran kan återförsöka failed, men automatisk retry/övervakning och återtagning av fastnad processing saknas. Ingen retry-jobb aktiverades mot kunddata. |
| Bokning efter osäkert nätavbrott | UNDERKÄND | Klienten varnar att bokningen kan ha skapats. Serverbaserad idempotensnyckel för kundens bokningsförsök saknas; manuell kontroll behövs före nytt försök. |
| Mobil, surfplatta, dator – visuell/interaktiv | EJ TESTAD | Webbläsarverktyget stoppades: native credential state kunde inte återupptas säkert. CSS-granskning ersätter inte dessa tester. |
| Publicering och offentlig tillgänglighets-API | GODKÄND | GitHub main uppdaterad; ordinarie booking.html gav HTTP 200 och exakt testad fil. Offentliga read-only RPC gav 20 PC/2 PS5. Edge Functions ACTIVE med JWT och intern token. |
| Publicerat fullständigt kundflöde i webbläsare | EJ TESTAD | Samma webbläsarblockering. HTTP- och källkodskontroll redovisas separat. |
| Tidigare adminfunktioner | GODKÄND | Befintliga automatiserade adminregressioner: kalender, överlapp, DST 23/25 h, rapporter, filter, sortering, betalningsknappar och sessionsrensning. Ingen faktisk betalning ändrad. |

## Åtgärder

- Korrigerat datumet för starttider efter midnatt i availability, bokningsanrop, sammanfattning och bekräftelse.
- Ersatt hårdkodade öppettider med databasens aktiva öppettider och gjort datumgränsen oberoende av besökarens tidszon.
- Säkrat asynkrona paket-/tillgänglighetssvar och återhämtning från nätfel. Bevarat tidigare skydd mot paket med nollpris.
- Tillagt nullkontroller och striktare antal/kontaktvalidering; telefon behöver minst sju siffror och tillåtna tecken.
- Serialiserat stationstilldelning per resurstyp med transaktionslås. Befintligt exclusion constraint kvarstår.
- Korrigerat kontrollen av blockerade tider så att nästa kalenderdags blockering även skyddar bokningar som startar föregående kväll.
- Säkrat mejlwebhooks med separat 256-bitars intern token i Supabase Vault. Token exponeras inte i webbplatsen eller rapporten; JWT-kontroll kvarstår. Ingen kunddata ändrad av migreringarna.
- Kundsidans färger och CSS har inte ändrats i denna granskning.

## Testmetod och säkerhet

SQL-filerna använder BEGIN/ROLLBACK och subtransaktioner. Test-RPC:er skapar både bokning och tillhörande köade HTTP-anrop inom transaktionen, vilka rullas tillbaka innan pg_net kan skicka. Inga befintliga kundbokningar ändras. Uppgifter med qa-isolated@example.com är endast transaktionella testdata.

Efter testerna: **8 befintliga bokningar, 0 kvarvarande testbokningar, 3 tidigare skickade bekräftelser och 1 tidigare skickad avbokning**. Dessa antal är oförändrade. Inga riktiga kundmejl skickades och inga riktiga betalningar ändrades.

Körbara lokala tester:

```
node tests/booking.test.cjs
node tests/email.test.cjs
node tests/admin.test.cjs
```

DB-testfiler: tests/sql/booking-matrix.sql, booking-boundaries.sql, booking-opening.sql och booking-security.sql. SQL-auditfiler i supabase/audits dokumenterar redan tillämpade funktionsändringar; de är inte automatiskt körda CLI-migreringar.

Mejltester ersätter nätverket helt. TypeScriptens begränsade typannoteringar tas bort i testharnessen; Supabase Edge-deploy verifierar den faktiska TypeScript-källan. Klientens JavaScript syntaxkontrolleras separat.

## Kvar för slutgodkännande

- Fungerande webbläsartest av hela kundflödet på mobil, surfplatta och dator, inklusive tillgänglighet, tangentbord och bekräftelsedialog.
- Säker kundavbokning om kunden ska kunna avboka själv.
- Ett uttryckligen godkänt mejltest till en kontrollerad testinkorg samt extern mall-/leveranskontroll.
- Bokningsidempotens vid osäkert nätavbrott och säker automatisk mejlåterhämtning/övervakning.
- Parallellt klienttest och relevanta belastningsgränser.

## Publiceringskontroll

Funktionsändringar publicerade i commit 8d40408fd914d2fb5fc427c701afd56d0e4d6733. Ordinarie https://www.elysiumgaming.se/booking.html matchade den testade filen byte för byte, SHA-256 eaf3411bf72b21c81ccc57ecb45408b615833c155ea4c52844f52ad6ff2398b8. Bekräftelsefunktionen är version 4 och avbokningsfunktionen version 2, båda ACTIVE med verify_jwt=true. HTTP-kontrollen innebär inte att webbläsarflödet är sluttestat.
