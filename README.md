# Kirill API и MongoDB

## Что запускается

`docker-compose.yml` поднимает три отдельных контейнера:

- `kirill-api` - backend приложения на порту `5183`.
- `account-billing-api` - общий backend аккаунтов, баланса, подписок и оплат на внутреннем порту `5184`, наружу по умолчанию `5185`.
- `kirill-mongo` - MongoDB на порту `27017`.

MongoDB живёт отдельно от backend, поэтому к ней могут подключаться другие сервисы. `kirill-api` проксирует старые `/api/v1/auth/*` и `/api/v1/billing/*` маршруты в `account-billing-api`, если задан `ACCOUNT_BILLING_SERVICE_URL`.

## Быстрый старт

```bash
cp .env.example .env
docker compose up -d --build
```

Проверка backend:

```bash
curl http://localhost:5183/health
curl http://localhost:5185/health
```

Проверка MongoDB с хоста:

```bash
mongosh "mongodb://kirill:kirill_password@localhost:27017/kirill_api?authSource=admin"
```

## Подключение других сервисов

Если другой сервис запускается в этом же `docker-compose.yml` или подключён к сети `kirill_backend_net`, ему нужно использовать имя контейнера `mongo`:

```env
MONGO_URI=mongodb://kirill:kirill_password@mongo:27017/kirill_api?authSource=admin
```

Если другой сервис запускается на этом же сервере, но не в Docker-сети:

```env
MONGO_URI=mongodb://kirill:kirill_password@localhost:27017/kirill_api?authSource=admin
```

Если другой сервис запускается на другом сервере:

```env
MONGO_URI=mongodb://kirill:kirill_password@SERVER_IP:27017/kirill_api?authSource=admin
```

`SERVER_IP` нужно заменить на IP сервера, где запущен `kirill-mongo`.

## Подключение внешнего docker-compose к этой MongoDB

В другом проекте можно подключиться к уже созданной сети:

```yaml
services:
  another-service:
    image: your-image
    environment:
      MONGO_URI: mongodb://kirill:kirill_password@mongo:27017/kirill_api?authSource=admin
    networks:
      - kirill_backend_net

networks:
  kirill_backend_net:
    external: true
```

После этого контейнер `another-service` сможет обращаться к MongoDB по имени `mongo`.

## Важные переменные

- `MONGO_INITDB_ROOT_USERNAME` - логин MongoDB.
- `MONGO_INITDB_ROOT_PASSWORD` - пароль MongoDB.
- `MONGO_HOST_PORT` - порт MongoDB наружу на сервере. По умолчанию `27017`.
- `MONGO_URI` - строка подключения backend к MongoDB.
- `PORT` - порт backend.
- `ACCOUNT_BILLING_PORT` - внутренний порт отдельного account/billing backend. По умолчанию `5184`.
- `ACCOUNT_BILLING_HOST_PORT` - внешний порт account/billing backend. По умолчанию `5185`.
- `ACCOUNT_BILLING_SERVICE_URL` - внутренний URL account/billing backend для прокси из `kirill-api`.
- `APP_ID` - id текущего приложения. По умолчанию `psychology`.
- `DEEPSEEK_API_KEY` - ключ для AI-запросов.
- `TBANK_API_BASE_URL` - адрес API интернет-эквайринга Т-Банка.
- `TBANK_TERMINAL_KEY` - терминал магазина Т-Банка.
- `TBANK_PASSWORD` - пароль терминала Т-Банка. Хранится только на backend.
- `TBANK_PAYMENT_SCHEME` - схема deeplink-а, по которой Т-Банк возвращает пользователя в мобильное приложение.
- `TBANK_PAYMENT_RETURN_BASE_URL` - куда Т-Банк отправит пользователя после оплаты. Для продакшена лучше `https://niami.ru/payment`, потому что сайт сможет открыть приложение через deeplink и показать понятный fallback.

## Платежи Т-Банка

Flutter не ходит в API Т-Банка напрямую. Приложение просит backend создать платеж, backend подписывает запрос паролем терминала и возвращает `PaymentURL`.

Подписки и пакеты запросов теперь имеют два поля:

- `appId` / `app_id` - приложение, к которому относится продукт. Для глобального продукта используется `global`.
- `scope` - `app` для продукта конкретного приложения или `global` для всей экосистемы.

Клиент может передавать `appId` и `scope` в JSON body, query-параметрах или заголовках `X-App-Id` / `X-Subscription-Scope`. Если `scope=global`, подписка или пакет действует во всех приложениях. Если `scope=app`, действует только для указанного `appId`.

Схема пополнения:

1. Flutter вызывает `POST /api/v1/billing/tbank/init` с `userId` и `amount`.
2. Backend вызывает `/Init` в Т-Банке и сохраняет платеж в MongoDB.
3. Flutter открывает `PaymentURL` в системной платежной форме.
4. После возврата в приложение Flutter вызывает `POST /api/v1/billing/tbank/confirm`.
5. Backend вызывает `/GetState`, сверяет сумму и начисляет баланс только при статусе `CONFIRMED`.

Токен Т-Банка собирается на backend: берутся только поля верхнего уровня запроса, добавляется `Password`, ключи сортируются по алфавиту, значения склеиваются в одну строку и хешируются через SHA-256.

### Способы оплаты в форме

Код открывает универсальную платежную форму Т-Банка через `PaymentURL`. Поэтому карты, СБП, T-Pay, Mir Pay и Долями включаются не отдельными Flutter-кнопками, а в личном кабинете интернет-эквайринга:

1. Открыть магазин.
2. Перейти на вкладку `Прием оплаты`.
3. В блоке готовой платежной формы Т-Банка включить нужные способы оплаты.
4. Проверить, что терминал настроен как `Универсальное` подключение.

Backend передает в `DATA` мобильный контекст (`Device`, `DeviceOs`, `DeviceWebView`, `DeviceBrowser`, `TinkoffPayWeb`), чтобы форма корректно показывала мобильные способы оплаты.

### Возврат в приложение после оплаты

`SuccessURL` и `FailURL` формируются от `TBANK_PAYMENT_RETURN_BASE_URL`.

Для локального теста можно оставить прямой deeplink:

```text
kirillapppay://payment/success/<orderId>
kirillapppay://payment/fail/<orderId>
```

Для продакшена лучше поставить:

```env
TBANK_PAYMENT_RETURN_BASE_URL=https://niami.ru/payment
```

Тогда банк откроет:

```text
https://niami.ru/payment/success/<orderId>
https://niami.ru/payment/fail/<orderId>
```

А сайт уже попытается открыть приложение через `kirillapppay://payment/...`.

Android и iOS должны иметь зарегистрированную схему `kirillapppay`. Flutter ловит эту ссылку, открывает экран баланса и просит backend проверить платеж. Сам deeplink не считается доказательством оплаты.

## Если порт 27017 занят

В `.env` поменять:

```env
MONGO_HOST_PORT=27018
```

Тогда с хоста подключение будет таким:

```env
MONGO_URI=mongodb://kirill:kirill_password@localhost:27018/kirill_api?authSource=admin
```

Внутри Docker-сети порт не меняется:

```env
MONGO_URI=mongodb://kirill:kirill_password@mongo:27017/kirill_api?authSource=admin
```

## Безопасность

Не коммитьте настоящий `.env`. В репозитории должен лежать только `.env.example`.

Если MongoDB открыта наружу через `MONGO_HOST_PORT`, доступ к порту `27017` или `27018` лучше ограничить firewall-ом только для нужных серверов.
