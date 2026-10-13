# Demo-scenarier

Fire korte klip, ét budskab hvert. Optages af dig med rigtige taster, KeyCastr og Kap; eksport
med Gifski i 1312 px bredde, 12–15 fps (eller MP4).

## Fælles skrivebord

Skærm: MacBook, 1312×848 punkter. Dine egne vinduer (Arc, Claude, VS Code) minimeret, så
kortet kun viser workspace 3–8. Terminalerne er Ghostty-vinduer med hver sin TUI og titel:

| Workspace | Vinduer |
|---|---|
| 3 | Safari *Aurora* + Ghostty *Aquarium* (asciiquarium) |
| 4 | Safari *Common octopus* + TextEdit "Recipe", som accordion |
| 5 | Ghostty *Bonsai* (cbonsai) + *Pipes* (pipes.sh) + *Clock* (tty-clock) |
| 6 | Safari *Mandelbrot set* + Ghostty *Matrix* (cmatrix) + Ordbog; Lommeregneren flyder |
| 7 | Ghostty *Banner* (figlet + lolcat) + Preview *Sonoma*; Finder med baggrundsbilleder flyder |
| 8 | Scenen til klip 5: Ghostty *Alpha*, *Bravo*, *Charlie*, *Delta*, *Echo*, hver med sit store bogstav og sin farve |

Ikke Skak (titlen indeholder dit fulde navn) og ikke btop (viser værtsnavn og dine processer).

## 1. Find det (~7 s)

*Where did that window go? Summon, type two letters, Enter.*

1. Start på workspace 3, hold 0,7 s.
2. `⌃⌥⌘ space`: kortet. Vent 1 s, til billederne står.
3. Skriv `oc`: gitteret samler sig om Octopus-vinduet, titlen vises. Hold 1 s.
4. `⏎`: workspace 4, Octopus i fokus. Hold 1,2 s.

## 2. Striben (~7 s)

*Which of my terminals? One key per app; only its windows, with pictures.*

1. Start på workspace 4 (*Octopus*), med *Aquarium* som den terminal, du brugte før.
2. `⌃⌥⌘ A`, `W`: seks terminaler på fire workspaces, ringen på *Aquarium*. Hold 1 s.
3. `→` `→`: markeringen til *Pipes*, hold 0,8 s.
4. `⏎`: workspace 5. Hold 1,2 s.

## 3. Flyt det (~9 s, looper)

*This belongs on workspace 3. Drag the picture, or ⇧⌘ + the workspace key. Drag a whole card to merge.*

1. Start på workspace 3. `⌃⌥⌘ space`.
2. Træk Ordbogens billede fra kort 6 til kort 3; kort 3 lægger sig om til tre. Hold 1 s.
3. Peg på den (ringen), `⇧⌘6`: den går tilbage. Hold 0,6 s.
4. `Esc`. Første og sidste billede er ens, så klippet looper.

## 4. Glemt en tast? (~5 s, looper)

*Forgot a key? The mode's keys, the moment you need them.*

1. Hint-positionen sat (fx nederst i midten), forsinkelse 400 ms.
2. `⌃⌥⌘ W`: window-moden, hinten kommer efter 400 ms. Hold 2 s.
3. `Esc`: hinten forsvinder.

Window-moden, ikke apps-moden: apps-moden viser navnene på dine arbejds-apps.
Optages sidst, da featuren ikke er committet.

## 5. Live (~12 s)

*The map is AeroSpace, live: change a layout while it is up, and the card follows.*

Layout-modens taster: `D` dwindle (`~/.config/aerospace/dwindle.sh`), `S` stacked, `G` tiled,
`F` floating, `T` tilbage til tiling. Hinten må gerne stå på her; den viser modens taster.

1. Start på workspace 8. `⌃⌥⌘ space`: kortet, ringen på kort 8. Hold 1 s.
2. `⌃⌥⌘ L`, `D`: kort 8 bliver en spiral. Hold 1,5 s.
3. `⌃⌥⌘ L`, `S`: stacked. Hold 1,5 s.
4. `⌃⌥⌘ L`, `G`: tiled igen. Hold 1,5 s.
5. `⌃⌥⌘ L`, `F`: vinduet under ringen flyder. Hold 1,5 s; `⌃⌥⌘ L`, `T` sætter det tilbage,
   så klippet kan loope.

## Faldgruber

- **Opvarmning**: kald kortet én gang før hver optagelse; første gang skifter billederne ud
  kort for kort.
- **Hinten i klip 1–3**: slå den fra i menuen (klik den valgte plads igen), ellers dukker den
  op, hvis du tøver i apps-moden.
- **KeyCastr** nederst til venstre over baggrunden, væk fra linjen under kortene, 1,5 s
  synlig. Tjek at hverken KeyCastr eller Kap bliver tilet ind som vindue på et kort.
- **Musen** parkeret i et hjørne af baggrunden (hover flytter ringen og viser luk-knapper).
  I klip 3: Kaps "vis markør" og klik-markering til, da KeyCastr ikke viser træk.
- **Private data**: kald kortet én gang tørt og læs hvert kort og filterlisten.
- Klip 1 og 2 går fra A til B og kan ikke loope; giv 0,5 s før og 1,2 s efter.

## Fravalgt

- **Luk de løse** (`⌘W`/`⌘Q`): gevinsten er et billede, der forsvinder, og det ødelægger
  skrivebordet mellem optagelser. En sætning i README'en bærer den.
- **Flet workspaces**: ligner klip 3; nævnes i dets billedtekst.
- **Gå med pilene**: AeroSpaces fokus, der følger med, ses ikke bag overlayet.

## Efter optagelserne

- Fjern den midlertidige `y = Safari` i apps-moden i `~/.config/aerospace/aerospace.toml`
  (klip 2 bruger nu Ghostty-tasten `w`).
- `scripts/demo-uninstall.sh` fjerner KeyCastr, Kap, Gifski og terminal-værktøjerne.
