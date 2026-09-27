import SwiftUI
import UIKit
import SharedModels

/// The device name for copy such as "Transcribed privately on this iPhone": "iPad" on iPad, "iPhone" otherwise.
enum DeviceName {
    @MainActor static var current: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}

/// Graphite design system: black, white and warm greys with ink as the only accent.
/// Every color adapts to light and dark mode. Flat surfaces, hairline borders, no gradients.
///
/// Use the semantic tokens (background, card, textPrimary, accent...) in new code.
/// The older names (purple, magenta, skyBlue...) remain as aliases so existing views
/// pick up the graphite palette; replace them with semantic tokens as screens are reworked.
public struct AppTheme {
    // MARK: - Adaptive helper

    /// A color that switches between light and dark mode values.
    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    // MARK: - Semantic tokens

    /// Screen background (warm off-white / near black)
    public static let background = adaptive(light: "#F7F7F5", dark: "#0B0B0B")
    /// Card and grouped-row surface
    public static let card = adaptive(light: "#FFFFFF", dark: "#161616")
    /// Subtle fill: segmented controls, chips, progress tracks
    public static let fill = adaptive(light: "#EFEFEC", dark: "#202020")
    /// Hairline borders and dividers
    public static let hairline = adaptive(light: "#E4E4E0", dark: "#2A2A2A")
    /// Primary text and icons
    public static let textPrimary = adaptive(light: "#111111", dark: "#F3F3F1")
    /// Secondary text, captions, inactive icons (meets 4.5:1 on card and background)
    public static let textSecondary = adaptive(light: "#55554F", dark: "#B4B4AF")
    /// The single accent: ink. Primary buttons, selection, record button.
    public static let accent = adaptive(light: "#111111", dark: "#F3F3F1")
    /// Text and icons placed on an accent fill
    public static let onAccent = adaptive(light: "#FFFFFF", dark: "#0B0B0B")
    /// Recording indicator only
    public static let recording = adaptive(light: "#D92D20", dark: "#F04438")
    /// Destructive actions only (delete, remove)
    public static let destructive = adaptive(light: "#B42318", dark: "#F97066")

    // MARK: - Typography

    /// Large screen titles in New York (Apple's system serif)
    /// Serif display font at a fixed size. In views prefer `.scaledFont(size:design: .serif)`,
    /// which follows Dynamic Type.
    public static func titleFont(size: CGFloat = 34) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    // MARK: - Shape

    public static let cardRadius: CGFloat = 20
    public static let buttonRadius: CGFloat = 12

    // MARK: - Legacy names (mapped to graphite)

    /// Legacy: was dark purple. Now ink.
    public static let darkPurple = accent
    /// Legacy: was purple accent. Now ink.
    public static let purple = accent
    /// Legacy: was light purple for borders/backgrounds. Now hairline.
    public static let lightPurple = hairline
    /// Legacy: was sky blue info accent. Now secondary text.
    public static let skyBlue = textSecondary
    /// Legacy: was pale blue background. Now fill.
    public static let paleBlue = fill
    /// Legacy: was magenta (energetic accent). Now ink.
    public static let magenta = accent
    /// Legacy: was emerald success. Now ink (status is shown with icons and words).
    public static let emerald = accent

    // MARK: - Legacy gradients (now flat)

    private static func flat(_ color: Color) -> RadialGradient {
        RadialGradient(colors: [color, color], center: .center, startRadius: 0, endRadius: 1)
    }

    public static let idleGradient = flat(accent)
    public static let recordingGradient = flat(accent)
    public static let processingGradient = flat(accent)
    public static let successGradient = flat(accent)
    public static let purpleBlueGradient = flat(accent)
    public static let magentaPinkGradient = flat(textSecondary)

    /// Word cloud: top ranks in ink, lower ranks in secondary grey (single-color scale)
    public static func wordCloudGradient(forRank rank: Int) -> RadialGradient {
        flat(rank < 6 ? textPrimary : textSecondary)
    }

    // MARK: - Card overlay (removed; kept for source compatibility)

    public static func cardGradient(for colorScheme: ColorScheme) -> some ShapeStyle {
        Color.clear
    }

    // MARK: - Icon backgrounds

    /// Subtle fill behind icon-only buttons
    public static let purpleIconBackground = fill
    
    // MARK: - WCAG Accessibility Helpers
    
    /// Calculate relative luminance for a color
    /// Formula: https://www.w3.org/TR/WCAG20/#relativeluminancedef
    private static func relativeLuminance(of color: Color) -> Double {
        // Convert SwiftUI Color to RGB components
        // Note: This is a simplified version. For production, use UIColor/NSColor conversion
        let components = color.cgColor?.components ?? [0, 0, 0]
        let r = components[0]
        let g = components.count > 1 ? components[1] : components[0]
        let b = components.count > 2 ? components[2] : components[0]
        
        // Apply gamma correction
        func adjust(_ component: CGFloat) -> Double {
            let c = Double(component)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        
        let rAdjusted = adjust(r)
        let gAdjusted = adjust(g)
        let bAdjusted = adjust(b)
        
        return 0.2126 * rAdjusted + 0.7152 * gAdjusted + 0.0722 * bAdjusted
    }
    
    /// Calculate contrast ratio between two colors
    /// Returns ratio (e.g., 7.2 means 7.2:1)
    /// WCAG AA: 4.5:1 for normal text, 3:1 for large text
    /// WCAG AAA: 7:1 for normal text, 4.5:1 for large text
    public static func contrastRatio(foreground: Color, background: Color) -> Double {
        let l1 = relativeLuminance(of: foreground)
        let l2 = relativeLuminance(of: background)
        
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    /// Check if color combination meets WCAG AA standard
    public static func meetsWCAGAA(foreground: Color, background: Color, isLargeText: Bool = false) -> Bool {
        let ratio = contrastRatio(foreground: foreground, background: background)
        return ratio >= (isLargeText ? 3.0 : 4.5)
    }
}

// MARK: - Year Wrap Theme

/// Year Wrap colors, graphite: sections differ by icon and title, not color
public struct YearWrapTheme {
    // Graphite: sections are told apart by icons and titles, not by color.
    public static let vibrantOrange = AppTheme.accent
    public static let hotPink = AppTheme.accent
    public static let electricPurple = AppTheme.accent
    public static let spotifyGreen = AppTheme.accent

    public static let winsColor = AppTheme.textPrimary
    public static let lossesColor = AppTheme.textPrimary
    public static let challengesColor = AppTheme.textPrimary
    public static let finishedProjectsColor = AppTheme.textPrimary
    public static let unfinishedProjectsColor = AppTheme.textPrimary
    public static let peopleColor = AppTheme.textPrimary
    public static let placesColor = AppTheme.textPrimary
    public static let topicsColor = AppTheme.textPrimary
    public static let actionsColor = AppTheme.textPrimary
    public static let opportunitiesColor = AppTheme.textPrimary

    /// Monthly activity charts: ink, alternating with secondary grey
    public static let chartColors: [Color] = [AppTheme.textPrimary, AppTheme.textSecondary]
    
    // MARK: - UIKit Conversion Helper
    
    /// Convert SwiftUI Color to UIColor for PDF rendering
    public static func uiColor(from color: Color) -> UIColor {
        return UIColor(color)
    }
}


// MARK: - Screen Styling

extension View {
    /// Warm graphite screen background for lists and scroll views.
    func themedScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
    }
}

// MARK: - Readable Width (iPad)

extension AppTheme {
    /// Widest a column of text or settings rows gets on iPad; longer lines are hard to read
    static let readableWidth: CGFloat = 720
    /// Screens this wide or wider lay content out in two columns (recording, Overview, Year Wrap)
    static let twoColumnWidth: CGFloat = 900
}

extension View {
    /// Caps content inside a ScrollView at a readable width, centered. No effect at iPhone widths.
    func readableColumn(_ maxWidth: CGFloat = AppTheme.readableWidth) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    /// For a List, Form or ScrollView: widens the side margins so rows stay at a readable width
    /// on iPad, while the whole screen still scrolls. No effect at iPhone widths.
    func readableMargins(_ maxWidth: CGFloat = AppTheme.readableWidth) -> some View {
        modifier(ReadableMargins(maxWidth: maxWidth))
    }

    /// Reports the view's width, for layouts that switch to two columns when there's room
    func onWidthChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { action($0) }
    }
}

/// Large serif screen title placed in the content. On iPad, screens whose content sits in a
/// centered column use it instead of the navigation bar title, which would sit far to the left.
struct ColumnTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .scaledFont(size: 34, design: .serif)
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Large title on iPhone. On iPad, where the content sits in a centered column, the title
    /// goes in the middle of the bar so it lines up with the content instead of the screen edge.
    func columnScreenTitleDisplayMode() -> some View {
        modifier(ColumnScreenTitleDisplayMode())
    }
}

private struct ColumnScreenTitleDisplayMode: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .large)
    }
}

private struct ReadableMargins: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        // Safe area padding, not content margins: setting a List's content margins (even to 0)
        // replaces its inset-grouped inset on iPhone, and content margins also reach nested scroll views
        content
            .safeAreaPadding(.horizontal, max((width - maxWidth) / 2, 0))
            .onWidthChange { width = $0 }
    }
}

// MARK: - Navigation Bar Appearance

enum AppAppearance {
    /// Serif (New York) navigation titles to match the graphite design.
    @MainActor
    static func configure() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: serifFont(size: 34, weight: .regular, textStyle: .largeTitle),
            .foregroundColor: UIColor(AppTheme.textPrimary)
        ]
        bar.titleTextAttributes = [
            .font: serifFont(size: 17, weight: .semibold, textStyle: .headline),
            .foregroundColor: UIColor(AppTheme.textPrimary)
        ]
    }

    private static func serifFont(size: CGFloat, weight: UIFont.Weight, textStyle: UIFont.TextStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        let font = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }
}

// MARK: - Graphite Components

extension View {
    /// White card with a hairline border, matching the mockups (radius 20, padding 20).
    func graphiteCard(padding: CGFloat = 20, radius: CGFloat = AppTheme.cardRadius) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(AppTheme.card)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
    }

    /// Hides the disclosure chevron on NavigationLink rows where the platform supports it.
    @ViewBuilder
    func hidesNavigationChevron() -> some View {
        if #available(iOS 26.0, *) {
            self.navigationLinkIndicatorVisibility(.hidden)
        } else {
            self
        }
    }
}

/// Segmented control drawn like the mockups: a soft grey track with a white,
/// hairline-bordered pill for the selected option. Optional SF Symbol per option.
struct GraphiteSegmentedControl<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var systemImage: String? = nil
    }

    let options: [Option]
    @Binding var selection: Value
    var height: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = option.value }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = option.systemImage {
                            Image(systemName: icon)
                                .scaledFont(size: 14, weight: .regular)
                        }
                        Text(option.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(AppTheme.card)
                                .stroke(AppTheme.hairline, lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.fill)
        )
    }
}

/// Square outlined icon button used for copy, regenerate and edit actions (36pt).
struct IconSquareButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .scaledFont(size: 15, weight: .regular)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.card)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension SessionCategory {
    /// Outline symbol used across the graphite UI (briefcase for work, house for personal).
    var outlineSymbol: String {
        switch self {
        case .work: return "briefcase"
        case .personal: return "house"
        }
    }
}

/// Empty state from the mockups: quiet outline icon, serif title, short secondary line.
struct GraphiteEmptyState: View {
    let title: String
    let systemImage: String
    let description: Text

    init(_ title: String, systemImage: String, description: Text) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .scaledFont(size: 28, weight: .light)
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .scaledFont(size: 22, design: .serif)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
            description
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Scaled Fonts

/// A fixed-size system font that still follows the Dynamic Type setting. Sizes scale with body text,
/// large display sizes with the large title, and growth is capped so fixed-size frames hold up.
private struct ScaledSystemFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    @ScaledMetric(relativeTo: .body) private var bodyScale: CGFloat = 100
    @ScaledMetric(relativeTo: .largeTitle) private var titleScale: CGFloat = 100

    func body(content: Content) -> some View {
        let scale = (size >= 28 ? titleScale : bodyScale) / 100
        // Must stay a plain system font: calling scaledFont here would apply this modifier forever
        content.font(.system(size: size * min(scale, 1.6), weight: weight, design: design))
    }
}

extension View {
    /// Like `.font(.system(size:weight:design:))`, but scales with Dynamic Type
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}
