#if os(iOS)
import StoreKit
import SwiftUI

struct TouchSubscriptionStatusBlock: View {
    @ObservedObject var subscriptionStore: MobileSubscriptionStore
    let localizer: TouchLocalizer
    let showPaywall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(localizer.format(subscriptionStore.stateMessage))
            } icon: {
                Image(systemName: subscriptionStore.hasActiveExportEntitlement ? "checkmark.seal.fill" : "lock.fill")
            }
            .font(.callout)
            .foregroundStyle(subscriptionStore.hasActiveExportEntitlement ? .green : .secondary)

            if !subscriptionStore.hasActiveExportEntitlement {
                Button {
                    showPaywall()
                } label: {
                    Label(localizer.string("paywall.subscribe.cta"), systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct TouchSubscriptionPaywallView: View {
    @ObservedObject var subscriptionStore: MobileSubscriptionStore
    let localizer: TouchLocalizer

    @Environment(\.dismiss) private var dismiss
    @State private var isRestoring = false

    var body: some View {
        VStack(spacing: 0) {
            SubscriptionStoreView(productIDs: MobileSubscriptionStore.productIDs) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localizer.string("paywall.title"))
                        .font(.title2.weight(.semibold))
                    Text(localizer.string("paywall.feature.export"))
                        .font(.body)
                    Text(localizer.string("paywall.trial.terms"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .onInAppPurchaseCompletion { _, _ in
                await subscriptionStore.refreshEntitlements()
                if subscriptionStore.hasActiveExportEntitlement {
                    dismiss()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label(localizer.format(subscriptionStore.stateMessage), systemImage: "checkmark.seal")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let message = subscriptionStore.lastMessage {
                    Text(localizer.format(message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        restore()
                    } label: {
                        if isRestoring {
                            ProgressView()
                        } else {
                            Text(localizer.string("paywall.restore"))
                        }
                    }
                    .disabled(isRestoring)

                    Button(localizer.string("paywall.manage")) {
                        Task { await subscriptionStore.showManageSubscriptions() }
                    }

                    Button(localizer.string("paywall.redeem")) {
                        Task { await subscriptionStore.redeemOfferCode() }
                    }
                }
                .buttonStyle(.bordered)

                HStack {
                    Link(localizer.string("paywall.eula"), destination: MobileSubscriptionStore.standardEULAURL)
                    Link(localizer.string("paywall.privacy"), destination: MobileSubscriptionStore.privacyURL)
                }
                .font(.caption)
            }
            .padding()
        }
        .navigationTitle(localizer.string("paywall.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizer.string("common.cancel")) {
                    dismiss()
                }
            }
        }
    }

    private func restore() {
        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            await subscriptionStore.restore()
            if subscriptionStore.hasActiveExportEntitlement {
                dismiss()
            }
        }
    }
}
#endif
