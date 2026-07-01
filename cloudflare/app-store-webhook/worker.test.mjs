import assert from "node:assert/strict";
import test from "node:test";
import { handle } from "./worker.mjs";

test("forwards App Store notification to Feishu", async () => {
    const calls = [];
    const response = await handle(
        request("/webhooks/test-secret", {
            signedPayload: jws({
                notificationType: "ONE_TIME_CHARGE",
                notificationUUID: "notification-1",
                data: {
                    bundleId: "run.libo.datalayer-studio",
                    environment: "Production",
                    signedTransactionInfo: jws({
                        bundleId: "run.libo.datalayer-studio",
                        productId: "run.libo.datalayer-studio",
                        price: 19900,
                        currency: "USD",
                        storefront: "USA",
                        purchaseDate: 1719820800000,
                        transactionReason: "PURCHASE",
                        transactionId: "tx-1",
                        originalTransactionId: "otx-1"
                    })
                }
            })
        }),
        env(),
        async (url, init) => {
            calls.push({ url, init });
            return new Response(JSON.stringify({ code: 0 }), { status: 200 });
        }
    );

    assert.equal(response.status, 200);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, "https://example.feishu.test/hook");

    const message = JSON.parse(calls[0].init.body);
    assert.equal(message.msg_type, "text");
    assert.match(message.content.text, /DataLayer Studio App Store 通知/);
    assert.match(message.content.text, /类型：ONE_TIME_CHARGE/);
    assert.match(message.content.text, /金额：19\.9 USD/);
    assert.doesNotMatch(message.content.text, /signedPayload/);
});

test("rejects wrong webhook token", async () => {
    let called = false;
    const response = await handle(
        request("/webhooks/wrong-secret", { signedPayload: "x.y.z" }),
        env(),
        async () => {
            called = true;
            return new Response("{}", { status: 200 });
        }
    );

    assert.equal(response.status, 404);
    assert.equal(called, false);
});

test("ignores other bundle ids", async () => {
    let called = false;
    const response = await handle(
        request("/webhooks/test-secret", {
            signedPayload: jws({
                notificationType: "ONE_TIME_CHARGE",
                data: {
                    bundleId: "other.bundle",
                    environment: "Production"
                }
            })
        }),
        env(),
        async () => {
            called = true;
            return new Response("{}", { status: 200 });
        }
    );

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, ignored: "bundle_id" });
    assert.equal(called, false);
});

function env() {
    return {
        WEBHOOK_PATH_SECRET: "test-secret",
        FEISHU_WEBHOOK_URL: "https://example.feishu.test/hook",
        APP_BUNDLE_ID: "run.libo.datalayer-studio",
        APPLE_ENVIRONMENT: "Production"
    };
}

function request(path, body) {
    return new Request(`https://datalayer-studio.ligh-t-ouch.com${path}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body)
    });
}

function jws(payload) {
    return [
        base64URL(JSON.stringify({ alg: "ES256" })),
        base64URL(JSON.stringify(payload)),
        "signature"
    ].join(".");
}

function base64URL(value) {
    return Buffer.from(value).toString("base64url");
}
