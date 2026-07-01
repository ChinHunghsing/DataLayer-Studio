# DataLayer Studio App Store Webhook

Cloudflare Worker for App Store Server Notifications. It accepts:

```text
https://datalayer-studio.ligh-t-ouch.com/webhooks/<WEBHOOK_PATH_SECRET>
```

Then it decodes the notification summary and forwards a text message to the Feishu custom bot.

## Deploy

`cloudflared` is for Cloudflare Tunnel. This Worker deploy uses Wrangler or the Cloudflare dashboard; use Tunnel only if you intentionally want a local process that must stay online.

Set secrets in Cloudflare; do not commit them:

```bash
cd cloudflare/app-store-webhook
wrangler secret put WEBHOOK_PATH_SECRET
wrangler secret put FEISHU_WEBHOOK_URL
wrangler deploy
```

Use the Feishu bot webhook as `FEISHU_WEBHOOK_URL`. Use a long random value for `WEBHOOK_PATH_SECRET`, then configure the App Store Server Notification URL with the same path:

```text
https://datalayer-studio.ligh-t-ouch.com/webhooks/<WEBHOOK_PATH_SECRET>
```

`APP_BUNDLE_ID` and `APPLE_ENVIRONMENT` are plain vars in `wrangler.toml`. Remove `APPLE_ENVIRONMENT` if you want the same Worker to accept Sandbox and Production notifications.

## Verify

Run the local parser/formatter checks:

```bash
node --test cloudflare/app-store-webhook/worker.test.mjs
```

After deploy, use App Store Connect's App Store Server Notifications test button. A successful request should create one Feishu text message and return HTTP 200 from the Worker.

## Notes

- `signedPayload` is decoded for notification text, but not printed or forwarded.
- The Worker uses the secret URL path as the spam guard. If these events ever control entitlement state, add Apple JWS certificate verification or confirm the event with App Store Server API before taking action.
- Apple `price` is milliunits, so the Worker divides by `1000` before showing the amount.
- This endpoint is for App Store Server Notifications. Paid app download sales may still need App Store Connect Sales and Trends reporting if Apple does not emit a server notification for that event.

References:

- [Apple App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-v2)
- [Apple JWSTransactionDecodedPayload](https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload)
- [Feishu custom bot usage guide](https://open.feishu.cn/document/client-docs/bot-v3/add-custom-bot)
