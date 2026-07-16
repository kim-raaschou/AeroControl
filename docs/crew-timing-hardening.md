# Crew-rapport: Retning & hårdhed for AeroControl

> Faciliteret 4-deltager-dialog om simplificering og fastholdelse af kvalitet,
> med fokus på timing mellem AeroSpace og AeroControl.

**Spørgsmålet:** "Alle tests er grønne, men produktet virker ikke som forventet.
Er der dark sides i timingen mellem AeroSpace og AeroControl?"

**Kort svar: Ja — og det er ikke tilfældigt. De grønne tests *kan per konstruktion
ikke* fange dem.**

Fire deltagere. Hver sin linse. Alle påstande er grundet i koden.

---

## 👤 Deltager 1 — Ada (Systemarkitekt, timing)

Kernearkitekturen er faktisk *rigtig*: ren reducer (`updateOverview`), AeroSpace som
eneste sandhed, `cancel-and-reload + generation stamp` uden klæbende flags. Problemet
er ikke logikken — det er **manglende og tabte inputs på kanterne**. Fem konkrete dark
sides:

1. **Intet `window-closed` event → døde tiles.** (Målt definitivt, checkpoint 007.)
   En baggrundsrude der lukkes uden fokusskifte giver *nul* events →
   `requestRefresh()` fyrer aldrig → tile bliver hængende for evigt. Dette er *det*
   kanoniske "virker i test, ikke i produkt".
2. **Reconnect-hul** (`startSubscribeListener`): når streamen dropper (AeroSpace
   genstart, `brew upgrade`, crash), sover den 1s og **re-subscriber — men reloader
   ikke**. Alt der skete i mellemtiden er tabt og bliver aldrig forsonet før næste
   tilfældige event. Ingen "reload på reconnect".
3. **App-quit race** (`.appTerminated` → `.refresh`): `didTerminateApplication` kan
   fyre *før* AeroSpace's `list-windows` har droppet ruden → reload læser stale liste
   → tile overlever, og der kommer intet opfølgende event. Ét engangs-reload, ingen
   bounded retry.
4. **Generation-stamp fintryk:** "nyeste *request* vinder — ikke nyeste *autoritative
   state*". Gen N kan have et gyldigt resultat der smides væk fordi Gen N+1 overtog og
   så fejlede (`try?` sluger fejlen → `return` uden apply). Kombineret med et tabt
   event: du sidder fast på stale state.
5. **Kold-start fokus-hul:** `OverviewResult` bærer ingen fokus;
   `focusedWorkspace/WindowId` sættes *kun* fra events. Ved cold start er fokus-pladen
   forkert indtil brugeren skifter workspace én gang.

**Pointe:** hærd *kanterne* (event-komplethed + reconnect-forsoning), ikke kernen.

---

## 👤 Deltager 2 — Björn (Test & kvalitet)

Her er hvorfor "grøn" lyver. **Alle** store-/timing-tests kører på `FakeRunner` hvor
`run()` returnerer synkront og øjeblikkeligt, og events **håndinjiceres**. De validerer
*reducer + wiring* — aldrig *rigtig timing*.

Se `refreshAppliesFetchedState` og `reloadMirrorsAerospace`: de består ved at **sende
et `binding-triggered` event** for at trigge reloaddet. Men den ægte dead-tile-fejl er
*præcis når intet event sendes*. Testen indkoder happy-path'ens stimulus, så den kan
**aldrig** fange den manglende-stimulus-bug. Grøn for evigt, brudt i virkeligheden.

Det der mangler helt:

- **Ingen integrationslag.** Den ægte `AerospaceProcessRunnerCli` (subprocess, 2s
  timeout, reap, cancel, reconnect) testes stort set ikke — en flaky rigtig-proces-test
  blev endda *fjernet* (checkpoint 006).
- **Ingen "reconnect → reload"-test.** Ingen "event-fravær → forson alligevel"-test.
- Testene er *determinismeteater*: de beviser invarianter (`render-once`,
  `mirror-verbatim`) der er sande *givet de injicerede events* — de modellerer aldrig
  at event-**kilden selv er ufuldstændig**.

**Pointe:** I tester reduceren grundigt og kilden slet ikke. Green ≠ correct når fejlen
bor i input-timingen.

---

## 👤 Deltager 3 — Clara (Simplicitet / "krumspring"-vagthund)

Jeg advarer mod den nemme fejlreaktion: at fikse dette med **polling** eller en
**AX-observer-doorbell** (Accessibility-permission + observer-lifecycle). Det er
krumspring. Rodårsagen er **ét manglende signal**, ikke for lidt kode.

Den *simpleste korrekte* fix er at rette **kilden**: jeres egen `window-closed` PR
#2181. Push, nul polling, nul permission. I AeroControl er det **én enum-case →
`.refresh`**. Det er "forenkl ved at fikse kilden".

Mens PR'en venter (stadig OPEN), er den næstbedste minimale fix **reconnect-reload**
(~2 linjer) — den lukker dark side #2 og #4 delvist gratis, uden ny maskineri.

Småting der *kan* trimmes (lav risiko): `fireLoadedAfterEffects` DispatchQueue-hop,
dobbelt `DispatchQueue.main.async` i `apply`, og de tavse `try?`. Men kvalitetsrisiko >
linjeantal her — rør dem kun hvis vi alligevel er i filen.

**Pointe:** Kernen skal *ikke* vokse. Tilføj ét manglende input + ét reconnect-reload.
Modstå doorbell/polling.

---

## 👤 Deltager 4 — Dmitri (Produkt / oplevet pålidelighed)

Det brugeren faktisk oplever: **døde tiles, fokus der ikke opdaterer ved start, et klik
der tavst gør ingenting** (fejlet `moveWindow`/`closeWindow` sluges af `try?`). Alle tre
er *timing/eventing*-huller — ikke logikfejl. Derfor fanger unit-tests dem ikke, og
derfor føles det som "grønt men virker ikke".

Acceptkriterier bør defineres i **observerbar adfærd under rigtig timing**, ikke i
reducer-invarianter. Fx: *"en baggrundsrude der lukkes forsvinder fra overview inden
for X ms"* og *"efter AeroSpace-genstart er overview korrekt uden brugerinput"*. Ingen
af de to er testet i dag.

**Pointe:** Mål kvalitet på hvad brugeren ser efter et event (eller et *manglende*
event), ikke på om reduceren er ren.

---

## 🤝 Faciliteret konsensus

**Retningen er ikke "mere kode" — det er "hærd kanterne, hold kernen ren, og test
kilden."** Enighed på tværs af alle fire:

| # | Handling | Linse | Omfang | Polling? |
|---|----------|-------|--------|----------|
| **1** | Forbrug `window-closed` (PR #2181) → `.refresh`. Byg mod fork indtil merged. | Ada+Clara | 1 enum-case | Nej |
| **2** | **Reload-på-reconnect** i `startSubscribeListener` (også ved første subscribe) | Ada | ~2 linjer | Nej |
| **3** | App-quit **bounded event-drevet retry** (eller lad #1 dække det når shipped) | Ada+Dmitri | lille | Nej |
| **4** | **Integrationstest-lag**: kør ægte `AerospaceProcessRunnerCli` mod et lille fake `aerospace`-shellscript (fixture-binary) → deterministisk subprocess/timeout/reconnect | Björn | nyt tyndt lag | — |
| **5** | Encode *failure*-stimulus som invariant: "intet event → forson alligevel via reconnect/close" | Björn | test | — |

**Bevidst fravalgt (YAGNI):** polling, AX-observer-doorbell, at genindføre
coalescing-maskineri.

**Kvalitet fastholdes ved** at flytte tyngdepunktet fra "reducer-invarianter" til
"adfærd under rigtig/manglende timing" — det er præcis det hul der lod produktet fejle
med grøn suite.

**Anbefalet start:** #2 (reconnect-reload) — 2 linjer, nul risiko, lukker et reelt hul
i dag og kræver ikke at vente på PR-merge. Derefter #4 (integrationslaget), så vi
faktisk *fanger* denne klasse fremover.

---

## Referencer i koden

- `Sources/AeroControlKit/State/OverviewStore.swift` — `startSubscribeListener`
  (reconnect-hul), `startTerminationListener` (quit-race), `requestRefresh`
  (generation-stamp), `runAction` (tavse `try?`).
- `Sources/Common/Domain/OverviewUpdate.swift` — reducer; `.appTerminated → .refresh`.
- `Sources/Common/Aerospace/AerospaceEventParser.swift` — `AerospaceEventName`-sæt
  (INTET `window-closed`).
- `Tests/AeroControlKit/OverviewStoreTests.swift` — alle timing-tests på
  `FakeRunner`/`FakeBridge`.
- Checkpoint 006 (sync-deadlock), 007 (window-closed PR).
- AeroSpace PR #2181 (upstream, OPEN): "Add window-closed subscribe event".

---

## 🔁 Runde 2 — Én samlet input-stream (én indgang til AeroControl)

> **Oplægget:** "Vi har vel 2 streams i dag — én fra AeroSpace og én fra den native
> macOS-bridge. Kan vi samle dem til én stream, så der kun er én indgang til
> AeroControl? Og skal 'vores' egne events — luk app, flyt app — også komme derfra?
> Jeg tænker det kan blive lækkert ift. integrationstest."

**Vigtigt fund (grundet i koden):** reduceren har *allerede* én samlet input-type —
`OverviewInput { .loaded(OverviewResult); .event(AerospaceEvent); .action(AeroControlAction) }`
— og `appTerminated` fra den native bridge går endda ind som et `.event`. Så
*logik-indgangen er allerede forenet*. Det der er splittet, er **driverne**:

| Driver i dag | Sti | Task/kald |
|---|---|---|
| AeroSpace subscribe | `startSubscribeListener` → `handleEvent` → `apply(.event)` | detached task |
| Native bridge (app-quit) | `startTerminationListener` → `handleEvent(.appTerminated)` → `apply(.event)` | separat task |
| Brugerhandlinger (flyt/luk) | `dispatch(action)` → `apply(.action)` | synkront kald |
| Refresh/initial load | `requestRefresh` / `initialLoad` → `apply(.loaded)` | internt task-kald |

Fire producenter kalder `apply` ad hver sin vej. Idéen: én privat
`AsyncStream<OverviewInput>` som **alle fire** *yield'er* ind i, og **én** consumer-loop
`for await input in inbox { apply(input) }`.

### 👤 Ada (Arkitekt)
Det er lærebogs-TEA: én "Msg"-inbox. Fordi reducer-inputtet allerede er forenet, er
dette ikke ny arkitektur — det er at fjerne fire divergerende driver-stier og lade dem
møde én serialiseret kø. Gevinst: **deterministisk rækkefølge på tværs af kilder** (i
dag kan subscribe- og termination-tasken interleave uforudsigeligt) og ét sted at
observere. Den *lækre* endestation: lad også effekt-*resultater* (refresh → `.loaded`,
`runAction` → `.loaded`) komme retur *som inputs* i stedet for at kalde `apply` direkte.
Så bliver storen `f(inputsekvens) → (model, outputs)` — en ren funktion af sin kø.

### 👤 Björn (Test)
Dette er **selve unlock'et** for integrationstest. Med én indgang bliver en test:
"script en sekvens af typede inputs (fra *begge* kilder) + fake effekt-svar, assert
`model` + opsamlede `outputs`". Nu kan jeg endelig teste den **utestede klasse**:
interleavings mellem kilder (app-quit *før* aerospace-eventet), reconnect-huller, og
"event-fravær → forson alligevel". Hvis resultater også kommer retur som inputs, får jeg
**replay/golden-tests** næsten gratis. Det er præcis det lag der manglede.

### 👤 Clara (Simplicitet)
Grønt lys — *men* hold det til den tasteful minimum. Den **gode** version: én
`AsyncStream.makeStream()`, fire `yield`-steder, én loop; `dispatch` og `handleEvent`
kollapser, og de spredte `apply`-kald forsvinder → **færre linjer, ikke flere**. Den
**forkerte** version (krumspring) er at bygge en message-bus / event-store / persistens
oven på det. Vi skal ikke have replay-*infrastruktur* i produktionskoden — kun den ene
kø. Effekt-fortolkeren beholdes uændret; eneste ændring er at resultater *poster tilbage*
i køen i stedet for at kalde `apply` direkte.

### 👤 Dmitri (Produkt)
Den brugervendte gevinst er indirekte men reel: reconnect-reload, quit-race- og
close-event-fixene hægter alle på **ét** observerbart søm. Og den tavse handling-fejl
bliver synlig: hvis `runAction`-resultatet kommer retur som et input, kan en fejl blive
et input som UI/reducer kan reagere på — i stedet for at forsvinde i et `try?`.

### 🤝 Konsensus (runde 2)
**Ja — det er interessant og på linje med retningen: ingen ny funktionalitet, men den
enkeltting der gør *ægte* integrationstest let.** Minimal form:

1. Én privat `AsyncStream<OverviewInput>` (inbox) oprettet i `init`.
2. Én consumer-loop på `@MainActor`: `for await input in inbox { apply(input) }`
   (fokus-notifikationen flyttes til efter-apply baseret på inputtet).
3. Producenterne bliver rene *yielders*:
   - subscribe: `line → parse → yield(.event(event))`
   - termination: `yield(.event(.appTerminated))`
   - `dispatch(action)`: `yield(.action(action))`
   - refresh/initialLoad-resultat: `yield(.loaded(result))` (i stedet for `apply` direkte)
4. Effekt-fortolkeren uændret; effekter der producerer nye inputs poster tilbage via
   inbox'en → **én indgang** bevares.

**Vagtplanker:** ingen bus/persistens/event-sourcing-ramme; nettolinjetal skal *falde*;
`requestRefresh`'s "newest wins" bevares (generation-stamp før `yield`, eller drop i
loop'en); serialisering via den ene loop fjerner reentrancy-risikoen ved `apply`.

**Rækkefølge:** (a) refaktorér til én inbox (adfærdsbevarende, alle 96 tests skal blive
grønne), derefter (b) byg integrationstest-laget ovenpå det ene søm, og først (c)
tilføj kant-hærdningen (reconnect-reload m.fl.) *med* dækkende integrationstests.

---

## 🎨 Runde 3 — Flyt overlayet ind i SwiftUIs observationsgraf, drop det manuelle diff-lag?

> **Oplægget:** Er storens manuelle "diff + gentegn"-lag korrekt, når vi næsten altid
> genlæser alt? Er der noget vundet ved ikke bare at lade SwiftUI gentegne overviewet?

**Fund (grundet i koden):** `AeroControlPanel` bruger *allerede* `@Bindable var state: OverviewStore`
og `OverviewStore` er `@Observable`; panelet læser `state.model.workspaces/monitors/icons`
direkte. Alligevel gentegnes der manuelt via `.contentChanged` → `OverlayWindowManager.refreshPanel()`
→ `hostingView.rootView = makePanel()`, fordi den **manuelt-hostede `NSHostingView`** (én pr.
overlay, uden for SwiftUIs normale scene-graf) ifølge kommentaren *ikke auto-observerer*
`@Observable`-ændringer. Storens `apply` beregner desuden `contentChanged = newState != model`
for at undertrykke no-op-reloads (anti-flimmer; vogtet af `rapidRefreshesRenderOnce`).

### 👤 Ada (Arkitekt)
Det manuelle diff+rebuild-lag eksisterer *kun* som kompensation for at være uden for
observationsgrafen. Da panelet allerede er `@Bindable`, er meget af pluммbing'en redundant
**hvis** `NSHostingView` (eller `NSHostingController`) auto-observerer på vores target
(macOS 26). To ting skal dog blive: (1) `.monitorsChanged`/`.workspaceFocused`/`.loaded` er
*vindues*-management (opret/flyt/afslør NSPanel'er), ikke rendering — de forbliver; (2)
`availableWidth/Height` (shrink-to-fit) er en almindelig `let`, ikke observerbar, så en eksplicit
rebuild ved *skærm*-skift skal bestå. Rendering-diff'et kan derimod formentlig kollapse.

### 👤 Björn (Test)
Advarsel: dette er *lærebogseksemplet* på "grønne tests fanger det ikke". Alle vores
store-tests forbliver grønne uanset — risikoen bor 100% i hosting-sømmet (auto-observation,
intrinsic-size, reveal-koreografi), som testene aldrig rører. Krav hvis vi gør det: (a) en
**manuel live-verifikations-checkliste** (åbn/luk/flyt vindue, multi-monitor, follow-focus,
shrink-to-fit, reveal/hide, ingen flimmer ved no-op); (b) **bevar no-op-undertrykkelsen** —
`@Observable` invaliderer ved *tildeling*, ikke ved ulighed, så en gentildeling af en *ens*
model ville gentegne. Erstat diff'et med en vogtet tildeling `if newState != model { model = newState }`
(1 linje) så `render-once`-invarianten ikke regredierer.

### 👤 Clara (Simplicitet)
Principielt stærkt ja: det fjerner et helt output (`.contentChanged`), en metode
(`refreshPanel`) og en diff-gren — **LOC og kompleksitet falder** (letter også metrics-loftet).
Men: ingen ny abstraktion — læn dig på framework'et. Et skift til `NSHostingController` (hvis
bare `NSHostingView` viser sig upålidelig) er en acceptabel minimal pris, ikke krumspring. Og
den vogtede tildeling er *mindre* kode end det nuværende diff+emit+refresh-kredsløb.

### 👤 Dmitri (Produkt)
Brugervendt opside: SwiftUIs egen finkornede diff bevarer view-identitet, hover, drag og
animationer i stedet for at smide hele `rootView` væk på hver ændring — potentielt *glattere*.
Brugervendt risiko: en subtil render-regression (stalе panel, forkert størrelse, reveal-glitch).
Netto positivt **kun** hvis verificeret live; ellers er det nuværende "kedeligt og virker".

### 🤝 Samlet anbefaling (Runde 3)
**Adoptér retningen — men bag en spike + live-verifikation, ikke som blind refaktor.**

1. Lad panelet gentegne via `@Observable`-auto-observation (skift til `NSHostingController`
   hvis bare `NSHostingView` er upålidelig på macOS 26 — verificér empirisk *først*).
2. Fjern `.contentChanged` + `refreshPanel()`. Erstat `apply`'s diff med vogtet tildeling
   `if newState != model { model = newState }` (bevarer no-op-undertrykkelse / render-once).
3. **Behold** `.monitorsChanged` / `.workspaceFocused` / `.loaded` (vindues-management) og en
   eksplicit panel-rebuild **kun** ved skærm/available-size-skift.
4. Verificér live mod checklisten (Björn). Adoptér kun ved rent resultat.

**Forventet payoff:** færre bevægelige dele, LOC/kompleksitet ned (letter loftet), finkornede
UI-opdateringer. Risiko indkapslet i hosting-sømmet — som vi verificerer *manuelt*, fordi
tests ikke kan. **Storen bevares** (fokus-retention, ordering/newest-wins, icon/monitor-cache
ligger stadig dér) — det er *diff+rebuild-laget*, ikke storen, der forenkles væk.

---

## Runde 3 — Spike-resultat (branch `spike/swiftui-observation`)

**Hypotese bekræftet: `NSHostingView` (vores `InteractiveHostingView`) auto-observerer
`@Observable`-modellen på macOS 26.**

**Spike-metode (ikke-destruktiv, isolerende):** `refreshPanel()` blev neutraliseret til en
no-op, så den *eneste* mulige content-opdateringsvej var auto-observation. Bygget, installeret
og kørt live. Panelet opdaterede stadig åbn/luk/flyt/fokus live → sømmet observerer selv.

**Herefter: den rigtige oprydning gennemført.**
- `apply`: diff+`emit(.contentChanged)` erstattet af vogtet tildeling `if newState != model { model = newState }` — bevarer no-op-undertrykkelse (nu load-bearing, da `@Observable` invaliderer på *tildeling*, ikke ulighed).
- `OverviewOutput.contentChanged` fjernet.
- `AeroControlApp`: `.contentChanged`-grenen fjernet.
- `OverlayWindowManager.refreshPanel()` fjernet (dødt).
- Bevaret: `.monitorsChanged` / `.workspaceFocused` / `.loaded` + `syncWindows`' eksplicitte
  rebuild ved skærm/available-size-skift (`availableSize` er ikke-observerbar).
- Tests: de 2 `.contentChanged`-tests omskrevet til at måle den *ægte* ting — `@Observable`
  model-invalideringer via `withObservationTracking` (`ModelInvalidationCounter`). No-op-burst
  invaliderer stadig præcis 1 gang.

**Resultat:** alle 109 tests grønne. Kompleksitet 412 → 408. Diff+rebuild-laget forenklet væk;
storen bevaret. Multi-monitor follow (uændret, styret af `syncWindows`) mangler stadig live-verifikation når 2 skærme er tilgængelige.

---

## Runde 4 — Skal storen helt væk? ("ingen store → ingen state", forventet ~35% mindre LOC)

**Oplæg (Kim):** Ideen var at fjerne `OverviewStore` helt og køre ren `@Observable` — hvis ingen
store, så ingen state. Forventning: ~35% mindre LOC.

### 👤 Ada (Arkitektur / timing)
Præmissen har en fælde: **`@Observable` *er* state.** En `@Observable class` er per definition
en tilstandsholder. "Ren `@Observable`" fjerner ikke storen — det *omdøber* den til ViewModel.
Det afgørende er ikke navnet, men at AeroSpace er en **ekstern proces**. Noget skal uanset hvad:
spawne CLI-subprocesser, parse JSON, holde subscribe-strømmen i live med genforbind, reconcile
mod virkeligheden, retry ved opstart, kollapse bursts (newest-wins), cache ikoner, mappe
monitorer til NSScreen. Det er ~250 linjer **uundgåelig** adapter-/IO-logik. Den flytter, den
forsvinder ikke. Kun ~5 linjer er egentlige felt-erklæringer ("staten").

### 👤 Björn (Test / kvalitet)
Og pas på: det er netop den logik der er timing-følsom — genforbind uden reload, dobbelt-refresh,
stale-generation. Det er dér "grønne tests, produktet virker ikke" bor. Fjerner vi "storen" og
smører logikken ud i views/closures, **mister vi det ene testbare søm** vi lige byggede
(single-ingress inbox). En integrationstest kan i dag drive HELE systemet gennem `send()`. Spreder
vi state ud i flere `@Observable`-viewmodels med hver sin livscyklus, kan vi ikke længere teste
ordering deterministisk. Det ville være et **kvalitets-tilbageskridt** forklædt som forenkling.

### 👤 Clara (Enkelhed)
Jeg vil normalt være fortaler for at slette — men "mindre LOC" må ikke blive et mål i sig selv.
Storen er 308 linjer, ~11% af kodebasen. Selv en aggressiv sanering giver ~40-80 linjer *ceremoni*
væk (se nedenfor). **35% (~1000 linjer) findes ikke i storen.** De ligger — hvis nogen steder — i
UI-kortene (~830), window-plumbing (~365) og `QuitTriggerController` (228). At jagte 35% i storen
er at lede efter nøglerne under gadelygten.

### 👤 Dmitri (Produkt)
Produktrisiko ved at rive storen ud: vi bytter et *kedeligt-men-virker* centrum for en spredt
graf af observerbare objekter, hvor en subtil timing-regression (stale panel, forkert skærm,
reveal-glitch) er svær at få øje på og svær at teste. Opsiden (færre linjer) er lille og forkert
lokaliseret; nedsiden (regression i det der endelig virker) er reel. **Ikke værd at gøre som
"big bang".**

### 🤝 Samlet anbefaling (Runde 4)
1. **Fjern IKKE storen.** "Ingen store" ville omdøbe, ikke fjerne, ~250 linjer uundgåelig
   ekstern-proces-logik — og ofre det testbare single-ingress-søm. Nettoforenkling: negativ.
2. **De 35% ligger ikke i storen.** Storen er ~11% af koden og domineret af irreducibel I/O.
   Reelle LOC-mål er UI-kort, window-plumbing og quit-detektion — separate spor.
3. **Det spiken reelt låser op (lille, ægte):** nu hvor `@Observable` auto-observeres, kan
   `outputs`/`OverviewOutput`-kanalen (~40-60 linjer) muligvis fjernes ved at lade
   window-management observere `model` direkte i stedet for `emit(.monitorsChanged/.workspaceFocused)`.
   ⚠️ `OverlayWindowManager` er ikke et SwiftUI-view, så det kræver `withObservationTracking`-loops,
   der kan æde besparelsen. **Mål med en throwaway-spike før beslutning** — ingen forkromede løfter.
4. **Konklusion:** behold storen som det ene testbare centrum; forfølg LOC-reduktion dér hvor
   massen faktisk er (UI/window/quit), som selvstændige, verificerbare spor — ikke ved at opløse
   arkitekturens rygrad.

---

## Runde 4 — efterspil: `outputs`-kanalen er et testbart aktiv (spike 3 aflyst)

Overvejelsen "fjern `outputs`/`OverviewOutput` og lad window-management observere `model`
direkte" (den lille LOC-gevinst spiken låste op) blev **forkastet** ved nærmere eftersyn:

- `outputs`-kanalen ER det **ene testbare egress-søm** der driver `OverlayWindowManager`
  (`.monitorsChanged` → `syncWindows()`, `.workspaceFocused` → `syncWindows(force:false)`,
  `.loaded` → `showErrorFallbackIfNeeded()`). At erstatte den med `withObservationTracking`-diffing
  i en ikke-SwiftUI-klasse ville have kostet ~samme antal linjer *og* smidt den deterministiske
  testbarhed væk — præcis Björns Runde 4-advarsel.
- **Symmetrien er pointen:** storen har nu én **indgang** (inbox, `send`) og én **udgang**
  (`outputs`), begge testbare fra integrationstest uden AppKit.

**Valgt i stedet (retning A): udvid integrationstestene til hele outputs-kontrakten.**
- Nye tests i `StoreIngressIntegrationTests.swift`:
  - `.monitorsChanged`: et monitor-sæt-skift ([1] → [1,2]) emitterer præcis ét output; et
    *samme-monitor* content-skift emitterer ingen.
  - `.loaded`: initial load emitterer præcis ét `.loaded` (host'ens reveal/error-fallback-signal).
  - `.workspaceFocused` var allerede dækket af focus/monitor-event-testene.
- Ny helper `resultM(name, monitorId, [windowIds])` til at vokse/skrumpe monitor-sættet.
- **Alle 111 tests grønne** (13 → 15 integrationstests). Kompleksitet uændret (kun testkode).

**Konklusion:** window-management-sømmet testes nu deterministisk gennem outputs-kontrakten —
uden at røre AppKit og uden at ofre `outputs`-kanalen. Selve `OverlayWindowManager`s skærm-mapping/
clamping verificeres fortsat live (den AppKit-tunge del tests ikke kan dække).

---

## Runde 4 — kompleksitet bragt UNDER baseline (missionen: mindre kompleksitet)

Efter at output-kontrakt-testene var på plads var totalen 408 (> loft 407). Det stred mod
hele projektets mål (mindre kompleksitet), så den blev clawed back — ikke ved at hæve baseline,
men ved en ægte forenkling:

- **`.workspaceFocused` flyttet ind i effekt-pipelinen.** Før havde `startInbox` en særskilt
  post-apply-sti (`notifyIfFocusChanged` + `notifyWorkspaceFocused`, 6 CCN) der kiggede på hver
  input-type og emitterede fokus-outputtet ved siden af. Nu returnerer reduceren `.workspaceFocused`
  som en almindelig effekt (`[.refresh, .workspaceFocused]`) og `executeEffects` emitterer den —
  **samme uniforme sti som alle andre outputs.** De to funktioner slettet; consumer-loopet har nu
  ingen per-input special-casing.
- **`OverviewOutput.workspaceFocused` mistede sin `WorkspaceInfo`-payload** — host'en ignorerede
  den (følger bare fokus via `syncWindows(force:false)`), så den var død vægt.

**Resultat:** kompleksitet **408 → 402 — under baseline 403.** Hele segmentet (single-ingress-inbox
+ drop-diff-lag + 2 nye integrationstests + fokus-via-effekt) endte altså med **mindre kompleksitet
end det startede med**, samtidig med flere tests (111) og et renere design (én indgang, én effekt-
drevet udgang). `--check` foreslår at ratchet baseline ned til 402.
