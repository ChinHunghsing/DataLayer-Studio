import SwiftUI

struct PurchaseAuthorizationGate<Content: View>: View {
    @EnvironmentObject private var localization: LocalizationStore
    @ObservedObject private var authorization: PurchaseAuthorizationStore

    private let content: () -> Content

    init(
        authorization: PurchaseAuthorizationStore,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.authorization = authorization
        self.content = content
    }

    var body: some View {
        Group {
            switch authorization.state {
            case .allowed:
                content()
            case .checking:
                purchaseStatusView
            case let .restricted(reason, detail):
                purchaseRestrictionView(reason: reason, detail: detail)
            }
        }
        .task {
            await authorization.verifyIfNeeded()
        }
    }

    private var purchaseStatusView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(localization.string("purchase.checking.title"))
                .font(.title3.weight(.semibold))
            Text(localization.string("purchase.checking.message"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 520, minHeight: 320)
    }

    private func purchaseRestrictionView(
        reason: PurchaseRestrictionReason,
        detail: String?
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text(localization.string("purchase.restricted.title"))
                    .font(.title2.weight(.semibold))

                Text(restrictionMessage(for: reason))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .frame(maxWidth: 520)

                if let detail, !detail.isEmpty {
                    Text(localization.string("purchase.restricted.detail", detail))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 520)
                }
            }

            HStack(spacing: 10) {
                Button(localization.string("purchase.retry")) {
                    Task { await authorization.retryVerification() }
                }

                Button(localization.string("purchase.restore")) {
                    Task { await authorization.restoreAndVerify() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(minWidth: 620, minHeight: 420)
    }

    private func restrictionMessage(for reason: PurchaseRestrictionReason) -> String {
        switch reason {
        case .missingReceipt:
            return localization.string("purchase.restricted.missingReceipt")
        case .unverifiedReceipt:
            return localization.string("purchase.restricted.unverified")
        case .restoreFailed:
            return localization.string("purchase.restricted.restoreFailed")
        }
    }
}
