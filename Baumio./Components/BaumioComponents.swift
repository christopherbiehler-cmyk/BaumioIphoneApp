import SwiftUI

// MARK: - Numeric input helpers

extension View {
    /// Restricts a TextField to decimal numbers (digits + one `,` or `.`) on all platforms.
    func decimalOnly(_ text: Binding<String>) -> some View {
        self
            .keyboardType(.decimalPad)
            .onChange(of: text.wrappedValue) { _, newValue in
                let filtered = newValue.filteringDecimal()
                if filtered != newValue { text.wrappedValue = filtered }
            }
    }

    /// Restricts a TextField to whole integers on all platforms.
    func integerOnly(_ text: Binding<String>) -> some View {
        self
            .keyboardType(.numberPad)
            .onChange(of: text.wrappedValue) { _, newValue in
                let filtered = newValue.filter { $0.isNumber }
                if filtered != newValue { text.wrappedValue = filtered }
            }
    }
}

private extension String {
    func filteringDecimal() -> String {
        var hasSeparator = false
        return filter { c in
            if c.isNumber { return true }
            if (c == "." || c == ",") && !hasSeparator {
                hasSeparator = true
                return true
            }
            return false
        }
    }
}

// MARK: -

struct BaumioCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BaumioTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: BaumioTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BaumioTheme.cardRadius, style: .continuous)
                    .stroke(BaumioTheme.border, lineWidth: 1)
            }
    }
}

struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage ?? "arrow.right")
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
        .background(BaumioTheme.accent)
        .clipShape(RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous))
        .accessibilityLabel(title)
    }
}

struct SecondaryButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage ?? "chevron.right")
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(BaumioTheme.primaryText)
        .background(BaumioTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BaumioTheme.controlRadius, style: .continuous)
                .stroke(BaumioTheme.border, lineWidth: 1)
        }
        .accessibilityLabel(title)
    }
}

struct FeatureRow: View {
    var title: String
    var isIncluded: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isIncluded ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isIncluded ? BaumioTheme.success : BaumioTheme.secondaryText)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(isIncluded ? BaumioTheme.primaryText : BaumioTheme.secondaryText)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(isIncluded ? "enthalten" : "nicht enthalten")")
    }
}

struct PricingCard: View {
    var plan: PricingPlan
    var action: () -> Void

    var body: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(plan.name)
                            .font(.title2.bold())
                            .foregroundStyle(BaumioTheme.primaryText)
                        Text(plan.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(BaumioTheme.secondaryText)
                    }
                    Spacer()
                    if plan.isHighlighted {
                        StatusBadge(title: "Empfohlen", color: BaumioTheme.accent)
                    }
                }

                Text(plan.price)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(plan.isHighlighted ? BaumioTheme.accent : BaumioTheme.primaryText)
                    .minimumScaleFactor(0.8)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(plan.features) { feature in
                        FeatureRow(title: feature.title, isIncluded: feature.isIncluded)
                    }
                }

                if plan.isHighlighted {
                    PrimaryButton(title: plan.buttonTitle, systemImage: "crown.fill", action: action)
                } else {
                    SecondaryButton(title: plan.buttonTitle, systemImage: plan.buttonSystemImage, action: action)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: BaumioTheme.cardRadius, style: .continuous)
                .stroke(plan.isHighlighted ? BaumioTheme.accent : BaumioTheme.border, lineWidth: plan.isHighlighted ? 2 : 1)
        }
    }
}

struct DashboardMetricCard: View {
    var title: String
    var value: String
    var subtitle: String
    var systemImage: String
    var tint: Color = BaumioTheme.accent

    var body: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(title.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(BaumioTheme.secondaryText)
                    Spacer()
                }
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(BaumioTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    var title: String
    var color: Color

    var body: some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.35), lineWidth: 1)
            }
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(BaumioTheme.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(BaumioTheme.primaryText)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(BaumioTheme.secondaryText)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct LoadingView: View {
    var title: String = "Wird geladen"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(BaumioTheme.accent)
            Text(title)
                .foregroundStyle(BaumioTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .accessibilityLabel(title)
    }
}

struct ErrorView: View {
    var title: String
    var message: String
    var retryTitle: String = "Erneut versuchen"
    var retry: () -> Void

    var body: some View {
        BaumioCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(BaumioTheme.danger)
                Text(message)
                    .foregroundStyle(BaumioTheme.secondaryText)
                SecondaryButton(title: retryTitle, systemImage: "arrow.clockwise", action: retry)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(BaumioTheme.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(BaumioTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
