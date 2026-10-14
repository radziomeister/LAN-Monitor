# LAN Monitor

Aplikacja w pasku menu (menu bar) dla macOS, która monitoruje łączność z bramą sieci LAN (routerem), loguje każdą przerwę w połączeniu i powiadamia o niej systemowo.

## Jak to działa

- Co 3 sekundy wysyła jeden ping ICMP do domyślnej bramy sieciowej (wykrywanej automatycznie przez `route -n get default`).
- Ikona w pasku menu to kolorowa kropka z białą obwódką: zielona = online, czerwona = brak połączenia.
- Kliknięcie ikony otwiera **dropdown zintegrowany w aplikacji** (nie osobne okno) z trzema sekcjami:
  - **Pingowanie na żywo** — aktualna prędkość internetu (↓ pobieranie / ↑ wysyłanie w Mb/s, odświeżane co 0,5 s na podstawie liczników bajtów interfejsu — tak jak w Monitorze Aktywności, bez zużywania danych na sztuczny test), mini-wykres ostatnich pingów (czerwony słupek = timeout) i lista ostatnich 5 pomiarów z czasem.
  - **Informacje o połączeniu** — brama, lokalny adres IP, nazwa usługi sieciowej (Wi-Fi/Ethernet), serwery DNS, ostatnia zarejestrowana przerwa.
  - **Test łącza** — rzeczywisty test przepustowości (nie pasywny odczyt): ~15 s pobierania + ~15 s wysyłania danych testowych do/z Cloudflare, na żywo pokazuje aktualną prędkość i pasek postępu, na koniec maksymalną i średnią prędkość pobierania oraz wysyłania. Zużywa realny transfer danych (rzędu kilkuset MB–kilku GB, zależnie od szybkości łącza).
  - Przyciski: **Otwórz plik logów**, **Wykryj bramę ponownie**, **Ustawienia…**, **Zakończ**.
- Każda zakończona przerwa (start → koniec → czas trwania) jest dopisywana do pliku CSV: `~/Library/Logs/LANMonitor/outages.csv`.
- Przy starcie i końcu przerwy wysyłane jest powiadomienie systemowe (macOS notification).
- Aplikacja nie pokazuje się w Docku (działa tylko jako ikona w pasku menu).
- Z dropdownu dostępne jest też okno **Ustawienia…** (osobne okno, w przeciwieństwie do dropdownu powyżej) z dwiema zakładkami:
  - **Sieć** — pokazuje aktualny adres IP, maskę, bramę i DNS interfejsu (Wi-Fi/Ethernet). Tryb Automatyczny (DHCP) lub Ręczny — w trybie ręcznym można wpisać własny IP/maskę/bramę/DNS i kliknąć "Zastosuj". Każda zmiana wymaga hasła administratora (standardowe okno autoryzacji macOS), tak jak w Ustawieniach systemowych.
  - **VPN** — formularz do utworzenia profilu IKEv2 (nazwa, adres serwera, Remote/Local ID, Shared Secret i/lub login+hasło). Przycisk "Zainstaluj profil VPN…" generuje plik `.mobileconfig` i otwiera systemowy instalator profili (wymaga potwierdzenia i hasła administratora). Poniżej lista już skonfigurowanych VPN-ów z przyciskami Połącz/Rozłącz (`scutil --nc`).

## Budowanie

Wymaga Xcode Command Line Tools (Swift 5.9+, macOS 13+).

```bash
cd "LAN Monitor"
./build_app.sh
```

Skrypt kompiluje projekt (`swift build -c release`), składa `LAN Monitor.app` i podpisuje go ad-hoc (żeby uruchamiał się lokalnie bez ostrzeżeń Gatekeepera).

## Uruchomienie

```bash
open "LAN Monitor.app"
```

albo zwykłe podwójne kliknięcie w Finderze.

## Automatyczne uruchamianie przy starcie systemu

1. Przenieś `LAN Monitor.app` do `/Applications` (lub zostaw w dowolnym stałym miejscu).
2. Ustawienia systemowe → Ogólne → Elementy logowania i rozszerzenia → sekcja "Otwórz przy logowaniu" → kliknij `+` i wybierz `LAN Monitor.app`.

## Struktura projektu

- `Sources/LANMonitor/PingMonitor.swift` — wykrywanie bramy i wykonywanie pingów (`/sbin/route`, `/sbin/ping`).
- `Sources/LANMonitor/OutageEvent.swift` — model pojedynczej przerwy.
- `Sources/LANMonitor/AppDelegate.swift` — logika aplikacji: pętla monitorująca, ikona w pasku menu, logowanie do CSV, powiadomienia.
- `Sources/LANMonitor/NetworkSettingsManager.swift` — odczyt/zapis konfiguracji sieciowej (`networksetup`, z autoryzacją administratora przy zapisie).
- `Sources/LANMonitor/ThroughputMonitor.swift` — pasywny pomiar bieżącej prędkości pobierania/wysyłania na podstawie liczników bajtów interfejsu (`netstat -I <iface> -b`).
- `Sources/LANMonitor/SpeedTestController.swift` — aktywny test przepustowości łącza (pobieranie/wysyłanie rzeczywistych danych testowych przez `URLSession`, endpointy `speed.cloudflare.com`).
- `Sources/LANMonitor/VPNProfile.swift` — model i generator profilu IKEv2 (`.mobileconfig`).
- `Sources/LANMonitor/VPNController.swift` — lista/połącz/rozłącz skonfigurowanych VPN-ów (`scutil --nc`).
- `Sources/LANMonitor/KeychainHelper.swift` — bezpieczne zapisywanie hasła VPN w Keychain.
- `Sources/LANMonitor/MonitorState.swift` — obserwowalny (Combine) stan na żywo współdzielony między AppDelegate a widokami SwiftUI.
- `Sources/LANMonitor/StatusDropdownView.swift` — widok SwiftUI dropdownu (status, wykres pingów, prędkość, info o połączeniu, przyciski).
- `Sources/LANMonitor/StatusPopoverController.swift` — `NSPopover` pokazujący dropdown po kliknięciu ikony w pasku menu.
- `Sources/LANMonitor/SettingsView.swift` — widoki SwiftUI okna Ustawień (zakładki Sieć/VPN).
- `Sources/LANMonitor/SettingsWindowController.swift` — okno hostujące widoki SwiftUI.
- `Sources/LANMonitor/main.swift` — punkt wejścia (uruchomienie `NSApplication`).
- `build_app.sh` — budowanie i pakowanie do `.app`.

## Dlaczego VPN działa przez instalator profilu, a nie "na klik"

Programowe tworzenie/łączenie VPN z poziomu aplikacji (`NetworkExtension`/`NEVPNManager`) wymaga płatnego konta Apple Developer i specjalnego uprawnienia (entitlement) nadawanego przez Apple — nie da się tego zrobić przy zwykłym, lokalnym podpisie ad-hoc. Dlatego aplikacja generuje standardowy plik konfiguracyjny `.mobileconfig` (dokładnie taki, jakiego używają firmy do zdalnej konfiguracji VPN pracownikom) i otwiera go w systemowym instalatorze profili — to jedyny sposób bez płatnego konta developerskiego, w pełni obsługiwany przez macOS. Po zainstalowaniu profilu, samo łączenie/rozłączanie (`scutil --nc start/stop`) już nie wymaga żadnych specjalnych uprawnień.

