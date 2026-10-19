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

## Один раз перед первой сборкой на телефон / загрузкой

1. Xcode → Settings → Accounts → добавить Apple ID разработчика.
2. Team ID (10 символов) вписать в `project.yml` → `DEVELOPMENT_TEAM`
   (или передавать `DEVELOPMENT_TEAM=…` в `tools/upload.sh`), затем `xcodegen generate`.
3. Зарегистрировать bundle id `com.maxdzhabali.shamatimer` — первый Run на свой iPhone с автоподписью
   (Xcode сам создаст App ID с HealthKit и Time Sensitive Notifications) или вручную в
   developer.apple.com → Certificates, IDs & Profiles. Это ДО шага 4.
4. В App Store Connect создать приложение, выбрав этот bundle id.
5. API-ключ App Store Connect (Users and Access → Integrations → App Store Connect API) с ролью **Admin**
   (с App Manager облачная подпись при `-allowProvisioningUpdates` может упасть):
   файл положить в `~/.appstoreconnect/AuthKey_<KEY_ID>.p8`, запомнить Key ID и Issuer ID.
   Альтернатива без ключа: первая загрузка руками — Xcode → Product → Archive → Organizer → Distribute App.

## Загрузить в TestFlight

```bash
cd ios
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-... tools/upload.sh
```

Скрипт поднимает номер сборки (`CURRENT_PROJECT_VERSION` в `project.yml`) на 1, перегенерирует проект,
делает archive и exportArchive с `destination=upload`. Версию (`MARKETING_VERSION`) меняем руками.
Изменённый `project.yml` после загрузки — закоммитить.

## Что где

- `ShamaTimer/Timer` — таймер (время от дат, паузы), колокола + фоновая тишина, уведомление-страховка.
- `ShamaTimer/Sync` — вход (кука `life`), API, синк push → pull.
- `ShamaTimer/Model` — SwiftData `Session`, DTO сервера, статистика (дни — по локальному календарю).
- `ShamaTimer/Health` — запись Mindful Minutes в Apple Health (только новые сессии).
