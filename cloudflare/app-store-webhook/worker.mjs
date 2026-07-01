const MAX_BODY_BYTES = 64 * 1024;

export default {
    async fetch(request, env) {
        return handle(request, env, fetch);
    }
};

export async function handle(request, env, fetchImpl = fetch) {
    if (request.method !== "POST") {
        return json({ ok: false, error: "method_not_allowed" }, 405, { Allow: "POST" });
    }

    const url = new URL(request.url);
    const token = webhookToken(url.pathname);
    if (!env.WEBHOOK_PATH_SECRET || !token || !constantTimeEqual(token, env.WEBHOOK_PATH_SECRET)) {
        return json({ ok: false, error: "not_found" }, 404);
    }

    if (!env.FEISHU_WEBHOOK_URL) {
        return json({ ok: false, error: "missing_feishu_webhook" }, 500);
    }

    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).length > MAX_BODY_BYTES) {
        return json({ ok: false, error: "body_too_large" }, 413);
    }

    const body = parseJSON(rawBody);
    if (!body || typeof body.signedPayload !== "string") {
        return json({ ok: false, error: "missing_signed_payload" }, 400);
    }

    let notification;
    try {
        // ponytail: notification-only path; verify Apple JWS before using this for entitlement state.
        notification = decodeJWSPayload(body.signedPayload);
    } catch {
        return json({ ok: false, error: "invalid_signed_payload" }, 400);
    }

    const transaction = decodeOptionalJWS(notification.data?.signedTransactionInfo);
    const renewal = decodeOptionalJWS(notification.data?.signedRenewalInfo);

    if (env.APP_BUNDLE_ID && !matchesBundle(env.APP_BUNDLE_ID, notification, transaction)) {
        return json({ ok: true, ignored: "bundle_id" });
    }

    if (env.APPLE_ENVIRONMENT && notification.data?.environment !== env.APPLE_ENVIRONMENT) {
        return json({ ok: true, ignored: "environment" });
    }

    const message = {
        msg_type: "text",
        content: {
            text: renderMessage(notification, transaction, renewal)
        }
    };

    const feishuResponse = await fetchImpl(env.FEISHU_WEBHOOK_URL, {
        method: "POST",
        headers: { "content-type": "application/json; charset=utf-8" },
        body: JSON.stringify(message)
    });

    if (!feishuResponse.ok) {
        console.error("Feishu webhook failed", feishuResponse.status);
        return json({ ok: false, error: "feishu_webhook_failed" }, 502);
    }

    const responseText = await feishuResponse.text();
    const feishuBody = parseJSON(responseText);
    const feishuCode = feishuBody?.code ?? feishuBody?.StatusCode;
    if (feishuCode !== undefined && feishuCode !== 0) {
        console.error("Feishu webhook returned non-zero code", feishuCode);
        return json({ ok: false, error: "feishu_webhook_rejected" }, 502);
    }

    return json({ ok: true, notificationUUID: notification.notificationUUID ?? null });
}

function webhookToken(pathname) {
    const match = pathname.match(/^\/webhooks\/([^/]+)$/);
    return match?.[1] ?? null;
}

function constantTimeEqual(a, b) {
    const left = new TextEncoder().encode(a);
    const right = new TextEncoder().encode(b);
    const length = Math.max(left.length, right.length);
    let diff = left.length ^ right.length;

    for (let index = 0; index < length; index += 1) {
        diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
    }

    return diff === 0;
}

function parseJSON(text) {
    try {
        return JSON.parse(text);
    } catch {
        return null;
    }
}

function decodeOptionalJWS(jws) {
    if (typeof jws !== "string") {
        return null;
    }

    try {
        return decodeJWSPayload(jws);
    } catch {
        return null;
    }
}

function decodeJWSPayload(jws) {
    const parts = jws.split(".");
    if (parts.length !== 3) {
        throw new Error("Invalid JWS");
    }

    const bytes = base64URLToBytes(parts[1]);
    return JSON.parse(new TextDecoder().decode(bytes));
}

function base64URLToBytes(value) {
    const base64 = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);

    for (let index = 0; index < binary.length; index += 1) {
        bytes[index] = binary.charCodeAt(index);
    }

    return bytes;
}

function matchesBundle(expectedBundleId, notification, transaction) {
    return notification.data?.bundleId === expectedBundleId || transaction?.bundleId === expectedBundleId;
}

function renderMessage(notification, transaction, renewal) {
    const data = notification.data ?? {};
    const lines = [
        "DataLayer Studio App Store 通知",
        field("类型", joinType(notification.notificationType, notification.subtype)),
        field("环境", data.environment),
        field("Bundle ID", data.bundleId ?? transaction?.bundleId),
        field("商品", transaction?.productId),
        field("金额", formatPrice(transaction?.price, transaction?.currency)),
        field("Storefront", transaction?.storefront),
        field("购买时间", formatAppleDate(transaction?.purchaseDate)),
        field("到期时间", formatAppleDate(transaction?.expiresDate ?? renewal?.gracePeriodExpiresDate)),
        field("交易原因", transaction?.transactionReason),
        field("交易 ID", transaction?.transactionId),
        field("原始交易 ID", transaction?.originalTransactionId),
        field("通知 ID", notification.notificationUUID)
    ];

    return lines.filter(Boolean).join("\n");
}

function joinType(type, subtype) {
    if (!type) {
        return null;
    }

    return subtype ? `${type} / ${subtype}` : type;
}

function field(label, value) {
    if (value === null || value === undefined || value === "") {
        return null;
    }

    return `${label}：${value}`;
}

function formatPrice(price, currency) {
    if (price === null || price === undefined || !currency) {
        return null;
    }

    const amount = Number(price);
    if (!Number.isFinite(amount)) {
        return null;
    }

    const value = trimTrailingZeros((amount / 1000).toFixed(3));
    const currencyName = currencyDisplayName(currency);
    return currencyName ? `${value} ${currency}（${currencyName}）` : `${value} ${currency}`;
}

function trimTrailingZeros(value) {
    return value.replace(/\.?0+$/, "");
}

function currencyDisplayName(currency) {
    try {
        return new Intl.DisplayNames(["zh-CN"], { type: "currency" }).of(currency);
    } catch {
        return null;
    }
}

function formatAppleDate(milliseconds) {
    if (milliseconds === null || milliseconds === undefined) {
        return null;
    }

    const date = new Date(Number(milliseconds));
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function json(body, status = 200, headers = {}) {
    return new Response(JSON.stringify(body), {
        status,
        headers: {
            "content-type": "application/json; charset=utf-8",
            ...headers
        }
    });
}
