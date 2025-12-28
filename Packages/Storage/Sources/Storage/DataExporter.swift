// =============================================================================
// Storage — Data Exporter
// =============================================================================
// Export user data to various formats (JSON, Markdown, CSV)
// =============================================================================

import Foundation
import SharedModels
import PDFKit

#if canImport(UIKit)
import UIKit
#endif

public actor DataExporter {
    private let databaseManager: DatabaseManager
    
    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - JSON Export
    
    /// Export all data to JSON format
    public func exportToJSON(year: Int? = nil) async throws -> Data {
        let allChunks = try await databaseManager.fetchAllAudioChunks()
        let allSummaries = try await databaseManager.fetchAllSummaries()
        
        // Filter by year if specified
        let chunks: [AudioChunk]
        let summaries: [Summary]
        
        if let year = year {
            let calendar = Calendar.current
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            
            chunks = allChunks.filter { $0.createdAt >= startOfYear && $0.createdAt < endOfYear }
            summaries = allSummaries.filter { $0.periodStart >= startOfYear && $0.periodStart < endOfYear }
        } else {
            chunks = allChunks
            summaries = allSummaries
        }
        
        // Fetch all transcript segments for filtered chunks
        var allSegments: [TranscriptSegment] = []
        for chunk in chunks {
            let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
            allSegments.append(contentsOf: segments)
        }
        
        let export = JSONExport(
            exportDate: Date(),
            version: "1.0",
            audioChunks: chunks.map { JSONAudioChunk(from: $0) },
            transcriptSegments: allSegments.map { JSONTranscriptSegment(from: $0) },
            summaries: summaries.map { JSONSummary(from: $0) }
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        return try encoder.encode(export)
    }
    
    // MARK: - Markdown Export
    
    /// Export all data to Markdown format
    public func exportToMarkdown(year: Int? = nil) async throws -> String {
        let allSummaries = try await databaseManager.fetchAllSummaries()
        
        // Filter by year if specified
        let summaries: [Summary]
        if let year = year {
            let calendar = Calendar.current
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            
            summaries = allSummaries.filter {
                $0.periodStart >= startOfYear && $0.periodStart < endOfYear
            }
        } else {
            summaries = allSummaries
        }
        
        var markdown = "# Life Wrapped Export\n\n"
        if let year = year {
            markdown += "**Year:** \(year)\n\n"
        }
        markdown += "**Export Date:** \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n\n"
        markdown += "---\n\n"
        
        // Group by period type
        let dailySummaries = summaries.filter { $0.periodType == .day }.sorted { $0.periodStart > $1.periodStart }
        let weeklySummaries = summaries.filter { $0.periodType == .week }.sorted { $0.periodStart > $1.periodStart }
        let monthlySummaries = summaries.filter { $0.periodType == .month }.sorted { $0.periodStart > $1.periodStart }
        
        if !dailySummaries.isEmpty {
            markdown += "## Daily Summaries\n\n"
            for summary in dailySummaries {
                markdown += formatSummaryMarkdown(summary)
            }
        }
        
        if !weeklySummaries.isEmpty {
            markdown += "## Weekly Summaries\n\n"
            for summary in weeklySummaries {
                markdown += formatSummaryMarkdown(summary)
            }
        }
        
        if !monthlySummaries.isEmpty {
            markdown += "## Monthly Summaries\n\n"
            for summary in monthlySummaries {
                markdown += formatSummaryMarkdown(summary)
            }
        }
        
        return markdown
    }
    
    // MARK: - PDF Export
    
    /// Export summaries to PDF format (summaries only, not full transcripts)
    public func exportToPDF(year: Int? = nil, redactPeople: Bool = false, redactPlaces: Bool = false) async throws -> Data {
        let summaries = try await databaseManager.fetchAllSummaries()
        
        // Filter by year if specified
        let filteredSummaries: [Summary]
        if let year = year {
            let calendar = Calendar.current
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            
            filteredSummaries = summaries.filter {
                $0.periodStart >= startOfYear && $0.periodStart < endOfYear
            }
        } else {
            filteredSummaries = summaries
        }
        
        // Check if this is a Year Wrap export
        let yearWrap = filteredSummaries.first(where: { $0.periodType == .yearWrap })
        
        if let yearWrap = yearWrap, let year = year {
            // Render enhanced Year Wrap PDF
            return try await renderYearWrapPDF(yearWrap: yearWrap, year: year, redactPeople: redactPeople, redactPlaces: redactPlaces)
        } else {
            // Render standard summary PDF
            return renderStandardPDF(summaries: filteredSummaries, year: year)
        }
    }
    
    // MARK: - Standard PDF Rendering
    
    private func renderStandardPDF(summaries: [Summary], year: Int?) -> Data {
        // Create PDF
        let pdfMetaData = [
            kCGPDFContextCreator: "Life Wrapped",
            kCGPDFContextTitle: year != nil ? "Life Wrapped Export \(year!)" : "Life Wrapped Export All"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            var yOffset: CGFloat = 50
            
            // Add disclaimer on first page
            context.beginPage()
            let disclaimerText = "This PDF contains summaries only, not full transcripts."
            let disclaimerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 12),
                .foregroundColor: UIColor.gray
            ]
            let disclaimerSize = disclaimerText.size(withAttributes: disclaimerAttributes)
            disclaimerText.draw(at: CGPoint(x: 50, y: yOffset), withAttributes: disclaimerAttributes)
            yOffset += disclaimerSize.height + 30
            
            // Group summaries by period type
            let groupedSummaries = Dictionary(grouping: summaries) { $0.periodType }
            let sortedGroups = groupedSummaries.sorted { $0.key.rawValue < $1.key.rawValue }
            
            for (periodType, summaries) in sortedGroups {
                // Add section header
                let headerText = "\(periodType.displayName) Summaries"
                let headerAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 18),
                    .foregroundColor: UIColor.black
                ]
                let headerSize = headerText.size(withAttributes: headerAttributes)
                
                if yOffset + headerSize.height > pageRect.height - 50 {
                    context.beginPage()
                    yOffset = 50
                }
                
                headerText.draw(at: CGPoint(x: 50, y: yOffset), withAttributes: headerAttributes)
                yOffset += headerSize.height + 20
                
                // Add each summary
                for summary in summaries.sorted(by: { $0.periodStart > $1.periodStart }) {
                    let titleText = formatPeriod(summary.periodType, start: summary.periodStart, end: summary.periodEnd)
                    let titleAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 14),
                        .foregroundColor: UIColor.black
                    ]
                    
                    let bodyAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12),
                        .foregroundColor: UIColor.darkGray
                    ]
                    
                    let titleSize = titleText.boundingRect(
                        with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin],
                        attributes: titleAttributes,
                        context: nil
                    ).size
                    
                    let bodySize = summary.text.boundingRect(
                        with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin],
                        attributes: bodyAttributes,
                        context: nil
                    ).size
                    
                    // Check if we need a new page
                    if yOffset + titleSize.height + bodySize.height + 40 > pageRect.height - 50 {
                        context.beginPage()
                        yOffset = 50
                    }
                    
                    // Draw title
                    titleText.draw(
                        with: CGRect(x: 50, y: yOffset, width: pageRect.width - 100, height: titleSize.height),
                        options: [.usesLineFragmentOrigin],
                        attributes: titleAttributes,
                        context: nil
                    )
                    yOffset += titleSize.height + 10
                    
                    // Draw body
                    summary.text.draw(
                        with: CGRect(x: 50, y: yOffset, width: pageRect.width - 100, height: bodySize.height),
                        options: [.usesLineFragmentOrigin],
                        attributes: bodyAttributes,
                        context: nil
                    )
                    yOffset += bodySize.height + 30
                }
                
                yOffset += 20 // Extra space between sections
            }
        }
        
        return data
    }
    
    // MARK: - Year Wrap PDF Rendering
    
    private func renderYearWrapPDF(yearWrap: Summary, year: Int, redactPeople: Bool, redactPlaces: Bool) async throws -> Data {
        guard let parsedData = parseYearWrapJSON(from: yearWrap.text) else {
            // Fallback to standard PDF if parsing fails
            return renderStandardPDF(summaries: [yearWrap], year: year)
        }
        
        // Fetch session stats for the year
        let stats = try await fetchYearStats(year: year)
        
        let pdfMetaData = [
            kCGPDFContextCreator: "Life Wrapped",
            kCGPDFContextTitle: "Year Wrap \(year)"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            var yOffset: CGFloat = 0
            
            // Page 1: Hero Section
            context.beginPage()
            renderHeroPage(context: context, pageRect: pageRect, data: parsedData, year: year)
            
            // Page 2: Stats
            context.beginPage()
            yOffset = 50
            yOffset = renderStatsSection(context: context, pageRect: pageRect, yOffset: yOffset, stats: stats)
            
            // Insights Sections
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Major Arcs", emoji: "🌟", items: parsedData.majorArcs, color: YearWrapTheme.sectionColors[0], requireNewPage: false)
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Biggest Wins", emoji: "🏆", items: parsedData.biggestWins, color: YearWrapTheme.sectionColors[1], requireNewPage: true)
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Biggest Losses", emoji: "💔", items: parsedData.biggestLosses, color: YearWrapTheme.sectionColors[2], requireNewPage: true)
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Biggest Challenges", emoji: "⚡", items: parsedData.biggestChallenges, color: YearWrapTheme.sectionColors[3], requireNewPage: true)
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Finished Projects", emoji: "✅", items: parsedData.finishedProjects, color: YearWrapTheme.sectionColors[4], requireNewPage: true)
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Unfinished Projects", emoji: "🚧", items: parsedData.unfinishedProjects, color: YearWrapTheme.sectionColors[5], requireNewPage: true)
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Top Worked On", emoji: "💼", items: parsedData.topWorkedOnTopics, color: YearWrapTheme.sectionColors[6], requireNewPage: true)
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Top Talked About", emoji: "💬", items: parsedData.topTalkedAboutThings, color: YearWrapTheme.sectionColors[7], requireNewPage: true)
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Valuable Actions", emoji: "🎯", items: parsedData.valuableActionsTaken, color: YearWrapTheme.sectionColors[8], requireNewPage: true)
            yOffset = renderInsightSection(context: context, pageRect: pageRect, yOffset: yOffset, title: "Opportunities Missed", emoji: "🤔", items: parsedData.opportunitiesMissed, color: YearWrapTheme.sectionColors[9], requireNewPage: true)
            
            // People & Places
            yOffset = renderPeopleSection(context: context, pageRect: pageRect, yOffset: yOffset, people: parsedData.peopleMentioned, redact: redactPeople)
            yOffset = renderPlacesSection(context: context, pageRect: pageRect, yOffset: yOffset, places: parsedData.placesVisited, redact: redactPlaces)
            
            // Footer with redaction note if needed
            if redactPeople || redactPlaces {
                context.beginPage()
                renderPrivacyFooter(context: context, pageRect: pageRect, redactPeople: redactPeople, redactPlaces: redactPlaces)
            }
        }
        
        return data
    }
    
    private func renderHeroPage(context: UIGraphicsPDFRendererContext, pageRect: CGRect, data: YearWrapData, year: Int) {
        let ctx = context.cgContext
        
        // Background gradient (purple)
        let colors = [
            YearWrapTheme.uiColor(YearWrapTheme.electricPurple).cgColor,
            YearWrapTheme.uiColor(YearWrapTheme.hotPink).cgColor
        ]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: pageRect.height), options: [])
        
        // Year title
        let yearTitle = "\(year)"
        let yearAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 72),
            .foregroundColor: UIColor.white
        ]
        let yearSize = yearTitle.size(withAttributes: yearAttributes)
        yearTitle.draw(at: CGPoint(x: (pageRect.width - yearSize.width) / 2, y: 250), withAttributes: yearAttributes)
        
        // Year summary
        let summaryText = data.yearSummary
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.white
        ]
        let summaryRect = CGRect(x: 50, y: 380, width: pageRect.width - 100, height: 300)
        summaryText.draw(with: summaryRect, options: [.usesLineFragmentOrigin], attributes: summaryAttributes, context: nil)
    }
    
    private func renderStatsSection(context: UIGraphicsPDFRendererContext, pageRect: CGRect, yOffset: CGFloat, stats: (sessions: Int, duration: TimeInterval, words: Int)) -> CGFloat {
        var y = yOffset
        
        let headerText = "Your Year in Numbers"
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.black
        ]
        let headerSize = headerText.size(withAttributes: headerAttributes)
        headerText.draw(at: CGPoint(x: 50, y: y), withAttributes: headerAttributes)
        y += headerSize.height + 30
        
        // Stats cards
        let statWidth: CGFloat = 150
        let statHeight: CGFloat = 120
        let spacing: CGFloat = 20
        let startX: CGFloat = (pageRect.width - (statWidth * 3 + spacing * 2)) / 2
        
        let statsData = [
            ("🎙️", "\(stats.sessions)", "Sessions", YearWrapTheme.vibrantOrange),
            ("⏱️", String(format: "%.1f", stats.duration / 3600), "Hours", YearWrapTheme.hotPink),
            ("💬", "\(stats.words)", "Words", YearWrapTheme.spotifyGreen)
        ]
        
        for (index, (emoji, value, label, colorHex)) in statsData.enumerated() {
            let x = startX + CGFloat(index) * (statWidth + spacing)
            let rect = CGRect(x: x, y: y, width: statWidth, height: statHeight)
            
            // Background
            context.cgContext.setFillColor(YearWrapTheme.uiColor(colorHex).withAlphaComponent(0.15).cgColor)
            context.cgContext.fillEllipse(in: rect.insetBy(dx: 10, dy: 10))
            
            // Emoji
            let emojiAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 32)]
            let emojiSize = emoji.size(withAttributes: emojiAttributes)
            emoji.draw(at: CGPoint(x: rect.midX - emojiSize.width / 2, y: rect.minY + 15), withAttributes: emojiAttributes)
            
            // Value
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 28),
                .foregroundColor: YearWrapTheme.uiColor(colorHex)
            ]
            let valueSize = value.size(withAttributes: valueAttributes)
            value.draw(at: CGPoint(x: rect.midX - valueSize.width / 2, y: rect.midY), withAttributes: valueAttributes)
            
            // Label
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.gray
            ]
            let labelSize = label.size(withAttributes: labelAttributes)
            label.draw(at: CGPoint(x: rect.midX - labelSize.width / 2, y: rect.maxY - 25), withAttributes: labelAttributes)
        }
        
        return y + statHeight + 40
    }
    
    @discardableResult
    private func renderInsightSection(context: UIGraphicsPDFRendererContext, pageRect: CGRect, yOffset: CGFloat, title: String, emoji: String, items: [ClassifiedItem], color: String, requireNewPage: Bool) -> CGFloat {
        if items.isEmpty {
            return yOffset
        }
        
        if requireNewPage {
            context.beginPage()
        }
        
        var y: CGFloat = requireNewPage ? 50 : yOffset
        
        // Section header with emoji
        let headerText = "\(emoji) \(title)"
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: YearWrapTheme.uiColor(color)
        ]
        let headerSize = headerText.size(withAttributes: headerAttributes)
        headerText.draw(at: CGPoint(x: 50, y: y), withAttributes: headerAttributes)
        y += headerSize.height + 20
        
        // Items as bullets with category indicators
        let bulletAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.darkGray
        ]
        
        for item in items {
            // Add category prefix for "All" view
            let categoryPrefix = getCategoryPrefix(item.category)
            let bulletText = "• \(categoryPrefix)\(item.text)"
            let bulletSize = bulletText.boundingRect(
                with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: bulletAttributes,
                context: nil
            ).size
            
            if y + bulletSize.height > pageRect.height - 50 {
                context.beginPage()
                y = 50
            }
            
            bulletText.draw(with: CGRect(x: 60, y: y, width: pageRect.width - 110, height: bulletSize.height), options: [.usesLineFragmentOrigin], attributes: bulletAttributes, context: nil)
            y += bulletSize.height + 8
        }
        
        return y + 30
    }
    
    private func getCategoryPrefix(_ category: ItemCategory) -> String {
        switch category {
        case .work: return "💼 "
        case .personal: return "🏠 "
        case .both: return "🔀 "
        }
    }
    
    private func renderPeopleSection(context: UIGraphicsPDFRendererContext, pageRect: CGRect, yOffset: CGFloat, people: [PersonMention], redact: Bool) -> CGFloat {
        if people.isEmpty {
            return yOffset
        }
        
        context.beginPage()
        var y: CGFloat = 50
        
        let headerText = "👥 People Mentioned"
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: YearWrapTheme.uiColor(YearWrapTheme.hotPink)
        ]
        let headerSize = headerText.size(withAttributes: headerAttributes)
        headerText.draw(at: CGPoint(x: 50, y: y), withAttributes: headerAttributes)
        y += headerSize.height + 20
        
        let itemAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.darkGray
        ]
        
        for person in people {
            let name = redact ? "[Person]" : person.name
            var itemText = "• \(name)"
            if let relationship = person.relationship, !redact {
                itemText += " — \(relationship)"
            }
            
            let itemSize = itemText.boundingRect(
                with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: itemAttributes,
                context: nil
            ).size
            
            if y + itemSize.height > pageRect.height - 50 {
                context.beginPage()
                y = 50
            }
            
            itemText.draw(with: CGRect(x: 60, y: y, width: pageRect.width - 110, height: itemSize.height), options: [.usesLineFragmentOrigin], attributes: itemAttributes, context: nil)
            y += itemSize.height + 8
        }
        
        return y + 30
    }
    
    private func renderPlacesSection(context: UIGraphicsPDFRendererContext, pageRect: CGRect, yOffset: CGFloat, places: [PlaceVisit], redact: Bool) -> CGFloat {
        if places.isEmpty {
            return yOffset
        }
        
        context.beginPage()
        var y: CGFloat = 50
        
        let headerText = "📍 Places Visited"
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: YearWrapTheme.uiColor(YearWrapTheme.electricPurple)
        ]
        let headerSize = headerText.size(withAttributes: headerAttributes)
        headerText.draw(at: CGPoint(x: 50, y: y), withAttributes: headerAttributes)
        y += headerSize.height + 20
        
        let itemAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.darkGray
        ]
        
        for place in places {
            let name = redact ? "[Location]" : place.name
            var itemText = "• \(name)"
            if let frequency = place.frequency, !redact {
                itemText += " — \(frequency)"
            }
            
            let itemSize = itemText.boundingRect(
                with: CGSize(width: pageRect.width - 100, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: itemAttributes,
                context: nil
            ).size
            
            if y + itemSize.height > pageRect.height - 50 {
                context.beginPage()
                y = 50
            }
            
            itemText.draw(with: CGRect(x: 60, y: y, width: pageRect.width - 110, height: itemSize.height), options: [.usesLineFragmentOrigin], attributes: itemAttributes, context: nil)
            y += itemSize.height + 8
        }
        
        return y + 30
    }
    
    private func renderPrivacyFooter(context: UIGraphicsPDFRendererContext, pageRect: CGRect, redactPeople: Bool, redactPlaces: Bool) {
        let footerText = "Privacy Note: "
        let detailsText: String
        if redactPeople && redactPlaces {
            detailsText = "All people and location names have been redacted in this export."
        } else if redactPeople {
            detailsText = "All people names have been redacted in this export."
        } else {
            detailsText = "All location names have been redacted in this export."
        }
        
        let fullText = footerText + detailsText
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 12),
            .foregroundColor: UIColor.gray
        ]
        
        fullText.draw(with: CGRect(x: 50, y: 50, width: pageRect.width - 100, height: 100), options: [.usesLineFragmentOrigin], attributes: footerAttributes, context: nil)
    }
    
    // MARK: - Helpers
    
    private func parseYearWrapJSON(from text: String) -> YearWrapData? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Extract all fields
        guard let yearTitle = json["year_title"] as? String,
              let yearSummary = json["year_summary"] as? String else {
            return nil
        }
        
        // Helper to parse classified items (supports both old string format and new object format)
        func parseClassifiedItems(_ key: String) -> [ClassifiedItem] {
            guard let array = json[key] as? [Any] else { return [] }
            
            return array.compactMap { item in
                // New format: {"text": "...", "category": "work|personal|both"}
                if let dict = item as? [String: String],
                   let text = dict["text"],
                   let categoryStr = dict["category"],
                   let category = ItemCategory(rawValue: categoryStr) {
                    return ClassifiedItem(text: text, category: category)
                }
                // Old format: just strings - default to "both"
                else if let text = item as? String {
                    return ClassifiedItem(text: text, category: .both)
                }
                return nil
            }
        }
        
        return YearWrapData(
            yearTitle: yearTitle,
            yearSummary: yearSummary,
            majorArcs: parseClassifiedItems("major_arcs"),
            biggestWins: parseClassifiedItems("biggest_wins"),
            biggestLosses: parseClassifiedItems("biggest_losses"),
            biggestChallenges: parseClassifiedItems("biggest_challenges"),
            finishedProjects: parseClassifiedItems("finished_projects"),
            unfinishedProjects: parseClassifiedItems("unfinished_projects"),
            topWorkedOnTopics: parseClassifiedItems("top_worked_on_topics"),
            topTalkedAboutThings: parseClassifiedItems("top_talked_about_things"),
            valuableActionsTaken: parseClassifiedItems("valuable_actions_taken"),
            opportunitiesMissed: parseClassifiedItems("opportunities_missed"),
            peopleMentioned: (json["people_mentioned"] as? [[String: String]] ?? []).compactMap { dict in
                guard let name = dict["name"] else { return nil }
                return PersonMention(name: name, relationship: dict["relationship"], impact: dict["impact"])
            },
            placesVisited: (json["places_visited"] as? [[String: String]] ?? []).compactMap { dict in
                guard let name = dict["name"] else { return nil }
                return PlaceVisit(name: name, frequency: dict["frequency"], context: dict["context"])
            }
        )
    }
    
    private func fetchYearStats(year: Int) async throws -> (sessions: Int, duration: TimeInterval, words: Int) {
        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        
        let chunks = try await databaseManager.fetchAllAudioChunks()
        let yearChunks = chunks.filter { $0.createdAt >= startOfYear && $0.createdAt < endOfYear }
        
        var totalDuration: TimeInterval = 0
        var totalWords: Int = 0
        var sessionIds: Set<UUID> = []
        
        for chunk in yearChunks {
            sessionIds.insert(chunk.sessionId)
            totalDuration += chunk.duration
            
            let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
            for segment in segments {
                totalWords += segment.text.split(separator: " ").count
            }
        }
        
        return (sessionIds.count, totalDuration, totalWords)
    }
    
    // MARK: - Helper Methods
    
    private func formatSummaryMarkdown(_ summary: Summary) -> String {
        var md = "### \(formatPeriod(summary.periodType, start: summary.periodStart, end: summary.periodEnd))\n\n"
        
        md += "\(summary.text)\n\n"
        
        md += "**Date:** \(DateFormatter.localizedString(from: summary.periodStart, dateStyle: .medium, timeStyle: .none))\n\n"
        
        md += "---\n\n"
        
        return md
    }
    
    private func formatPeriod(_ type: PeriodType, start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        switch type {
        case .session:
            formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
            return "Session on \(formatter.string(from: start))"
        case .hour:
            formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
            return formatter.string(from: start)
        case .day:
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            return formatter.string(from: start)
        case .week:
            formatter.dateFormat = "MMM d"
            return "Week of \(formatter.string(from: start))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: start)
        case .year:
            formatter.dateFormat = "yyyy"
            return "Year \(formatter.string(from: start))"
        case .yearWrap:
            formatter.dateFormat = "yyyy"
            return "Year Wrap \(formatter.string(from: start))"
        }
    }

    
    // MARK: - Storage Info
    
    /// Get storage usage statistics
    public func getStorageInfo(localModelSize: Int64? = nil) async throws -> StorageInfo {
        let chunks = try await databaseManager.fetchAllAudioChunks()
        let summaries = try await databaseManager.fetchAllSummaries()
        
        var totalAudioSize: Int64 = 0
        for chunk in chunks {
            if FileManager.default.fileExists(atPath: chunk.fileURL.path) {
                let attrs = try FileManager.default.attributesOfItem(atPath: chunk.fileURL.path)
                totalAudioSize += attrs[.size] as? Int64 ?? 0
            }
        }
        
        return StorageInfo(
            audioChunkCount: chunks.count,
            summaryCount: summaries.count,
            totalAudioSize: totalAudioSize,
            databaseSize: try await getDatabaseSize(),
            localModelSize: localModelSize
        )
    }
    
    private func getDatabaseSize() async throws -> Int64 {
        // Get database path from DatabaseManager
        let dbPath = await databaseManager.getDatabasePath()
        
        if FileManager.default.fileExists(atPath: dbPath) {
            let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
            if let size = attrs[FileAttributeKey.size] as? Int64 {
                return size
            }
        }
        
        return 0
    }
}

// MARK: - Export Models

public struct JSONExport: Codable {
    let exportDate: Date
    let version: String
    let audioChunks: [JSONAudioChunk]
    let transcriptSegments: [JSONTranscriptSegment]?
    let summaries: [JSONSummary]
}

public struct JSONAudioChunk: Codable {
    let id: UUID
    let fileURL: URL
    let startTime: Date
    let endTime: Date
    let format: String
    let sampleRate: Int
    let createdAt: Date
    let sessionId: UUID
    let chunkIndex: Int
    
    init(from chunk: AudioChunk) {
        self.id = chunk.id
        self.fileURL = chunk.fileURL
        self.startTime = chunk.startTime
        self.endTime = chunk.endTime
        self.format = chunk.format.rawValue
        self.sampleRate = chunk.sampleRate
        self.createdAt = chunk.createdAt
        self.sessionId = chunk.sessionId
        self.chunkIndex = chunk.chunkIndex
    }
}

public struct JSONTranscriptSegment: Codable {
    let id: UUID
    let audioChunkID: UUID
    let startTime: Double
    let endTime: Double
    let text: String
    let confidence: Float
    let languageCode: String
    let createdAt: Date
    let sentimentScore: Double?
    
    init(from segment: TranscriptSegment) {
        self.id = segment.id
        self.audioChunkID = segment.audioChunkID
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.text = segment.text
        self.confidence = segment.confidence
        self.languageCode = segment.languageCode
        self.createdAt = segment.createdAt
        self.sentimentScore = segment.sentimentScore
    }
}

public struct JSONSummary: Codable {
    let id: UUID
    let periodType: String
    let periodStart: Date
    let periodEnd: Date
    let text: String
    let createdAt: Date
    let sessionId: UUID?
    
    init(from summary: Summary) {
        self.id = summary.id
        self.periodType = summary.periodType.rawValue
        self.periodStart = summary.periodStart
        self.periodEnd = summary.periodEnd
        self.text = summary.text
        self.createdAt = summary.createdAt
        self.sessionId = summary.sessionId
    }
}

public struct StorageInfo: Sendable {
    public let audioChunkCount: Int
    public let summaryCount: Int
    public let totalAudioSize: Int64
    public let databaseSize: Int64
    public let localModelSize: Int64?
    
    public var totalSize: Int64 {
        totalAudioSize + databaseSize + (localModelSize ?? 0)
    }
    
    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    public var formattedAudioSize: String {
        ByteCountFormatter.string(fromByteCount: totalAudioSize, countStyle: .file)
    }
    
    public var formattedDatabaseSize: String {
        ByteCountFormatter.string(fromByteCount: databaseSize, countStyle: .file)
    }
    
    public var formattedLocalModelSize: String {
        guard let localModelSize = localModelSize else {
            return "Not Downloaded"
        }
        return ByteCountFormatter.string(fromByteCount: localModelSize, countStyle: .file)
    }
}

// MARK: - Year Wrap Theme

private struct YearWrapTheme {
    static let vibrantOrange = "#FF6B35"
    static let hotPink = "#FF006E"
    static let electricPurple = "#8338EC"
    static let spotifyGreen = "#06FFA5"
    
    static let sectionColors = [
        "#FF6B35", "#FF8C42", "#FFA600", "#FFB800", "#06FFA5",
        "#00D9FF", "#3A86FF", "#8338EC", "#B5179E", "#FF006E"
    ]
    
    static func uiColor(_ hex: String) -> UIColor {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        r = (int >> 16) & 0xFF
        g = (int >> 8) & 0xFF
        b = int & 0xFF
        return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1.0)
    }
}
