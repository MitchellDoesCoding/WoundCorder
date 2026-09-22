import SwiftUI
import UIKit

// MARK: - Theme

/// Visual language shared by the refreshed WoundScope screens.
///
/// The palette intentionally uses dynamic system-trait colors instead of asset names so the
/// components remain correct in light and dark mode without requiring asset-catalog changes.
enum WSTheme {
    enum Palette {
        static let patientPrimary = Color(red: 0.031, green: 0.545, blue: 0.463)
        static let patientDeep = Color(red: 0.016, green: 0.400, blue: 0.353)
        static let patientSoft = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.055, green: 0.176, blue: 0.157, alpha: 1)
                : UIColor(red: 0.878, green: 0.957, blue: 0.933, alpha: 1)
        })

        static let professionalPrimary = Color(red: 0.278, green: 0.322, blue: 0.859)
        static let professionalDeep = Color(red: 0.192, green: 0.216, blue: 0.702)
        static let professionalSoft = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.098, green: 0.106, blue: 0.259, alpha: 1)
                : UIColor(red: 0.902, green: 0.914, blue: 0.988, alpha: 1)
        })

        static let paper = adaptive(
            light: UIColor(red: 0.980, green: 0.971, blue: 0.953, alpha: 1),
            dark: UIColor(red: 0.063, green: 0.071, blue: 0.078, alpha: 1)
        )
        static let card = adaptive(
            light: .white,
            dark: UIColor(red: 0.098, green: 0.106, blue: 0.114, alpha: 1)
        )
        static let lifted = adaptive(
            light: UIColor(red: 0.961, green: 0.961, blue: 0.957, alpha: 1),
            dark: UIColor(red: 0.125, green: 0.133, blue: 0.141, alpha: 1)
        )
        static let sunken = adaptive(
            light: UIColor(red: 0.941, green: 0.941, blue: 0.937, alpha: 1),
            dark: UIColor(red: 0.157, green: 0.169, blue: 0.180, alpha: 1)
        )

        static let ink = adaptive(
            light: UIColor(red: 0.110, green: 0.094, blue: 0.090, alpha: 1),
            dark: UIColor(red: 0.945, green: 0.953, blue: 0.961, alpha: 1)
        )
        static let secondary = adaptive(
            light: UIColor(red: 0.110, green: 0.094, blue: 0.090, alpha: 0.70),
            dark: UIColor(red: 0.945, green: 0.953, blue: 0.961, alpha: 0.70)
        )
        static let tertiary = adaptive(
            light: UIColor(red: 0.110, green: 0.094, blue: 0.090, alpha: 0.50),
            dark: UIColor(red: 0.945, green: 0.953, blue: 0.961, alpha: 0.50)
        )
        static let hairline = adaptive(
            light: UIColor(red: 0.890, green: 0.886, blue: 0.882, alpha: 1),
            dark: UIColor(red: 0.212, green: 0.224, blue: 0.235, alpha: 1)
        )

        // Descriptive aliases make the tokens easy to discover at call sites.
        static let surface = card
        static let surfaceLifted = lifted
        static let surfaceSunken = sunken
        static let inkSecondary = secondary
        static let inkTertiary = tertiary

        static let routine = Color(red: 0.086, green: 0.639, blue: 0.290)
        static let monitor = Color(red: 0.961, green: 0.620, blue: 0.043)
        static let clinical = Color(red: 0.918, green: 0.345, blue: 0.047)
        static let urgent = Color(red: 0.863, green: 0.149, blue: 0.149)

        private static func adaptive(light: UIColor, dark: UIColor) -> Color {
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            })
        }
    }

    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let card: CGFloat = 22
        static let pill: CGFloat = 999
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Stroke {
        static let hairline: CGFloat = 0.5
        static let thin: CGFloat = 1
        static let medium: CGFloat = 2
        static let thick: CGFloat = 3
    }

    enum Motion {
        static let tap = Animation.spring(response: 0.32, dampingFraction: 0.78)
        static let panel = Animation.spring(response: 0.45, dampingFraction: 0.85)
        static let quick = Animation.easeInOut(duration: 0.18)
    }
}

// MARK: - Typography

extension Font {
    static let wsDisplay = Font.system(size: 36, weight: .heavy, design: .rounded)
    static let wsTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let wsHeadline = Font.system(size: 20, weight: .bold, design: .rounded)
    static let wsBody = Font.system(size: 17, weight: .regular, design: .default)
    static let wsBodyBold = Font.system(size: 17, weight: .semibold, design: .default)
    static let wsCaption = Font.system(size: 13, weight: .regular, design: .default)
    static let wsMicro = Font.system(size: 11, weight: .medium, design: .default)
    static let wsMono = Font.system(size: 17, weight: .medium, design: .monospaced)
    static let wsMonoBig = Font.system(size: 28, weight: .semibold, design: .monospaced)
}

// MARK: - Mode-aware styling

extension WoundAppMode {
    var wsPrimary: Color {
        switch self {
        case .publicPatient: return WSTheme.Palette.patientPrimary
        case .professional: return WSTheme.Palette.professionalPrimary
        }
    }

    var wsDeep: Color {
        switch self {
        case .publicPatient: return WSTheme.Palette.patientDeep
        case .professional: return WSTheme.Palette.professionalDeep
        }
    }

    var wsSoft: Color {
        switch self {
        case .publicPatient: return WSTheme.Palette.patientSoft
        case .professional: return WSTheme.Palette.professionalSoft
        }
    }

    var wsGradient: LinearGradient {
        LinearGradient(
            colors: [wsPrimary, wsDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var wsHeroGradient: LinearGradient { wsGradient }
}

private struct WSModeEnvironmentKey: EnvironmentKey {
    static let defaultValue = WoundAppMode.publicPatient
}

extension EnvironmentValues {
    var wsAppMode: WoundAppMode {
        get { self[WSModeEnvironmentKey.self] }
        set { self[WSModeEnvironmentKey.self] = newValue }
    }
}

extension View {
    func wsAppMode(_ mode: WoundAppMode) -> some View {
        environment(\.wsAppMode, mode)
    }

    func wsCard(
        padding: CGFloat = WSTheme.Space.md,
        cornerRadius: CGFloat = WSTheme.Radius.card
    ) -> some View {
        self
            .padding(padding)
            .background(WSTheme.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(WSTheme.Palette.hairline, lineWidth: WSTheme.Stroke.hairline)
            }
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 12)
    }

    func wsPaperBackground() -> some View {
        background(WSTheme.Palette.paper.ignoresSafeArea())
    }
}

// MARK: - Cards and compact data

struct WSSectionCard<Content: View>: View {
    let title: String?
    private let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
            if let title, !title.isEmpty {
                Text(title.uppercased())
                    .font(.wsMicro)
                    .tracking(0.8)
                    .foregroundStyle(WSTheme.Palette.tertiary)
            }
            content()
        }
        .wsCard()
    }
}

struct WSStatTile: View {
    let title: String
    let value: String
    var unit: String?
    var systemImage: String?
    var tint: Color?

    @Environment(\.wsAppMode) private var mode

    init(
        title: String,
        value: String,
        unit: String? = nil,
        systemImage: String? = nil,
        tint: Color? = nil
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.systemImage = systemImage
        self.tint = tint
    }

    init(title: String, value: String, systemImage: String, color: Color) {
        self.init(title: title, value: value, systemImage: systemImage, tint: color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(resolvedTint)
                    .frame(width: 32, height: 32)
                    .background(resolvedTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.wsMonoBig)
                    .foregroundStyle(WSTheme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let unit {
                    Text(unit)
                        .font(.wsCaption)
                        .foregroundStyle(WSTheme.Palette.tertiary)
                }
            }

            Text(title.uppercased())
                .font(.wsMicro)
                .tracking(0.6)
                .foregroundStyle(WSTheme.Palette.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wsCard(padding: WSTheme.Space.sm, cornerRadius: WSTheme.Radius.lg)
    }

    private var resolvedTint: Color { tint ?? mode.wsPrimary }
}

struct WSModeChip: View {
    let mode: WoundAppMode

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mode.wsPrimary)
                .frame(width: 8, height: 8)
            Text(mode.displayName)
                .font(.wsMicro)
                .fontWeight(.semibold)
                .tracking(0.6)
                .foregroundStyle(mode.wsPrimary)
        }
        .padding(.horizontal, WSTheme.Space.sm)
        .padding(.vertical, 7)
        .background(mode.wsSoft, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.displayName) mode")
    }
}

// MARK: - Buttons

struct WSPrimaryButton: View {
    let title: String
    var icon: String?
    var isLoading: Bool
    var fullWidth: Bool
    let action: () -> Void

    @Environment(\.wsAppMode) private var mode
    @Environment(\.isEnabled) private var isEnabled

    init(
        title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        fullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: WSTheme.Space.xs) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                }
                Text(title)
                    .font(.wsBodyBold)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: 56)
            .padding(.horizontal, WSTheme.Space.lg)
            .foregroundStyle(.white)
            .background(mode.wsGradient)
            .clipShape(RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: WSTheme.Stroke.thin)
            }
            .shadow(color: mode.wsPrimary.opacity(isEnabled ? 0.30 : 0), radius: 16, x: 0, y: 8)
            .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(WSPressButtonStyle())
        .disabled(isLoading)
        .accessibilityValue(isLoading ? "Loading" : "")
    }
}

struct WSSecondaryButton: View {
    let title: String
    var icon: String?
    var fullWidth: Bool
    let action: () -> Void

    @Environment(\.wsAppMode) private var mode

    init(
        title: String,
        icon: String? = nil,
        fullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: WSTheme.Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title).font(.wsBodyBold)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: 50)
            .padding(.horizontal, WSTheme.Space.md)
            .foregroundStyle(mode.wsPrimary)
            .background(mode.wsSoft)
            .clipShape(RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous)
                    .strokeBorder(mode.wsPrimary.opacity(0.12), lineWidth: WSTheme.Stroke.hairline)
            }
        }
        .buttonStyle(WSPressButtonStyle())
    }
}

private struct WSPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(WSTheme.Motion.tap, value: configuration.isPressed)
    }
}

// MARK: - Patient identity

struct WSAvatar: View {
    let seed: String
    let initials: String
    var size: CGFloat

    init(seed: String, initials: String, size: CGFloat = 44) {
        self.seed = seed
        self.initials = initials
        self.size = size
    }

    init(initials: String, seed: String, size: CGFloat = 44) {
        self.init(seed: seed, initials: initials, size: size)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [baseColor, baseColor.opacity(0.70)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials.isEmpty ? "?" : initials.uppercased())
                .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.40), lineWidth: 1))
        .shadow(color: baseColor.opacity(0.25), radius: 6, x: 0, y: 3)
        .accessibilityHidden(true)
    }

    private var baseColor: Color {
        let colors: [Color] = [
            Color(red: 0.31, green: 0.56, blue: 0.95),
            Color(red: 0.95, green: 0.51, blue: 0.31),
            Color(red: 0.20, green: 0.72, blue: 0.55),
            Color(red: 0.77, green: 0.35, blue: 0.85),
            Color(red: 0.96, green: 0.45, blue: 0.55),
            Color(red: 0.35, green: 0.68, blue: 0.92),
            Color(red: 0.92, green: 0.62, blue: 0.18),
            Color(red: 0.42, green: 0.45, blue: 0.78)
        ]
        return colors[Int(stableHash(seed) % UInt64(colors.count))]
    }

    private func stableHash(_ value: String) -> UInt64 {
        value.unicodeScalars.reduce(UInt64(5_381)) { hash, scalar in
            ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
    }
}

// MARK: - Severity tiers

enum WSTier: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case routine
    case monitor
    case clinical
    case urgent

    var id: String { rawValue }

    init(severity: Int) {
        switch severity {
        case 15...: self = .urgent
        case 10..<15: self = .clinical
        case 6..<10: self = .monitor
        default: self = .routine
        }
    }

    var title: String {
        switch self {
        case .routine: return "Routine"
        case .monitor: return "Monitor"
        case .clinical: return "Clinical review"
        case .urgent: return "Urgent"
        }
    }

    var label: String { title }

    var color: Color {
        switch self {
        case .routine: return WSTheme.Palette.routine
        case .monitor: return WSTheme.Palette.monitor
        case .clinical: return WSTheme.Palette.clinical
        case .urgent: return WSTheme.Palette.urgent
        }
    }

    var icon: String {
        switch self {
        case .routine: return "checkmark.seal.fill"
        case .monitor: return "eye.fill"
        case .clinical: return "stethoscope"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
}

struct WSTierBadge: View {
    let tier: WSTier
    var compact: Bool

    init(tier: WSTier, compact: Bool = false) {
        self.tier = tier
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tier.icon)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
            Text(tier.title)
                .font(compact ? .wsMicro : .wsCaption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, compact ? 8 : WSTheme.Space.sm)
        .padding(.vertical, compact ? 4 : 6)
        .foregroundStyle(tier.color)
        .background(tier.color.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().strokeBorder(tier.color.opacity(0.25), lineWidth: WSTheme.Stroke.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier.title) severity")
    }
}

struct WSSeverityBadge: View {
    let score: Int
    var compact: Bool

    init(score: Int, compact: Bool = false) {
        self.score = min(max(score, 1), 20)
        self.compact = compact
    }

    var body: some View {
        let tier = WSTier(severity: score)
        HStack(spacing: 5) {
            Image(systemName: tier.icon)
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
            Text("\(score)/20")
                .font(compact ? .wsMicro : .wsCaption)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .foregroundStyle(tier.color)
        .background(tier.color.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().strokeBorder(tier.color.opacity(0.25), lineWidth: WSTheme.Stroke.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Severity \(score) out of 20, \(tier.title)")
    }
}
