import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Terms of Service")
                        .font(.title.bold())
                    
                    Text("Last Updated: December 29, 2025")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Terms Sections
                VStack(alignment: .leading, spacing: 20) {
                    
                    // 1. Acceptance
                    TermsSection(
                        number: "1",
                        title: "Acceptance of Terms",
                        content: "By downloading, installing, or using Life Wrapped, you agree to be bound by these Terms of Service. If you do not agree to these terms, do not use the app."
                    )
                    
                    // 2. License
                    TermsSection(
                        number: "2",
                        title: "License Grant",
                        content: "We grant you a limited, non-exclusive, non-transferable, revocable license to use Life Wrapped for personal, non-commercial purposes on devices you own or control."
                    )
                    
                    // 3. Purchases & Refunds
                    TermsSection(
                        number: "3",
                        title: "Purchases & Refunds",
                        content: """
                        All purchases made through the App Store are final. In-app purchases, including "Smartest AI Year Wrap," are non-refundable once completed.
                        
                        Refund requests must be directed to Apple through the App Store, as Apple handles all payment processing. Apple's refund policy applies to all purchases.
                        
                        We do not process refunds directly. By making a purchase, you acknowledge and agree to these terms.
                        """
                    )
                    
                    // 4. BYOK - Third Party Services
                    TermsSection(
                        number: "4",
                        title: "Bring Your Own Key (BYOK) & Third-Party Services",
                        content: """
                        Life Wrapped offers optional integration with third-party AI services (OpenAI, Anthropic) using your own API keys. By using this feature:
                        
                        • YOU ARE SOLELY RESPONSIBLE for any costs, charges, or fees incurred through your API provider.
                        
                        • YOU ARE SOLELY RESPONSIBLE for the personal data and transcript content you choose to send to these third-party services.
                        
                        • We do not have access to your API keys beyond your device's secure Keychain storage.
                        
                        • We are not responsible for how third-party providers (OpenAI, Anthropic) handle, store, or process your data. You must review and agree to their respective terms of service and privacy policies.
                        
                        • If you do not wish to share data with external AI providers, use the on-device AI options (Local AI or Basic) which process data 100% locally.
                        """
                    )
                    
                    // 5. User Responsibilities
                    TermsSection(
                        number: "5",
                        title: "User Responsibilities",
                        content: """
                        You agree to:
                        • Obtain consent from any individuals you record (where required by law)
                        • Use the app in compliance with all applicable laws
                        • Not use the app for any illegal or unauthorized purpose
                        • Accept responsibility for all content you record and process
                        """
                    )
                    
                    // 6. Intellectual Property
                    TermsSection(
                        number: "6",
                        title: "Intellectual Property",
                        content: "Life Wrapped and its original content, features, and functionality are owned by the developer and are protected by copyright, trademark, and other intellectual property laws. Your recordings and transcripts remain your property."
                    )
                    
                    // 7. Disclaimer of Warranties
                    TermsSection(
                        number: "7",
                        title: "Disclaimer of Warranties",
                        content: """
                        THE APP IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND.
                        
                        We do not warrant that:
                        • The app will be uninterrupted or error-free
                        • Transcriptions will be 100% accurate
                        • AI-generated summaries will be accurate or complete
                        • The app will meet your specific requirements
                        
                        Speech recognition accuracy depends on audio quality, background noise, accents, and other factors beyond our control.
                        """
                    )
                    
                    // 8. Limitation of Liability
                    TermsSection(
                        number: "8",
                        title: "Limitation of Liability",
                        content: """
                        TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR:
                        
                        • Any indirect, incidental, special, consequential, or punitive damages
                        • Loss of data, profits, or business opportunities
                        • Costs incurred through third-party API usage
                        • Any actions taken based on AI-generated content
                        
                        Our total liability shall not exceed the amount you paid for the app.
                        """
                    )
                    
                    // 9. Data & Privacy
                    TermsSection(
                        number: "9",
                        title: "Data & Privacy",
                        content: "Your use of Life Wrapped is also governed by our Privacy Policy. Audio recordings and transcripts are stored locally on your device. We do not collect, transmit, or store your personal data on our servers."
                    )
                    
                    // 10. Changes to Terms
                    TermsSection(
                        number: "10",
                        title: "Changes to Terms",
                        content: "We reserve the right to modify these terms at any time. Continued use of the app after changes constitutes acceptance of the new terms."
                    )
                    
                    // 11. Contact
                    TermsSection(
                        number: "11",
                        title: "Contact",
                        content: "For questions about these Terms of Service, please contact us through our support page or GitHub repository."
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Terms Section Component

struct TermsSection: View {
    @Environment(\.colorScheme) var colorScheme
    let number: String
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.headline)
                    .foregroundStyle(AppTheme.purple)
                    .frame(width: 24, alignment: .leading)
                
                Text(title)
                    .font(.headline)
            }
            
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 32)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .allowsHitTesting(false)
        )
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        TermsOfServiceView()
    }
}
