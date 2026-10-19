# Shama — iOS

Нативный порт веб-таймера `../shamatimer.html` (SwiftUI, iOS 17+, SwiftData).
Данные — тот же сервер `life.maxdzhabali.com/shama/api`, вход паролем Life.

## Собрать

```bash
brew install xcodegen          # один раз
cd ios
xcodegen generate              # → ShamaTimer.xcodeproj (в git не хранится)
open ShamaTimer.xcodeproj
```

В Xcode: схема ShamaTimer → свой iPhone → Run. Тесты: ⌘U или из терминала на первом доступном
iPhone-симуляторе:

```bash
SIM=$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}')
xcodebuild test -project ShamaTimer.xcodeproj -scheme ShamaTimer -destination "id=$SIM"
```

(или `-destination 'platform=iOS Simulator,name=iPhone 17'` — имя должно совпадать с установленным симулятором.)

Колокола пересобираются `python3 tools/gen_bells.py` (кладёт `.caf` в `ShamaTimer/Resources/Sounds/`).

## Где собирается и как подписано (с 19.10.2026)

Собирается и грузится **на Mac mini** (`ssh maxmini`, клон `~/ai-database/max-personal-wiki/apps/shamatimer`):
там Xcode 27.1 и симулятор iOS 27.1; на MacBook Xcode нет (macOS 26.5 < 26.6).

- Аккаунт: Diamond Wisdom Group OU, Team ID `F8H3UK3UF7`, в App Store разработчик «Diamond Wisdom».
  Приложение в App Store Connect: ShamaTimer, Apple ID `6824541981`, SKU `shamatimer`.
- API-ключ: `~/.appstoreconnect/AuthKey_GTFY4P5UPP.p8` (роль Admin; копии на MacBook и mini, в репо НИКОГДА —
  репо публичное), Issuer `74224bd7-bbf9-4a2f-a400-0ed839c272bb`.
- Подпись **ручная**, устройства в аккаунте не нужны: сертификат Apple Distribution (до 19.10.2027) +
  ключ в отдельной связке `~/Library/Keychains/shama-build.keychain-db` на mini (пароль —
  `~/.appstoreconnect/signing/keychain-pass`, открывается по ssh, login keychain не нужен);
  профиль «ShamaTimer App Store» (`tools/asc.py create-profile <certId>` — пересоздать, если добавятся
  capabilities). Автоподпись Xcode не годится: без зарегистрированного iPhone она не архивирует.
- `tools/asc.py` — мини-клиент API (bundle id + capabilities, сертификат, профиль, `get <путь>`).
  Нужны PyJWT + cryptography (есть на MacBook, на mini нет — запускать с MacBook).

## Загрузить в TestFlight

```bash
ssh maxmini 'cd ~/ai-database/max-personal-wiki/apps/shamatimer/ios && git pull && bash tools/upload.sh'
```

Скрипт поднимает номер сборки (`CURRENT_PROJECT_VERSION` в `project.yml`) на 1, перегенерирует проект,
делает archive и exportArchive с `destination=upload`. Версию (`MARKETING_VERSION`) меняем руками.
Изменённый `project.yml` после загрузки — закоммитить (с mini или повторить номер на MacBook).
Обработка у Apple 5–30 мин, потом билд сам появляется у внутренней группы TestFlight «Max»
(`hasAccessToAllBuilds`).

Грабли: экспорт идёт с `PATH` без Homebrew — системный rsync зовёт «rsync» по PATH, а brew-rsync 3.x
не знает `-E` → «exportArchive Copy failed». Связку `shama-build` скрипт открывает сам — без этого
«codesign command failed».

## Что где

- `ShamaTimer/Timer` — таймер (время от дат, паузы), колокола + фоновая тишина, уведомление-страховка.
- `ShamaTimer/Sync` — вход (кука `life`), API, синк push → pull.
- `ShamaTimer/Model` — SwiftData `Session`, DTO сервера, статистика (дни — по локальному календарю).
- `ShamaTimer/Health` — запись Mindful Minutes в Apple Health (только новые сессии).
