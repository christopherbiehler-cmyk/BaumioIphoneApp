import SwiftUI
import UIKit

// MARK: - Bauzeitstrahl (Gantt)

private struct GanttBarInfo: Equatable {
    let id: UUID
    let frame: CGRect
}

private struct GanttBarInfoKey: PreferenceKey {
    static var defaultValue: [GanttBarInfo] = []
    static func reduce(value: inout [GanttBarInfo], nextValue: () -> [GanttBarInfo]) {
        value.append(contentsOf: nextValue())
    }
}

struct GanttChartView: View {
    let items: [ScheduleItem]
    var light = false

    @State private var barInfos: [UUID: GanttBarInfo] = [:]

    private var sorted: [ScheduleItem] {
        items.sorted { $0.date < $1.date }
    }

    private var earliest: Date? { items.map(\.date).min() }

    private var latest: Date? {
        items.map { endDate(of: $0) }.max()
    }

    private var totalDays: Int {
        guard let earliest, let latest else { return 1 }
        return max(1, days(from: earliest, to: latest))
    }

    private var primaryColor: Color { light ? .black : BaumioTheme.primaryText }
    private var secondaryColor: Color { light ? Color(hex: "555555") : BaumioTheme.secondaryText }
    private var arrowColor: Color { light ? Color(hex: "F59E0B") : BaumioTheme.warning }

    var body: some View {
        if items.isEmpty {
            Text("Keine Termine für den Zeitstrahl vorhanden.")
                .font(.footnote)
                .foregroundStyle(secondaryColor)
        } else if let earliest {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(earliest.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    if let latest { Text(latest.formatted(date: .abbreviated, time: .omitted)) }
                }
                .font(.caption.bold())
                .foregroundStyle(secondaryColor)

                ForEach(sorted) { item in
                    let offset = days(from: earliest, to: item.date)
                    let duration = max(item.durationDays, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title).font(.subheadline.bold()).foregroundStyle(primaryColor).lineLimit(1)
                            Spacer()
                            if let depID = item.dependsOn, let dep = items.first(where: { $0.id == depID }) {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(arrowColor)
                                Text(dep.title)
                                    .font(.caption2)
                                    .foregroundStyle(arrowColor)
                                    .lineLimit(1)
                            }
                            Text("\(item.date.formatted(date: .abbreviated, time: .omitted)) · \(duration) Tg")
                                .font(.caption2)
                                .foregroundStyle(secondaryColor)
                        }
                        GeometryReader { geo in
                            let unit = geo.size.width / CGFloat(totalDays)
                            let x = CGFloat(offset) * unit
                            let w = max(CGFloat(duration) * unit, 8)
                            let containerFrame = geo.frame(in: .named("ganttContainer"))
                            let barFrame = CGRect(
                                x: containerFrame.minX + x,
                                y: containerFrame.midY - 9,
                                width: w,
                                height: 18
                            )
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(light ? Color(hex: "E5E7EB") : BaumioTheme.elevatedSurface)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(statusColor(item.status))
                                    .frame(width: w)
                                    .offset(x: x)
                            }
                            .preference(key: GanttBarInfoKey.self, value: [GanttBarInfo(id: item.id, frame: barFrame)])
                        }
                        .frame(height: 18)
                    }
                }
            }
            .coordinateSpace(name: "ganttContainer")
            .onPreferenceChange(GanttBarInfoKey.self) { infos in
                for info in infos { barInfos[info.id] = info }
            }
            .overlay {
                Canvas { ctx, _ in
                    let shading: GraphicsContext.Shading = .color(arrowColor)
                    for item in sorted {
                        guard let depID = item.dependsOn,
                              let from = barInfos[depID],
                              let to = barInfos[item.id] else { continue }
                        let startPt = CGPoint(x: from.frame.maxX, y: from.frame.midY)
                        let endPt   = CGPoint(x: to.frame.minX,  y: to.frame.midY)
                        var line = Path()
                        line.move(to: startPt)
                        line.addLine(to: CGPoint(x: startPt.x + 4, y: startPt.y))
                        line.addLine(to: CGPoint(x: startPt.x + 4, y: endPt.y))
                        line.addLine(to: endPt)
                        ctx.stroke(line, with: shading, lineWidth: 1.5)
                        var head = Path()
                        head.move(to: CGPoint(x: endPt.x - 5, y: endPt.y - 4))
                        head.addLine(to: endPt)
                        head.addLine(to: CGPoint(x: endPt.x - 5, y: endPt.y + 4))
                        ctx.stroke(head, with: shading, lineWidth: 1.5)
                    }
                }
            }
        }
    }

    private func endDate(of item: ScheduleItem) -> Date {
        Calendar.current.date(byAdding: .day, value: max(item.durationDays, 1), to: item.date) ?? item.date
    }

    private func days(from: Date, to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: from), to: Calendar.current.startOfDay(for: to)).day ?? 0
    }
}

/// Druck-Layout (weißer Hintergrund) für den PDF-Export.
struct GanttPDFPage: View {
    let items: [ScheduleItem]
    let projectName: String
    let exportDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bauzeitenplan").font(.system(size: 24, weight: .bold))
                Text(projectName).font(.system(size: 15))
                    .foregroundStyle(Color(hex: "555555"))
                Text("Erstellt am \(exportDate.formatted(date: .long, time: .omitted)) · Baumio")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "888888"))
            }
            Divider()
            GanttChartView(items: items, light: true)
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(width: 794) // A4-Breite bei 96 dpi
        .background(Color.white)
    }
}

/// Rendert eine beliebige SwiftUI-View als einseitige PDF und gibt die Datei-URL zurück.
enum PDFExporter {
    @MainActor
    static func export<Content: View>(_ content: Content, fileName: String, width: CGFloat = 794) -> URL? {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        var result: URL?
        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            result = url
        }
        return result
    }
}

enum GanttPDFExporter {
    /// Rendert den Bauzeitenplan als PDF und gibt die Datei-URL zurück.
    @MainActor
    static func export(items: [ScheduleItem], projectName: String, date: Date) -> URL? {
        PDFExporter.export(GanttPDFPage(items: items, projectName: projectName, exportDate: date), fileName: "Bauzeitenplan.pdf")
    }
}

/// Wiederverwendbarer Briefkopf für PDF-Exporte (weißes Layout).
struct PDFHeader: View {
    let title: String
    let projectName: String
    let exportDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 24, weight: .bold))
            Text(projectName).font(.system(size: 15)).foregroundStyle(Color(hex: "555555"))
            Text("Erstellt am \(exportDate.formatted(date: .long, time: .omitted)) · Baumio")
                .font(.system(size: 11)).foregroundStyle(Color(hex: "888888"))
        }
    }
}

// MARK: - Gemeinsame PDF-Bausteine

/// Blauer Banner-Header für offizielle Dokumente.
private struct PDFBanner: View {
    let title: String
    let subtitle: String
    let exportDate: Date
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.75))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(exportDate.formatted(date: .long, time: .omitted))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                Text("Baumio App").font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(hex: "1C3557"))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Zweiseitiges Unterschriftenfeld für offizielle Dokumente.
struct PDFSignatureSection: View {
    var label1: String = "Auftraggeber"
    var label2: String = "Auftragnehmer / Bauleiter"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UNTERSCHRIFTEN")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "888888"))
                .padding(.top, 10)
            HStack(alignment: .bottom, spacing: 40) {
                signatureBox(label1)
                signatureBox(label2)
            }
        }
    }
    private func signatureBox(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Spacer().frame(height: 52)
            Rectangle().fill(Color(hex: "222222")).frame(height: 1)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: "333333"))
            Text("Ort, Datum, Unterschrift").font(.system(size: 9)).foregroundStyle(Color(hex: "999999"))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Mängelprotokoll PDF

/// Professionelles Mängelprotokoll – zum Teilen mit Handwerkern und Auftraggebern.
struct DefectsPDFPage: View {
    let defects: [DefectItem]
    let projectName: String
    let exportDate: Date
    var project: Project? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PDFBanner(title: "MÄNGELPROTOKOLL", subtitle: "Dokumentation festgestellter Mängel", exportDate: exportDate)
                .padding(.bottom, 12)

            projectInfoRow

            if !defects.isEmpty {
                Text("FESTGESTELLTE MÄNGEL — \(defects.count) Pos.")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "888888"))
                    .padding(.top, 12).padding(.bottom, 4)
                ForEach(Array(defects.enumerated()), id: \.element.id) { i, d in
                    defectCard(d, number: i + 1)
                }
            } else {
                Text("Keine Mängel erfasst.").font(.system(size: 12)).padding(.top, 12)
            }

            noteField(title: "ABSCHLIESSENDE BEMERKUNGEN").padding(.top, 12)

            Spacer(minLength: 12)
            Rectangle().fill(Color(hex: "1C3557")).frame(height: 1)
            PDFSignatureSection()
        }
        .padding(36).frame(width: 794).background(Color.white)
    }

    private var projectInfoRow: some View {
        HStack(spacing: 0) {
            infoCellPDF(label: "Projekt", value: projectName)
            Divider().frame(maxHeight: 36)
            if let a = project?.address, !a.isEmpty {
                infoCellPDF(label: "Anschrift", value: a)
                Divider().frame(maxHeight: 36)
            }
            infoCellPDF(label: "Erstellt am", value: exportDate.formatted(date: .abbreviated, time: .omitted))
        }
        .padding(10)
        .background(Color(hex: "F5F7FA"))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func defectCard(_ d: DefectItem, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Nr. \(number)  ·  \(d.title)")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                priorityTag(d.priority)
                statusTag(d.status)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(hex: "F0F4F8"))

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    detailLine("Gewerk",       d.trade.isEmpty ? "–" : d.trade)
                    detailLine("Schwere",      d.severity)
                    detailLine("Priorität",    d.priority.rawValue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    detailLine("Verantwortlich", d.responsible.isEmpty ? "–" : d.responsible)
                    detailLine("Frist bis",      d.deadline.formatted(date: .abbreviated, time: .omitted))
                    detailLine("Wichtigkeit",    d.importance)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 7)

            if !d.description.isEmpty {
                Text(d.description)
                    .font(.system(size: 10)).foregroundStyle(Color(hex: "333333"))
                    .padding(.horizontal, 10).padding(.bottom, 5)
            }

            HStack(spacing: 20) {
                checkboxLabel("Fotodokumentation beigefügt")
                checkboxLabel("Kostenvoranschlag / Rechnung erhalten")
                Spacer()
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "DDDDDD"), lineWidth: 1))
        .padding(.bottom, 8)
    }

    private func priorityTag(_ p: Priority) -> some View {
        let (color, label): (Color, String) = {
            switch p {
            case .high:   (Color(hex: "EF4444"), "HOCH")
            case .medium: (Color(hex: "F59E0B"), "MITTEL")
            case .low:    (Color(hex: "22C55E"), "NIEDRIG")
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(.trailing, 4)
    }

    private func statusTag(_ status: String) -> some View {
        let done = status.lowercased() == "behoben"
        return Text(status)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(done ? Color(hex: "22C55E").opacity(0.15) : Color(hex: "EF4444").opacity(0.15))
            .foregroundStyle(done ? Color(hex: "22C55E") : Color(hex: "EF4444"))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":").font(.system(size: 9)).foregroundStyle(Color(hex: "888888"))
            Text(value).font(.system(size: 9, weight: .semibold))
        }
    }
}

// MARK: - Abnahmeprotokoll PDF

/// Offizielles Übergabe- & Abnahmeprotokoll mit zwei Unterschriftenfeldern.
struct HandoverPDFPage: View {
    let items: [HandoverItem]
    let projectName: String
    let exportDate: Date
    var project: Project? = nil

    private var grouped: [(String, [HandoverItem])] {
        var seen = Set<String>()
        let rooms = items.compactMap { $0.room.isEmpty ? nil : $0.room }.filter { seen.insert($0).inserted }
        var result = rooms.map { r in (r, items.filter { $0.room == r }) }
        let noRoom = items.filter { $0.room.isEmpty }
        if !noRoom.isEmpty { result.append(("Allgemein", noRoom)) }
        return result
    }
    private var acceptedCount: Int { items.filter { $0.status == .akzeptiert }.count }
    private var reservationCount: Int { items.filter { $0.status == .vorbehalt }.count }
    private var openCount: Int { items.count - acceptedCount - reservationCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PDFBanner(title: "ABNAHMEPROTOKOLL", subtitle: "Übergabe & Abnahme", exportDate: exportDate)
                .padding(.bottom, 12)

            // Projektinfo + Abnahmedatum
            HStack(spacing: 0) {
                infoCellPDF(label: "Projekt", value: projectName)
                Divider().frame(maxHeight: 36)
                if let a = project?.address, !a.isEmpty {
                    infoCellPDF(label: "Anschrift", value: a)
                    Divider().frame(maxHeight: 36)
                }
                if let p = project {
                    infoCellPDF(label: "Gepl. Fertigstellung", value: p.plannedEndDate.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .padding(10).background(Color(hex: "F5F7FA")).clipShape(RoundedRectangle(cornerRadius: 6))

            // Vertragspartner
            Text("VERTRAGSPARTNER")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "888888")).padding(.top, 12)
            HStack(spacing: 24) {
                participantField("Auftraggeber (Name / Firma)")
                participantField("Auftragnehmer / Bauleiter (Name / Firma)")
            }

            // Abnahmedatum + Ort
            HStack(spacing: 24) {
                fillLine("Abnahmedatum")
                fillLine("Ort der Abnahme")
            }
            .padding(.top, 8)

            // Statistik
            HStack(spacing: 16) {
                statChip("\(items.count)", "Prüfpunkte gesamt", Color(hex: "555555"))
                statChip("\(acceptedCount)", "Akzeptiert", Color(hex: "22C55E"))
                statChip("\(reservationCount)", "Unter Vorbehalt", Color(hex: "3B82F6"))
                statChip("\(openCount)", "Offen / Abgelehnt", Color(hex: "EF4444"))
            }
            .padding(.vertical, 10)

            Rectangle().fill(Color(hex: "1C3557")).frame(height: 2)

            // Prüfpunkte
            Text("PRÜFPUNKTE")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "888888")).padding(.top, 8)
            ForEach(grouped, id: \.0) { (room, entries) in
                Text(room.uppercased())
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "1C3557"))
                    .padding(.top, 8)
                ForEach(entries) { e in checklistRow(e) }
            }

            // Ergebnis-Checkboxen
            noteField(title: "PROTOKOLLNOTIZEN").padding(.top, 12)
            HStack(spacing: 20) {
                checkboxLabel("Keine Mängel festgestellt")
                checkboxLabel("Mängel festgestellt (siehe Mängelprotokoll)")
                checkboxLabel("Abnahme unter Vorbehalt")
            }
            .padding(.top, 8)

            Spacer(minLength: 12)
            Rectangle().fill(Color(hex: "1C3557")).frame(height: 1)
            PDFSignatureSection()
        }
        .padding(36).frame(width: 794).background(Color.white)
    }

    private func checklistRow(_ e: HandoverItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text(e.isDone ? "✓" : "○")
                    .font(.system(size: 11))
                    .foregroundStyle(e.isDone ? Color(hex: "22C55E") : Color(hex: "BBBBBB"))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(e.item).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        statusBadgeHO(e.status)
                    }
                    let sub = [e.tradeType, e.notes].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty {
                        Text(sub).font(.system(size: 9)).foregroundStyle(Color(hex: "888888"))
                    }
                }
            }
            .padding(.vertical, 4)
            Rectangle().fill(Color(hex: "EEEEEE")).frame(height: 0.5)
        }
    }

    private func statusBadgeHO(_ s: HandoverStatus) -> some View {
        let (color, label): (Color, String) = {
            switch s {
            case .akzeptiert: (Color(hex: "22C55E"), "Akzeptiert")
            case .vorbehalt:  (Color(hex: "3B82F6"), "Unter Vorbehalt")
            case .abgelehnt:  (Color(hex: "EF4444"), "Abgelehnt")
            case .offen:      (Color(hex: "F59E0B"), "Offen")
            }
        }()
        return Text(label)
            .font(.system(size: 9)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func participantField(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: "555555"))
            Spacer().frame(height: 18)
            Rectangle().fill(Color(hex: "CCCCCC")).frame(height: 0.5)
            Text("Name / Firma").font(.system(size: 8)).foregroundStyle(Color(hex: "BBBBBB"))
        }
        .frame(maxWidth: .infinity)
    }

    private func fillLine(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: "555555"))
            Spacer().frame(height: 14)
            Rectangle().fill(Color(hex: "CCCCCC")).frame(height: 0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func statChip(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(Color(hex: "555555"))
        }
    }
}

// MARK: - Shared helpers (fileprivate)

private func infoCellPDF(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.system(size: 9)).foregroundStyle(Color(hex: "888888"))
        Text(value).font(.system(size: 11, weight: .semibold)).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
}

private func noteField(title: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "888888"))
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: "F9F9F9"))
            .frame(height: 52)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "DDDDDD"), lineWidth: 0.5))
    }
}

private func checkboxLabel(_ label: String) -> some View {
    HStack(spacing: 5) {
        RoundedRectangle(cornerRadius: 2).stroke(Color(hex: "AAAAAA"), lineWidth: 1).frame(width: 12, height: 12)
        Text(label).font(.system(size: 9)).foregroundStyle(Color(hex: "555555"))
    }
}

/// PDF-Layout für den §35a-Steuerexport (Handwerkerleistungen).
struct TaxPDFPage: View {
    let laborCosts: [CostItem]
    let materialCosts: [CostItem]
    let projectName: String
    let exportDate: Date

    private var laborSum: Decimal { laborCosts.reduce(0) { $0 + $1.taxRelevantAmount } }
    private var materialSum: Decimal { materialCosts.reduce(0) { $0 + $1.planned } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PDFHeader(title: "§35a EStG – Handwerkerleistungen", projectName: projectName, exportDate: exportDate)
            Divider()

            Text("Arbeitskosten (steuerlich absetzbar)").font(.system(size: 14, weight: .bold))
            ForEach(laborCosts) { cost in
                HStack {
                    Text(cost.title).font(.system(size: 12))
                    Spacer()
                    Text(cost.taxRelevantAmount.euroString).font(.system(size: 12))
                }
            }
            HStack {
                Text("Summe Arbeitskosten").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(laborSum.euroString).font(.system(size: 13, weight: .semibold))
            }
            Divider()

            Text("Materialkosten (nicht §35a-relevant)").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: "555555"))
            HStack {
                Text("Summe Materialkosten").font(.system(size: 12))
                Spacer()
                Text(materialSum.euroString).font(.system(size: 12))
            }

            Text("Hinweis: Keine Steuerberatung. Nach §35a EStG sind i. d. R. Arbeits-, Fahrt- und Maschinenkosten (nicht Material) begünstigt. Bitte mit dem Steuerberater abstimmen.")
                .font(.system(size: 10)).foregroundStyle(Color(hex: "888888"))
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(width: 794)
        .background(Color.white)
    }
}

/// PDF-Layout des Bauberichts.
struct BauberichtPDFPage: View {
    let model: BaumioAppViewModel
    let project: Project
    let exportDate: Date

    private var totalPlanned: Decimal { model.costs.reduce(0) { $0 + $1.planned } }
    private var totalOrdered: Decimal { model.costs.reduce(0) { $0 + $1.ordered } }
    private var totalPaid: Decimal { model.costs.reduce(0) { $0 + $1.paid } }
    private var openDefects: [DefectItem] { model.defects.filter { $0.status.lowercased() != "behoben" } }
    private var openTasks: [TaskItem] { model.tasks.filter { !$0.isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PDFHeader(title: "Baubericht", projectName: project.name, exportDate: exportDate)
            if !project.address.isEmpty {
                Text("Adresse: \(project.address)").font(.system(size: 12)).foregroundStyle(Color(hex: "555555"))
            }
            Divider()

            Group {
                Text("Projektübersicht").font(.system(size: 14, weight: .bold))
                row("Status", project.status.rawValue)
                row("Budget", project.budget.euroString)
                row("Gesamtfortschritt", "\(model.overallProgress) %")
                row("Aufgaben", "\(model.progressTasks) %")
                row("Kosten", "\(model.progressCosts) %")
                if !model.totalTrackedTimeText.isEmpty {
                    row("Zeiterfassung", model.totalTrackedTimeText)
                }
            }
            Divider()

            Group {
                Text("Kostenübersicht").font(.system(size: 14, weight: .bold))
                row("Geplant", totalPlanned.euroString)
                row("Beauftragt", totalOrdered.euroString)
                row("Bezahlt", totalPaid.euroString)
            }

            if !openDefects.isEmpty {
                Divider()
                Text("Offene Mängel (\(openDefects.count))").font(.system(size: 14, weight: .bold))
                ForEach(openDefects.prefix(10)) { d in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.description).font(.system(size: 11, weight: .medium))
                            Text("\(d.trade.isEmpty ? "" : "\(d.trade) · ")\(d.status)").font(.system(size: 10)).foregroundStyle(Color(hex: "666666"))
                        }
                    }
                }
            }

            if !openTasks.isEmpty {
                Divider()
                Text("Offene Aufgaben (\(openTasks.count))").font(.system(size: 14, weight: .bold))
                ForEach(openTasks.prefix(10)) { t in
                    HStack(spacing: 6) {
                        Text("•").font(.system(size: 12))
                        Text(t.title).font(.system(size: 11))
                        Spacer()
                        Text(t.dueDate.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(Color(hex: "666666"))
                    }
                }
            }

            if !model.diary.isEmpty {
                Divider()
                Text("Bautagebuch (letzte Einträge)").font(.system(size: 14, weight: .bold))
                ForEach(model.diary.prefix(5)) { e in
                    HStack(alignment: .top, spacing: 6) {
                        Text(e.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(Color(hex: "666666")).frame(width: 70, alignment: .leading)
                        Text(e.notes).font(.system(size: 11)).lineLimit(2)
                    }
                }
            }

            Spacer(minLength: 0)
            Divider()
            Text("Erstellt mit Baumio · baumio.eu").font(.system(size: 9)).foregroundStyle(Color(hex: "999999"))
        }
        .padding(32)
        .frame(width: 794)
        .background(Color.white)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(Color(hex: "555555"))
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium))
        }
    }
}

enum BauberichtPDFExporter {
    @MainActor
    static func export(model: BaumioAppViewModel, project: Project) -> URL? {
        let dateStr = Date().formatted(date: .long, time: .omitted)
        let safeName = project.name.replacingOccurrences(of: " ", with: "_")
        let safeDateStr = dateStr.replacingOccurrences(of: ".", with: "-")
        let fileName = "Baubericht_\(safeName)_\(safeDateStr).pdf"
        return PDFExporter.export(BauberichtPDFPage(model: model, project: project, exportDate: Date()), fileName: fileName)
    }
}

/// Teilen-Dialog (UIActivityViewController) für die exportierte PDF.
/// Auf iPad und Mac Catalyst muss der Popover einen Source-View haben, sonst Crash.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        guard let popover = controller.popoverPresentationController else { return }
        popover.permittedArrowDirections = []
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?.windows.first
        popover.sourceView = window
        popover.sourceRect = CGRect(
            x: (window?.bounds.midX ?? 0),
            y: (window?.bounds.midY ?? 0),
            width: 1, height: 1
        )
    }
}

struct ShareableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// Kamera-Aufnahme via UIImagePickerController. Gibt ein komprimiertes JPEG als Data zurück.
struct CameraCapturePicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapturePicker
        init(_ parent: CameraCapturePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.85) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
