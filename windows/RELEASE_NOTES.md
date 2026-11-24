**Cyberpad voor Windows 10/11 — eerste testversie.** Maak van een oude iPad of tablet een macropad voor je pc.
*First test version for Windows 10/11 · Primera versión de prueba para Windows 10/11.*

## Installeren

1. Download **CyberpadSetup-…exe** hieronder en start het.
2. Windows toont waarschijnlijk **"Windows heeft uw pc beschermd"** (SmartScreen), omdat de installer nog niet digitaal ondertekend is. Klik op **Meer informatie** › **Toch uitvoeren**.
3. Laat **"Tablets op mijn thuisnetwerk toelaten"** aangevinkt: dat zet de Windows Firewall open voor Cyberpad, alleen op privénetwerken.
4. Na de installatie verschijnt het koppelvenster met een adres, een QR-code en een koppelcode. Open het adres in Safari/Chrome op je tablet en voer de code in.

Tablet en pc moeten op hetzelfde wifi-netwerk zitten. Staat het netwerk in Windows op *Openbaar*, zet het dan op *Privé* (Instellingen › Netwerk en internet).

## Wat werkt al

- Koppelen, tablet-pagina, thema's, talen (English, Nederlands, Español) en de layout-editor (systeemvak › *Layout bewerken…*, of op de tablet via ⚙).
- Media- en volumeknoppen, volume- en microfoonschuif, dempen, microfoon uit.
- Toetscombinaties (`ctrl`, `shift`, `alt`, `win`; `cmd` uit een Mac-layout wordt Ctrl), tekst typen, macro's, apps uit het Startmenu, links (standaardbrowser of een gekozen browser).
- Vergrendelen, scherm uit, schermafbeelding, wakker houden, donkere modus.
- Widgets: klok, wereldklok, weer, timer, pomodoro, systeem (CPU/RAM/netwerk/batterij), *nu speelt* (Spotify, browsers, Mediaspeler…), foto's, terminal.
- Aanraakpad en draaiknoppen.

## Nog niet (volgende versie)

Home Assistant, MQTT, webhooks, plugins, de vergaderknop, agenda en contextpagina's per app. Een layout van de Mac werkt, maar knoppen met die acties melden "nog niet beschikbaar op Windows".

Je gegevens staan in `%APPDATA%\Cyberpad` en blijven staan als je Cyberpad verwijdert.
