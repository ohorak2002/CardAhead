import SwiftUI
import Charts
import CardKit

struct ImpactSharingView: View {
    @Environment(ImpactStore.self) private var impact
    @State private var cloud = ImpactCloudStore.shared
    @State private var email = ""
    @State private var password = ""
    @State private var confirmHistory = false
    @State private var confirmDeletion = false
    var body: some View {
        Form {
            Section("Optional Impact sharing") {
                Text("Local tracking and cloud sharing are separate. Share only recommendation outcomes, day, category, catalog product and reported or estimated dollar amounts. No merchant names, precise locations, card photos, card numbers or bank credentials are uploaded.")
                Text("Your account email is used for authentication. Reports use your account identifier. Only the configured owner can see aggregate reports; outcomes are not independently verified.").font(.footnote)
                if !cloud.configured { Text("Cloud sharing is not configured in this build. Local Impact still works.").foregroundStyle(.secondary) }
                Toggle("Share new Impact reports", isOn: Binding(get: { cloud.state.enabled }, set: { cloud.setSharing($0) }))
                    .disabled(!cloud.configured || !cloud.signedIn)
                Text("Only new reports are shared by default. Turning this off stops future uploads and clears pending uploads. Previously shared records remain until you delete them. An upload already in flight may finish; deletion removes it too.").font(.caption)
            }
            if cloud.configured && !cloud.signedIn {
                Section("Account for sharing") {
                    TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                    Button("Sign in") { Task { await cloud.signIn(email: email, password: password, create: false); password = "" } }.disabled(cloud.isBusy)
                    Button("Create account") { Task { await cloud.signIn(email: email, password: password, create: true); password = "" } }.disabled(cloud.isBusy)
                    Text("Verify your email before signing in. Creating an account does not enable sharing or grant owner access.").font(.caption)
                }
            }
            Section("Delivery & privacy") {
                Text(cloud.status)
                Text("\(cloud.state.pending.count) reports awaiting delivery").font(.caption)
                Button("Retry delivery or deletion") { cloud.flush(force: true) }.disabled(!cloud.signedIn)
                Button("Share earlier recommendation reports…") { confirmHistory = true }.disabled(!cloud.state.enabled)
                Button("Delete previously shared records…", role: .destructive) { confirmDeletion = true }.disabled(!cloud.signedIn)
                if cloud.signedIn { Button("Sign out") { cloud.signOut() } }
            }
            if cloud.isOwner {
                Section { NavigationLink("Owner dashboard") { OwnerDashboardView() } }
            }
        }.navigationTitle("Impact sharing")
            .task { await cloud.refreshOwner(); cloud.flush() }
            .confirmationDialog("Share your earlier local recommendation reports?", isPresented: $confirmHistory, titleVisibility: .visible) {
                Button("Share earlier reports") { cloud.shareHistory(impact.ledger.events) }
            } message: { Text("This uploads eligible older recommendation outcomes and estimates using the same minimal fields. It is separate from sharing new reports.") }
            .confirmationDialog("Delete all previously shared Impact records?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button("Delete shared records", role: .destructive) { cloud.deleteShared() }
            } message: { Text("Sharing turns off immediately. If offline, deletion stays pending until you reconnect while signed in. Local Impact records remain. Your sign-in account remains available.") }
    }
}

struct OwnerDashboardView: View {
    @State private var cloud = ImpactCloudStore.shared
    @State private var from = Date().addingTimeInterval(-30 * 86400)
    @State private var to = Date()
    @State private var report: OwnerDashboard?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            Section("Report dates (UTC)") {
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("Through", selection: $to, displayedComponents: .date)
                Button("Load report") { Task { await load() } }.disabled(loading || from > to)
            }
            if loading { ProgressView("Loading authorized report") }
            if let error { Text(error) }
            if let report {
                Section("Participating users only") {
                    LabeledContent("Currently sharing", value: "\(report.participating_users)")
                    LabeledContent("Users reporting in date range", value: "\(report.reporting_users)")
                    LabeledContent("Recommendations acted on (reported)", value: "\(report.acted_on)")
                    metric("Purchase amounts (reported)", report.purchase_cents)
                    metric("Total rewards (estimated)", report.estimated_cents)
                    metric("Additional rewards (estimated)", report.incremental_cents)
                    metric("Rewards or credits received (reported)", report.received_cents)
                    Text("Known comparison baselines: \(report.known_baselines) of \(report.priced_recommendations) priced recommendations.").font(.caption)
                }
                Section("Daily estimated rewards") {
                    Chart(report.breakdowns.filter { $0.dimension == "day" }) { row in
                        if let cents = row.estimated {
                            BarMark(x: .value("Day", row.label), y: .value("Estimated USD", Double(cents) / 100))
                                .accessibilityLabel(row.label).accessibilityValue(money(cents))
                        }
                    }.frame(height: 200)
                    ForEach(report.breakdowns.filter { $0.dimension == "day" }) { row in
                        VStack(alignment: .leading) {
                            Text(row.label).font(.headline)
                            Text("Estimated: \(money(row.estimated)); additional: \(money(row.incremental)); received: \(money(row.received))").font(.caption)
                        }
                    }
                }
                ForEach(["category", "product"], id: \.self) { dimension in
                    Section("By \(dimension)") {
                        ForEach(report.breakdowns.filter { $0.dimension == dimension }) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.label).font(.headline)
                                Text("\(row.acted) acted on · \(money(row.purchases)) reported purchases")
                                Text("\(money(row.estimated)) estimated rewards · \(money(row.incremental)) additional · \(money(row.received)) reported received").font(.caption)
                            }
                        }
                    }
                }
                Section("What these numbers mean") {
                    Text("Voluntary, incomplete reporting from participating users. Purchase amounts and received rewards are user reports, never independently verified. Rewards are not money saved. Estimated additional rewards compare against the best other eligible wallet card when the recommendation was made; missing baselines remain unknown. Historical estimates retain their original assumptions and point valuations.")
                }
            }
        }.navigationTitle("Owner dashboard")
            .task { await load() }
    }
    private func load() async {
        loading = true; report = nil; error = nil
        defer { loading = false }
        do { report = try await cloud.dashboard(from: from, to: to) }
        catch { self.error = "Access denied or service unavailable. A verified owner account and server configuration are required." }
    }
    private func money(_ cents: Int?) -> String {
        cents.map { CardAheadFormat.money(Decimal($0) / 100) } ?? "Unknown"
    }
    private func metric(_ title: String, _ cents: Int?) -> some View { LabeledContent(title, value: money(cents)) }
}
