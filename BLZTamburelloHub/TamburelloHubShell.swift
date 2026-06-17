import SwiftUI

struct TamburelloHubShell: View {
    @EnvironmentObject private var store: TamburelloClubLedger
    @State private var selectedTab: HubTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(selectedTab: $selectedTab)
                .tag(HubTab.today)
                .tabItem { Label("Today", systemImage: "sun.max.fill") }

            MatchScorerView()
                .tag(HubTab.scorer)
                .tabItem { Label("Score", systemImage: "plus.forwardslash.minus") }

            TrainingDrillsView()
                .tag(HubTab.drills)
                .tabItem { Label("Drills", systemImage: "figure.tennis") }

            ClubRankingsView()
                .tag(HubTab.rankings)
                .tabItem { Label("Club", systemImage: "list.number") }

            HubLibraryView()
                .tag(HubTab.library)
                .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
        }
        .tint(.brandRed)
        .preferredColorScheme(.light)
    }
}

enum HubTab: Hashable {
    case today
    case scorer
    case drills
    case rankings
    case library
}

// MARK: - Data Store

final class TamburelloClubLedger: ObservableObject {
    @Published var matches: [MatchRecord] = [] { didSet { save() } }
    @Published var rankings: [ClubRank] = [] { didSet { save() } }
    @Published var teamProfiles: [TeamProfile] = [] { didSet { save() } }
    @Published var drillResults: [DrillResult] = [] { didSet { save() } }
    @Published var tournaments: [TournamentRecord] = [] { didSet { save() } }

    let courts = SeedData.courts
    private let key = "BLZTamburelloHub.LocalState.v2"

    init() {
        load()
    }

    func recordMatch(teamA: String, teamB: String, scoreA: Int, scoreB: Int, mode: MatchMode, history: [PointEvent]) {
        let winner = scoreA >= scoreB ? teamA : teamB
        let loser = scoreA >= scoreB ? teamB : teamA
        let record = MatchRecord(teamA: teamA, teamB: teamB, scoreA: scoreA, scoreB: scoreB, mode: mode, date: .now, pointHistory: history)
        matches.insert(record, at: 0)
        applyElo(winner: winner, loser: loser)
        TamburelloTelemetry.log("match_saved", parameters: [
            "mode": mode.rawValue,
            "points": history.count,
            "winner_score": max(scoreA, scoreB),
            "loser_score": min(scoreA, scoreB)
        ])
    }

    func addDrillResult(drill: DrillKind, made: Int, attempts: Int) {
        drillResults.insert(DrillResult(drill: drill, made: made, attempts: attempts, date: .now), at: 0)
        TamburelloTelemetry.log("drill_saved", parameters: [
            "drill": drill.rawValue,
            "made": made,
            "attempts": attempts
        ])
    }

    func saveTournament(_ tournament: TournamentRecord) {
        tournaments.insert(tournament, at: 0)
        TamburelloTelemetry.log("tournament_saved", parameters: [
            "size": tournament.size,
            "matches": tournament.matches.count
        ])
    }

    private func applyElo(winner: String, loser: String) {
        ensureRank(named: winner)
        ensureRank(named: loser)

        guard let winnerIndex = rankings.firstIndex(where: { $0.name == winner }),
              let loserIndex = rankings.firstIndex(where: { $0.name == loser }) else { return }

        let winnerRating = Double(rankings[winnerIndex].rating)
        let loserRating = Double(rankings[loserIndex].rating)
        let expectedWinner = 1.0 / (1.0 + pow(10.0, (loserRating - winnerRating) / 400.0))
        let delta = Int((32.0 * (1.0 - expectedWinner)).rounded())

        rankings[winnerIndex].rating += delta
        rankings[winnerIndex].lastChange = delta
        rankings[winnerIndex].wins += 1
        rankings[loserIndex].rating -= delta
        rankings[loserIndex].lastChange = -delta
        rankings[loserIndex].losses += 1
        rankings.sort { $0.rating > $1.rating }
    }

    private func ensureRank(named name: String) {
        guard rankings.contains(where: { $0.name == name }) == false else { return }
        rankings.append(ClubRank(name: name, rating: 1000, lastChange: 0, wins: 0, losses: 0))
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(HubState.self, from: data) else {
            matches = SeedData.matches
            rankings = SeedData.rankings
            teamProfiles = SeedData.teamProfiles
            drillResults = SeedData.drills
            tournaments = []
            return
        }
        matches = state.matches
        rankings = state.rankings
        teamProfiles = state.teamProfiles
        drillResults = state.drillResults
        tournaments = state.tournaments
    }

    private func save() {
        let state = HubState(matches: matches, rankings: rankings, teamProfiles: teamProfiles, drillResults: drillResults, tournaments: tournaments)
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct HubState: Codable {
    var matches: [MatchRecord]
    var rankings: [ClubRank]
    var teamProfiles: [TeamProfile]
    var drillResults: [DrillResult]
    var tournaments: [TournamentRecord]
}

enum MatchMode: String, Codable, CaseIterable, Identifiable {
    case singles = "Singles"
    case doubles = "Doubles"

    var id: String { rawValue }
}

struct MatchRecord: Identifiable, Codable {
    var id = UUID()
    var teamA: String
    var teamB: String
    var scoreA: Int
    var scoreB: Int
    var mode: MatchMode
    var date: Date
    var pointHistory: [PointEvent]
}

struct PointEvent: Identifiable, Codable {
    var id = UUID()
    var team: String
    var scoreLine: String
    var date: Date
}

struct ClubRank: Identifiable, Codable {
    var id = UUID()
    var name: String
    var rating: Int
    var lastChange: Int
    var wins: Int
    var losses: Int
}

struct TeamProfile: Identifiable, Codable {
    var id = UUID()
    var name: String
    var city: String
    var country: String
    var founded: String
    var homeCourt: String
    var coach: String
    var captain: String
    var roster: [String]
    var style: String
    var strengths: [String]
    var seasonGoal: String
    var notes: String
}

enum DrillKind: String, Codable, CaseIterable, Identifiable {
    case servePrecision = "Serve Precision"
    case returnChallenge = "Return Challenge"
    case wallPractice = "Wall Practice"

    var id: String { rawValue }
}

struct DrillResult: Identifiable, Codable {
    var id = UUID()
    var drill: DrillKind
    var made: Int
    var attempts: Int
    var date: Date

    var percentage: Int {
        guard attempts > 0 else { return 0 }
        return Int((Double(made) / Double(attempts) * 100.0).rounded())
    }
}

struct TournamentRecord: Identifiable, Codable {
    var id = UUID()
    var name: String
    var size: Int
    var teams: [String]
    var matches: [BracketMatch]
    var createdAt: Date
}

struct BracketMatch: Identifiable, Codable {
    var id = UUID()
    var round: Int
    var slot: Int
    var teamA: String
    var teamB: String
    var scoreA: String = ""
    var scoreB: String = ""
}

struct CourtLocation: Identifiable, Codable {
    var id = UUID()
    var name: String
    var city: String
    var country: String
    var surface: String
}

struct RuleSection: Identifiable {
    var id = UUID()
    var title: String
    var summary: String
    var bullets: [String]
    var symbol: RuleSymbol
}

enum RuleSymbol {
    case court
    case score
    case equipment
    case foul
    case format
}

// MARK: - Today

struct TodayView: View {
    @EnvironmentObject private var store: TamburelloClubLedger
    @Binding var selectedTab: HubTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    BrandHeader(subtitle: "Digital center for tamburello players, coaches, and clubs.")

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("Training Focus")
                        VStack(spacing: 12) {
                            FocusRow(title: "Serve Accuracy", detail: "25 serves, three target zones", icon: "target")
                            FocusRow(title: "Defensive Returns", detail: "Read the bounce, reset the rally", icon: "arrow.uturn.backward.circle")
                            FocusRow(title: "Court Positioning", detail: "Shift as a unit after every strike", icon: "rectangle.split.3x1")
                        }
                        Button {
                            selectedTab = .drills
                        } label: {
                            Label("Start Session", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .hubCard()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionLabel("Match Board")
                            Spacer()
                            Text("\(store.matches.count) local")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(store.matches.prefix(3)) { match in
                            MatchBoardRow(match: match)
                        }
                    }
                    .hubCard()

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("Quick Tools")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            QuickToolButton(title: "Score Match", icon: "plus.forwardslash.minus") { selectedTab = .scorer }
                            QuickToolButton(title: "Drill Timer", icon: "timer") { selectedTab = .drills }
                            QuickToolNavigation(title: "Tournament", icon: "trophy.fill", destination: TournamentBuilderView())
                            QuickToolNavigation(title: "Rules", icon: "book.closed.fill", destination: RulesAcademyView())
                        }
                    }
                    .hubCard()
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle("Today")
        }
    }
}

struct BrandHeader: View {
    var subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            AppBallLogo(size: 78)
            VStack(alignment: .leading, spacing: 4) {
                Text("BLZ")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct AppBallLogo: View {
    var size: CGFloat

    var body: some View {
        Image("BLZLogo")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        .frame(width: size, height: size)
        .accessibilityLabel("BLZ Tamburello Hub logo")
    }
}

struct FocusRow: View {
    var title: String
    var detail: String
    var icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.brandRed)
                .frame(width: 36, height: 36)
                .background(Color.brandRed.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct MatchBoardRow: View {
    var match: MatchRecord

    var body: some View {
        VStack(spacing: 8) {
            ScoreLine(name: match.teamA, score: match.scoreA, isWinner: match.scoreA >= match.scoreB)
            ScoreLine(name: match.teamB, score: match.scoreB, isWinner: match.scoreB > match.scoreA)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
    }
}

struct ScoreLine: View {
    var name: String
    var score: Int
    var isWinner: Bool

    var body: some View {
        HStack {
            Text(name)
                .font(.headline)
            Spacer()
            Text("\(score)")
                .font(.title3.weight(.black))
                .foregroundStyle(isWinner ? Color.brandRed : Color.ink)
        }
    }
}

struct QuickToolButton: View {
    var title: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickToolLabel(title: title, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

struct QuickToolNavigation<Destination: View>: View {
    var title: String
    var icon: String
    var destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            QuickToolLabel(title: title, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

struct QuickToolLabel: View {
    var title: String
    var icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.brandRed)
                .frame(width: 42, height: 42)
                .background(Color.brandRed.opacity(0.1), in: Circle())
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.06)))
    }
}

// MARK: - Match Scorer

struct MatchScorerView: View {
    @EnvironmentObject private var store: TamburelloClubLedger
    @State private var mode: MatchMode = .doubles
    @State private var teamA = "Team A"
    @State private var teamB = "Team B"
    @State private var scoreA = 0
    @State private var scoreB = 0
    @State private var setNumber = 1
    @State private var history: [PointEvent] = []
    @State private var savedBanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Mode", selection: $mode) {
                        ForEach(MatchMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 14) {
                        HStack(spacing: 12) {
                            TextField("Team A", text: $teamA)
                                .textFieldStyle(.roundedBorder)
                            TextField("Team B", text: $teamB)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("Set \(setNumber)")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 14) {
                            ScorerPanel(team: teamA, score: scoreA) { addPoint(toA: true) }
                            ScorerPanel(team: teamB, score: scoreB) { addPoint(toA: false) }
                        }

                        HStack(spacing: 12) {
                            Button("Undo") { undoPoint() }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(history.isEmpty)
                            Button("Save Match") { saveMatch() }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(scoreA == 0 && scoreB == 0)
                        }
                    }
                    .hubCard()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionLabel("Point History")
                            Spacer()
                            Text("\(history.count) points")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if history.isEmpty {
                            EmptyState(title: "No points yet", systemImage: "clock.arrow.circlepath", detail: "Tap +1 on either side to build a local match log.")
                        } else {
                            ForEach(history.reversed()) { event in
                                HStack {
                                    Text(event.team)
                                        .font(.headline)
                                    Spacer()
                                    Text(event.scoreLine)
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(Color.brandRed)
                                }
                                .padding(12)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .hubCard()
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle("Match Scorer")
            .overlay(alignment: .top) {
                if savedBanner {
                    Text("Match saved locally")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.ink, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func addPoint(toA: Bool) {
        if toA { scoreA += 1 } else { scoreB += 1 }
        let team = toA ? teamA : teamB
        history.append(PointEvent(team: team, scoreLine: "\(scoreA)-\(scoreB)", date: .now))
        if hasSetWinner {
            setNumber += 1
        }
    }

    private func undoPoint() {
        guard let last = history.popLast() else { return }
        if last.team == teamA {
            scoreA = max(0, scoreA - 1)
        } else {
            scoreB = max(0, scoreB - 1)
        }
    }

    private var hasSetWinner: Bool {
        max(scoreA, scoreB) >= 13 && abs(scoreA - scoreB) >= 2
    }

    private func saveMatch() {
        store.recordMatch(teamA: teamA, teamB: teamB, scoreA: scoreA, scoreB: scoreB, mode: mode, history: history)
        scoreA = 0
        scoreB = 0
        setNumber = 1
        history = []
        withAnimation { savedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { savedBanner = false }
        }
    }
}

struct ScorerPanel: View {
    var team: String
    var score: Int
    var action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(team)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("\(score)")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(Color.ink)
            Button("+1", action: action)
                .font(.title2.weight(.black))
                .frame(maxWidth: .infinity)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.black.opacity(0.06)))
    }
}

// MARK: - Drills

struct TrainingDrillsView: View {
    @EnvironmentObject private var store: TamburelloClubLedger
    @State private var selectedDrill: DrillKind = .servePrecision
    @State private var leftHits = 0
    @State private var centerHits = 0
    @State private var rightHits = 0
    @State private var misses = 0
    @State private var returnSuccess = 0
    @State private var returnErrors = 0
    @State private var returnStreak = 0
    @State private var bestReturnStreak = 0
    @State private var wallHits = 0
    @State private var wallSeconds = 0
    @State private var timerRunning = false
    private let wallTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Drill", selection: $selectedDrill) {
                        ForEach(DrillKind.allCases) { drill in
                            Text(drill.rawValue).tag(drill)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(selectedDrill.rawValue)
                        CourtDiagram(showTargets: selectedDrill == .servePrecision)
                            .frame(height: 260)

                        InteractiveDrillPanel(
                            selectedDrill: selectedDrill,
                            leftHits: $leftHits,
                            centerHits: $centerHits,
                            rightHits: $rightHits,
                            misses: $misses,
                            returnSuccess: $returnSuccess,
                            returnErrors: $returnErrors,
                            returnStreak: $returnStreak,
                            bestReturnStreak: $bestReturnStreak,
                            wallHits: $wallHits,
                            wallSeconds: $wallSeconds,
                            timerRunning: $timerRunning
                        )

                        HStack(spacing: 14) {
                            StatBubble(title: "Result", value: "\(currentMade)/\(currentAttempts)")
                            StatBubble(title: "Accuracy", value: "\(accuracy)%")
                        }

                        Button {
                            store.addDrillResult(drill: selectedDrill, made: currentMade, attempts: max(1, currentAttempts))
                            resetCurrentDrill()
                        } label: {
                            Label("Save Training", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .hubCard()

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("Drill Library")
                        DrillCard(title: "Serve Precision", detail: "Hit left, right, and center service targets. Track 18/25, 72%, or any custom score.", icon: "target")
                        DrillCard(title: "Return Challenge", detail: "Run a reception series and score clean returns against difficult bounce angles.", icon: "arrow.triangle.2.circlepath")
                        DrillCard(title: "Wall Practice", detail: "Use a wall counter to build rhythm, compact swing shape, and recovery footwork.", icon: "rectangle.portrait.and.arrow.right")
                    }
                    .hubCard()

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("Recent Results")
                        if store.drillResults.isEmpty {
                            EmptyState(title: "No training saved", systemImage: "figure.run", detail: "Save a drill to build your local practice history.")
                        } else {
                            ForEach(store.drillResults.prefix(6)) { result in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(result.drill.rawValue)
                                            .font(.headline)
                                        Text(result.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(result.percentage)%")
                                        .font(.title3.weight(.black))
                                        .foregroundStyle(Color.brandRed)
                                }
                                .padding(14)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .hubCard()
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle("Training Drills")
            .onReceive(wallTimer) { _ in
                if timerRunning && selectedDrill == .wallPractice {
                    wallSeconds += 1
                }
            }
        }
    }

    private var currentMade: Int {
        switch selectedDrill {
        case .servePrecision:
            leftHits + centerHits + rightHits
        case .returnChallenge:
            returnSuccess
        case .wallPractice:
            wallHits
        }
    }

    private var currentAttempts: Int {
        switch selectedDrill {
        case .servePrecision:
            leftHits + centerHits + rightHits + misses
        case .returnChallenge:
            returnSuccess + returnErrors
        case .wallPractice:
            max(1, wallSeconds)
        }
    }

    private var accuracy: Int {
        guard currentAttempts > 0 else { return 0 }
        return Int((Double(currentMade) / Double(currentAttempts) * 100).rounded())
    }

    private func resetCurrentDrill() {
        switch selectedDrill {
        case .servePrecision:
            leftHits = 0
            centerHits = 0
            rightHits = 0
            misses = 0
        case .returnChallenge:
            returnSuccess = 0
            returnErrors = 0
            returnStreak = 0
            bestReturnStreak = 0
        case .wallPractice:
            wallHits = 0
            wallSeconds = 0
            timerRunning = false
        }
    }
}

struct InteractiveDrillPanel: View {
    var selectedDrill: DrillKind
    @Binding var leftHits: Int
    @Binding var centerHits: Int
    @Binding var rightHits: Int
    @Binding var misses: Int
    @Binding var returnSuccess: Int
    @Binding var returnErrors: Int
    @Binding var returnStreak: Int
    @Binding var bestReturnStreak: Int
    @Binding var wallHits: Int
    @Binding var wallSeconds: Int
    @Binding var timerRunning: Bool

    var body: some View {
        switch selectedDrill {
        case .servePrecision:
            VStack(alignment: .leading, spacing: 12) {
                Text("Tap the zone after every serve.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    DrillActionButton(title: "Left", value: leftHits, icon: "arrow.left.circle.fill") { leftHits += 1 }
                    DrillActionButton(title: "Center", value: centerHits, icon: "smallcircle.filled.circle.fill") { centerHits += 1 }
                    DrillActionButton(title: "Right", value: rightHits, icon: "arrow.right.circle.fill") { rightHits += 1 }
                }
                Button {
                    misses += 1
                } label: {
                    Label("Miss", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                Text("Misses: \(misses)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
            }
        case .returnChallenge:
            VStack(alignment: .leading, spacing: 12) {
                Text("Log each return in the series. Streak rewards clean reception under pressure.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button {
                        returnSuccess += 1
                        returnStreak += 1
                        bestReturnStreak = max(bestReturnStreak, returnStreak)
                    } label: {
                        Label("Clean Return", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        returnErrors += 1
                        returnStreak = 0
                    } label: {
                        Label("Error", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                HStack(spacing: 14) {
                    StatBubble(title: "Current Streak", value: "\(returnStreak)")
                    StatBubble(title: "Best Streak", value: "\(bestReturnStreak)")
                }
            }
        case .wallPractice:
            VStack(alignment: .leading, spacing: 12) {
                Text("Start the timer, count every controlled wall strike, and save hits per second as the session result.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    StatBubble(title: "Hits", value: "\(wallHits)")
                    StatBubble(title: "Time", value: timeString)
                }
                HStack(spacing: 12) {
                    Button {
                        timerRunning.toggle()
                    } label: {
                        Label(timerRunning ? "Pause" : "Start", systemImage: timerRunning ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        wallHits += 1
                    } label: {
                        Label("+ Hit", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var timeString: String {
        let minutes = wallSeconds / 60
        let seconds = wallSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct DrillActionButton: View {
    var title: String
    var value: Int
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2.weight(.black))
                Text(title)
                    .font(.caption.weight(.black))
                Text("\(value)")
                    .font(.title2.weight(.black))
            }
            .foregroundStyle(Color.brandRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

struct CourtDiagram: View {
    var showTargets: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.ink, lineWidth: 3)
                Path { path in
                    path.move(to: CGPoint(x: width / 2, y: 0))
                    path.addLine(to: CGPoint(x: width / 2, y: height))
                    path.move(to: CGPoint(x: 0, y: height * 0.36))
                    path.addLine(to: CGPoint(x: width, y: height * 0.36))
                    path.move(to: CGPoint(x: 0, y: height * 0.64))
                    path.addLine(to: CGPoint(x: width, y: height * 0.64))
                }
                .stroke(Color.ink.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))

                if showTargets {
                    TargetZone(label: "Left").position(x: width * 0.24, y: height * 0.22)
                    TargetZone(label: "Center").position(x: width * 0.50, y: height * 0.50)
                    TargetZone(label: "Right").position(x: width * 0.76, y: height * 0.78)
                } else {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(Color.brandRed.opacity(0.18 + Double(index) * 0.1))
                            .frame(width: 34, height: 34)
                            .position(x: width * CGFloat(0.18 + Double(index) * 0.16), y: height * CGFloat(0.25 + Double(index % 2) * 0.4))
                    }
                }
            }
        }
    }
}

struct TargetZone: View {
    var label: String

    var body: some View {
        VStack(spacing: 5) {
            Circle()
                .stroke(Color.brandRed, lineWidth: 4)
                .background(Circle().fill(Color.brandRed.opacity(0.12)))
                .frame(width: 56, height: 56)
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(Color.brandRed)
        }
    }
}

struct DrillCard: View {
    var title: String
    var detail: String
    var icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.brandRed)
                .frame(width: 44, height: 44)
                .background(Color.brandRed.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Tournament

struct TournamentBuilderView: View {
    @EnvironmentObject private var store: TamburelloClubLedger
    @State private var name = "Club Cup"
    @State private var size = 8
    @State private var teams: [String] = (1...16).map { "Team \($0)" }
    @State private var matches: [BracketMatch] = []
    @State private var showingAddTeam = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Tournament Builder")
                    TextField("Tournament name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    Picker("Size", selection: $size) {
                        Text("4 teams").tag(4)
                        Text("8 teams").tag(8)
                        Text("16 teams").tag(16)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Button {
                            fillFromDirectory()
                        } label: {
                            Label("Use Club Teams", systemImage: "person.3.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button {
                            showingAddTeam = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.bold))
                        }
                        .buttonStyle(IconCircleButtonStyle())
                    }

                    if store.teamProfiles.isEmpty == false {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(store.teamProfiles) { profile in
                                    Button {
                                        addTeamToNextSlot(profile.name)
                                    } label: {
                                        Label(profile.name, systemImage: "plus.circle.fill")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(Color.brandRed)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color.white, in: Capsule())
                                            .overlay(Capsule().stroke(Color.black.opacity(0.08)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    ForEach(0..<size, id: \.self) { index in
                        TextField("Team \(index + 1)", text: $teams[index])
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        matches = generateBracket()
                    } label: {
                        Label("Generate Bracket", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .hubCard()

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Bracket")
                    if matches.isEmpty {
                        EmptyState(title: "Ready in seconds", systemImage: "trophy", detail: "Choose 4, 8, or 16 teams and generate a local bracket.")
                    } else {
                        ForEach($matches) { $match in
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Round \(match.round) - Match \(match.slot)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text(match.teamA)
                                        .font(.headline)
                                    Spacer()
                                    TextField("0", text: $match.scoreA)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 54)
                                        .textFieldStyle(.roundedBorder)
                                }
                                HStack {
                                    Text(match.teamB)
                                        .font(.headline)
                                    Spacer()
                                    TextField("0", text: $match.scoreB)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 54)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            .padding(14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        Button {
                            let tournament = TournamentRecord(name: name, size: size, teams: Array(teams.prefix(size)), matches: matches, createdAt: .now)
                            store.saveTournament(tournament)
                        } label: {
                            Label("Save Tournament", systemImage: "checkmark.seal.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .hubCard()
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("Tournament")
        .onAppear {
            if matches.isEmpty { matches = generateBracket() }
        }
        .sheet(isPresented: $showingAddTeam) {
            AddTeamSheet { profile in
                store.teamProfiles.append(profile)
                if store.rankings.contains(where: { $0.name == profile.name }) == false {
                    store.rankings.append(ClubRank(name: profile.name, rating: 1000, lastChange: 0, wins: 0, losses: 0))
                    store.rankings.sort { $0.rating > $1.rating }
                }
                addTeamToNextSlot(profile.name)
                TamburelloTelemetry.log("team_created", parameters: [
                    "source": "tournament",
                    "roster": profile.roster.count
                ])
            }
        }
    }

    private func generateBracket() -> [BracketMatch] {
        let selected = Array(teams.prefix(size))
        var bracket: [BracketMatch] = []
        var slot = 1
        for index in stride(from: 0, to: selected.count, by: 2) {
            bracket.append(BracketMatch(round: 1, slot: slot, teamA: selected[index], teamB: selected[index + 1]))
            slot += 1
        }
        var round = 2
        var remaining = size / 2
        while remaining > 1 {
            for matchIndex in 1...(remaining / 2) {
                bracket.append(BracketMatch(round: round, slot: matchIndex, teamA: "Winner R\(round - 1)-\(matchIndex * 2 - 1)", teamB: "Winner R\(round - 1)-\(matchIndex * 2)"))
            }
            remaining /= 2
            round += 1
        }
        return bracket
    }

    private func fillFromDirectory() {
        for (index, profile) in store.teamProfiles.prefix(size).enumerated() {
            teams[index] = profile.name
        }
        matches = []
    }

    private func addTeamToNextSlot(_ name: String) {
        if let emptyIndex = teams.prefix(size).firstIndex(where: { $0.hasPrefix("Team ") || $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            teams[emptyIndex] = name
        } else if let duplicateIndex = teams.prefix(size).firstIndex(of: name) {
            teams[duplicateIndex] = name
        } else {
            teams[max(0, size - 1)] = name
        }
        matches = []
    }
}

// MARK: - Rankings

struct ClubRankingsView: View {
    @EnvironmentObject private var store: TamburelloClubLedger
    @State private var newName = ""
    @State private var showingAddTeam = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("Club Rankings")
                        Text("Local ELO for clubs, friends, and family championships. No account required.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Quick team name", text: $newName)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                addRank()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.headline.weight(.bold))
                            }
                            .buttonStyle(IconCircleButtonStyle())
                        }
                        Button {
                            showingAddTeam = true
                        } label: {
                            Label("Create Full Team", systemImage: "person.3.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .hubCard()

                    VStack(spacing: 12) {
                        ForEach(Array(store.rankings.enumerated()), id: \.element.id) { index, rank in
                            NavigationLink {
                                TeamProfileView(profile: profile(for: rank.name), rank: rank)
                            } label: {
                                RankingRow(place: index + 1, rank: rank, profile: profile(for: rank.name))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("Team Directory")
                        ForEach(store.teamProfiles) { profile in
                            NavigationLink {
                                TeamProfileView(profile: profile, rank: rank(for: profile.name))
                            } label: {
                                TeamDirectoryRow(profile: profile, rank: rank(for: profile.name))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .hubCard()
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle("Club")
            .sheet(isPresented: $showingAddTeam) {
                AddTeamSheet { profile in
                    addProfile(profile)
                }
            }
        }
    }

    private func addRank() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        store.rankings.append(ClubRank(name: trimmed, rating: 1000, lastChange: 0, wins: 0, losses: 0))
        store.teamProfiles.append(TeamProfile(name: trimmed, city: "Local club", country: "Local", founded: "New", homeCourt: "Training court", coach: "Add coach", captain: "Add captain", roster: ["Player 1", "Player 2", "Player 3", "Player 4"], style: "Balanced club profile", strengths: ["Serve consistency", "Defensive returns"], seasonGoal: "Build a full local match history.", notes: "Editable in code seed data for release builds."))
        store.rankings.sort { $0.rating > $1.rating }
        newName = ""
        TamburelloTelemetry.log("team_created", parameters: [
            "source": "quick_add",
            "roster": 4
        ])
    }

    private func addProfile(_ profile: TeamProfile) {
        guard profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        if store.teamProfiles.contains(where: { $0.name == profile.name }) == false {
            store.teamProfiles.append(profile)
        }
        if store.rankings.contains(where: { $0.name == profile.name }) == false {
            store.rankings.append(ClubRank(name: profile.name, rating: 1000, lastChange: 0, wins: 0, losses: 0))
            store.rankings.sort { $0.rating > $1.rating }
        }
        TamburelloTelemetry.log("team_created", parameters: [
            "source": "club_form",
            "roster": profile.roster.count
        ])
    }

    private func profile(for name: String) -> TeamProfile {
        store.teamProfiles.first(where: { $0.name == name }) ?? TeamProfile(name: name, city: "Local club", country: "Local", founded: "New", homeCourt: "Training court", coach: "Add coach", captain: "Add captain", roster: ["Player 1", "Player 2"], style: "Balanced", strengths: ["Match logging"], seasonGoal: "Create a local team identity.", notes: "This profile was generated from the ranking table.")
    }

    private func rank(for name: String) -> ClubRank? {
        store.rankings.first(where: { $0.name == name })
    }
}

struct RankingRow: View {
    var place: Int
    var rank: ClubRank
    var profile: TeamProfile

    var body: some View {
        HStack(spacing: 14) {
            Text("\(place)")
                .font(.title3.weight(.black))
                .foregroundStyle(Color.brandRed)
                .frame(width: 44, height: 44)
                .background(Color.brandRed.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(rank.name)
                    .font(.headline)
                Text("\(profile.city), \(profile.country)  -  \(rank.wins)W  \(rank.losses)L")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(rank.rating)")
                    .font(.title3.weight(.black))
                Text(changeText)
                    .font(.caption.weight(.black))
                    .foregroundStyle(rank.lastChange >= 0 ? Color.brandRed : .secondary)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.06)))
    }

    private var changeText: String {
        if rank.lastChange > 0 { return "+\(rank.lastChange)" }
        return "\(rank.lastChange)"
    }
}

struct TeamDirectoryRow: View {
    var profile: TeamProfile
    var rank: ClubRank?

    var body: some View {
        HStack(spacing: 14) {
            TeamBadge(name: profile.name, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Text("\(profile.city), \(profile.country)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(profile.style)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandRed)
            }
            Spacer()
            if let rank {
                Text("\(rank.rating)")
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color.ink)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct TeamProfileView: View {
    @EnvironmentObject private var store: TamburelloClubLedger
    var profile: TeamProfile
    var rank: ClubRank?
    @State private var showingAddPlayer = false

    private var currentProfile: TeamProfile {
        store.teamProfiles.first(where: { $0.id == profile.id }) ??
        store.teamProfiles.first(where: { $0.name == profile.name }) ??
        profile
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    TeamBadge(name: currentProfile.name, size: 76)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentProfile.name)
                            .font(.title.weight(.black))
                            .foregroundStyle(Color.ink)
                        Text("\(currentProfile.city), \(currentProfile.country)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .hubCard()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    StatBubble(title: "Rating", value: rank.map { "\($0.rating)" } ?? "1000")
                    StatBubble(title: "Record", value: rank.map { "\($0.wins)-\($0.losses)" } ?? "0-0")
                    StatBubble(title: "Founded", value: currentProfile.founded)
                    StatBubble(title: "Roster", value: "\(currentProfile.roster.count)")
                }
                .hubCard()

                InfoBlock(title: "Club Staff", rows: [("Coach", currentProfile.coach), ("Captain", currentProfile.captain), ("Home Court", currentProfile.homeCourt)])
                InfoBlock(title: "Playing Identity", rows: [("Style", currentProfile.style), ("Season Goal", currentProfile.seasonGoal), ("Notes", currentProfile.notes)])

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel("Roster")
                        Spacer()
                        Button {
                            showingAddPlayer = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.bold))
                        }
                        .buttonStyle(IconCircleButtonStyle())
                    }
                    ForEach(currentProfile.roster, id: \.self) { player in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color.brandRed)
                            Text(player)
                                .font(.headline)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .hubCard()

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Strengths")
                    ForEach(currentProfile.strengths, id: \.self) { strength in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.brandRed)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            Text(strength)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .hubCard()
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle(currentProfile.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddPlayer) {
            AddPlayerSheet(teamName: currentProfile.name) { player in
                addPlayer(player)
            }
        }
    }

    private func addPlayer(_ player: String) {
        let trimmed = player.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard let index = store.teamProfiles.firstIndex(where: { $0.id == currentProfile.id || $0.name == currentProfile.name }) else { return }
        if store.teamProfiles[index].roster.contains(trimmed) == false {
            store.teamProfiles[index].roster.append(trimmed)
            TamburelloTelemetry.log("player_added", parameters: [
                "team": currentProfile.name,
                "roster": store.teamProfiles[index].roster.count
            ])
        }
    }
}

struct AddTeamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var city = ""
    @State private var country = "Italy"
    @State private var founded = "2026"
    @State private var homeCourt = ""
    @State private var coach = ""
    @State private var captain = ""
    @State private var rosterText = ""
    @State private var style = ""
    @State private var strengthsText = ""
    @State private var seasonGoal = ""
    @State private var notes = ""
    var onCreate: (TeamProfile) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    TextField("Team name", text: $name)
                    TextField("City", text: $city)
                    TextField("Country", text: $country)
                    TextField("Founded", text: $founded)
                    TextField("Home court", text: $homeCourt)
                }
                Section("Staff") {
                    TextField("Coach", text: $coach)
                    TextField("Captain", text: $captain)
                }
                Section("Players") {
                    TextField("Players separated by comma", text: $rosterText, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Identity") {
                    TextField("Playing style", text: $style, axis: .vertical)
                        .lineLimit(2...3)
                    TextField("Strengths separated by comma", text: $strengthsText, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Season goal", text: $seasonGoal, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Create Team")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(profile)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var profile: TeamProfile {
        TeamProfile(
            name: clean(name, fallback: "New Team"),
            city: clean(city, fallback: "Local city"),
            country: clean(country, fallback: "Local"),
            founded: clean(founded, fallback: "2026"),
            homeCourt: clean(homeCourt, fallback: "Training court"),
            coach: clean(coach, fallback: "Coach"),
            captain: clean(captain, fallback: "Captain"),
            roster: list(from: rosterText, fallback: ["Player 1", "Player 2"]),
            style: clean(style, fallback: "Balanced club profile"),
            strengths: list(from: strengthsText, fallback: ["Serve consistency", "Court positioning"]),
            seasonGoal: clean(seasonGoal, fallback: "Build a complete local match history."),
            notes: clean(notes, fallback: "Created locally on this device.")
        )
    }

    private func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func list(from value: String, fallback: [String]) -> [String] {
        let items = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false }
        return items.isEmpty ? fallback : items
    }
}

struct AddPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var teamName: String
    @State private var playerName = ""
    var onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(teamName) {
                    TextField("Player name", text: $playerName)
                }
            }
            .navigationTitle("Add Player")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onCreate(playerName)
                        dismiss()
                    }
                    .disabled(playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct TeamBadge: View {
    var name: String
    var size: CGFloat

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.brandRed)
            Circle()
                .stroke(Color.ink, lineWidth: max(2, size * 0.06))
                .padding(size * 0.08)
            Text(initials.isEmpty ? "BLZ" : initials)
                .font(.system(size: size * 0.28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct InfoBlock: View {
    var title: String
    var rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title)
            ForEach(rows, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .hubCard()
    }
}

// MARK: - Library

struct HubLibraryView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BrandHeader(subtitle: "Tools, rules, courts, and statistics for the local tamburello season.")
                    NavigationLink(destination: TournamentBuilderView()) {
                        LibraryRow(title: "Tournament Builder", detail: "4, 8, or 16 teams with generated brackets.", icon: "trophy.fill")
                    }
                    NavigationLink(destination: TeamDirectoryView()) {
                        LibraryRow(title: "Team Directory", detail: "Full local profiles: roster, coach, captain, court, style, strengths.", icon: "person.3.fill")
                    }
                    NavigationLink(destination: RulesAcademyView()) {
                        LibraryRow(title: "Rules Academy", detail: "Court layout, scoring, equipment, fouls, and match formats.", icon: "book.closed.fill")
                    }
                    NavigationLink(destination: CourtMapperView()) {
                        LibraryRow(title: "Court Mapper", detail: "100+ manually curated courts across Italy, France, and Spain.", icon: "map.fill")
                    }
                    NavigationLink(destination: StatisticsView()) {
                        LibraryRow(title: "Statistics", detail: "Matches played, wins, average score, streaks, and monthly activity.", icon: "chart.bar.xaxis")
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle("Library")
        }
    }
}

struct TeamDirectoryView: View {
    @EnvironmentObject private var store: TamburelloClubLedger

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(store.teamProfiles) { profile in
                    NavigationLink {
                        TeamProfileView(profile: profile, rank: store.rankings.first(where: { $0.name == profile.name }))
                    } label: {
                        TeamDirectoryRow(profile: profile, rank: store.rankings.first(where: { $0.name == profile.name }))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("Team Directory")
    }
}

struct LibraryRow: View {
    var title: String
    var detail: String
    var icon: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.brandRed)
                .frame(width: 52, height: 52)
                .background(Color.brandRed.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.black.opacity(0.06)))
    }
}

// MARK: - Rules

struct RulesAcademyView: View {
    private let sections = SeedData.rules

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 14) {
                            RuleIllustration(symbol: section.symbol)
                                .frame(width: 82, height: 82)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(section.title)
                                    .font(.title3.weight(.black))
                                Text(section.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(section.bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color.brandRed)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 7)
                                Text(bullet)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .hubCard()
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("Rules Academy")
    }
}

struct RuleIllustration: View {
    var symbol: RuleSymbol

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.ink, lineWidth: 2)
            switch symbol {
            case .court:
                Rectangle().stroke(Color.brandRed, lineWidth: 3).padding(18)
                Rectangle().fill(Color.brandRed).frame(width: 3).padding(.vertical, 18)
            case .score:
                Text("13")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color.brandRed)
            case .equipment:
                Circle().stroke(Color.brandRed, lineWidth: 5).padding(18)
                Rectangle().fill(Color.ink).frame(width: 34, height: 4).rotationEffect(.degrees(-28)).offset(x: 14, y: 20)
            case .foul:
                Image(systemName: "xmark")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(Color.brandRed)
            case .format:
                VStack(spacing: 6) {
                    HStack(spacing: 6) { Circle().fill(Color.brandRed); Circle().fill(Color.ink) }
                    HStack(spacing: 6) { Circle().fill(Color.ink); Circle().fill(Color.brandRed) }
                }
                .padding(24)
            }
        }
    }
}

// MARK: - Courts

struct CourtMapperView: View {
    @EnvironmentObject private var store: TamburelloClubLedger
    @State private var country = "All"
    @State private var searchText = ""

    private var countries: [String] {
        ["All"] + Array(Set(store.courts.map(\.country))).sorted()
    }

    private var filtered: [CourtLocation] {
        store.courts.filter { court in
            (country == "All" || court.country == country) &&
            (searchText.isEmpty || court.name.localizedCaseInsensitiveContains(searchText) || court.city.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Country", selection: $country) {
                    ForEach(countries, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("\(filtered.count) courts") {
                ForEach(filtered) { court in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(court.name)
                            .font(.headline)
                        Text("\(court.city), \(court.country)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(court.surface)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.brandRed)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search city or court")
        .navigationTitle("Court Mapper")
    }
}

// MARK: - Statistics

struct StatisticsView: View {
    @EnvironmentObject private var store: TamburelloClubLedger

    private var wins: Int {
        store.matches.filter { $0.scoreA > $0.scoreB }.count
    }

    private var averageScore: String {
        guard store.matches.isEmpty == false else { return "0-0" }
        let a = store.matches.map(\.scoreA).reduce(0, +) / store.matches.count
        let b = store.matches.map(\.scoreB).reduce(0, +) / store.matches.count
        return "\(a)-\(b)"
    }

    private var bestStreak: Int {
        var current = 0
        var best = 0
        for match in store.matches {
            if match.scoreA > match.scoreB {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    StatBubble(title: "Matches", value: "\(store.matches.count)")
                    StatBubble(title: "Wins", value: "\(wins)")
                    StatBubble(title: "Average", value: averageScore)
                    StatBubble(title: "Best Streak", value: "\(bestStreak)")
                }
                .hubCard()

                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Monthly Activity")
                    ForEach(monthBuckets, id: \.month) { bucket in
                        HStack {
                            Text(bucket.month)
                                .font(.headline)
                                .frame(width: 54, alignment: .leading)
                            GeometryReader { proxy in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.brandRed)
                                    .frame(width: max(8, proxy.size.width * CGFloat(bucket.count) / CGFloat(maxBucket)))
                            }
                            .frame(height: 14)
                            Text("\(bucket.count)")
                                .font(.caption.weight(.black))
                        }
                    }
                }
                .hubCard()
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("Statistics")
    }

    private var monthBuckets: [(month: String, count: Int)] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let grouped = Dictionary(grouping: store.matches) { match in
            calendar.component(.month, from: match.date)
        }
        return (0..<6).reversed().map { offset in
            let date = calendar.date(byAdding: .month, value: -offset, to: .now) ?? .now
            let month = calendar.component(.month, from: date)
            return (formatter.string(from: date), grouped[month]?.count ?? 0)
        }
    }

    private var maxBucket: Int {
        max(1, monthBuckets.map(\.count).max() ?? 1)
    }
}

// MARK: - Shared UI

struct SectionLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.black))
            .foregroundStyle(Color.brandRed)
            .tracking(0)
    }
}

struct StatBubble: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title.weight(.black))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.black.opacity(0.06)))
    }
}

struct EmptyState: View {
    var title: String
    var systemImage: String
    var detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title.weight(.bold))
                .foregroundStyle(Color.brandRed)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(Color.brandRed.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(Color.ink)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().stroke(Color.ink.opacity(0.18)))
    }
}

struct IconCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.brandRed.opacity(configuration.isPressed ? 0.8 : 1), in: Circle())
    }
}

extension View {
    func hubCard() -> some View {
        padding(18)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.black.opacity(0.05)))
    }
}

extension Color {
    static let brandRed = Color(red: 0.843, green: 0.098, blue: 0.125)
    static let ink = Color(red: 0.071, green: 0.071, blue: 0.071)
    static let appBackground = Color.white
    static let cardBackground = Color(red: 0.975, green: 0.975, blue: 0.975)
}

// MARK: - Seed Data

enum SeedData {
    static let matches = [
        MatchRecord(teamA: "Team A", teamB: "Team B", scoreA: 13, scoreB: 11, mode: .doubles, date: .now.addingTimeInterval(-86_400), pointHistory: []),
        MatchRecord(teamA: "Team C", teamB: "Team D", scoreA: 13, scoreB: 7, mode: .doubles, date: .now.addingTimeInterval(-172_800), pointHistory: []),
        MatchRecord(teamA: "Mantova Reds", teamB: "Verona Black", scoreA: 12, scoreB: 13, mode: .singles, date: .now.addingTimeInterval(-260_000), pointHistory: [])
    ]

    static let rankings = [
        ClubRank(name: "Mantova Reds", rating: 1042, lastChange: 15, wins: 4, losses: 1),
        ClubRank(name: "Verona Black", rating: 1019, lastChange: 12, wins: 3, losses: 2),
        ClubRank(name: "Montpellier Club", rating: 998, lastChange: -12, wins: 2, losses: 2),
        ClubRank(name: "Barcelona Tamb", rating: 976, lastChange: -15, wins: 1, losses: 3)
    ]

    static let teamProfiles = [
        TeamProfile(
            name: "Mantova Reds",
            city: "Mantova",
            country: "Italy",
            founded: "2016",
            homeCourt: "Campo Tamburello Mantova Centro",
            coach: "Luca Bianchi",
            captain: "Marco Rinaldi",
            roster: ["Marco Rinaldi", "Enzo Bellini", "Pietro Sala", "Davide Conti", "Gio Ferri", "Nico Moretti"],
            style: "Aggressive serving with compact defensive rotation",
            strengths: ["High first-serve pressure", "Fast recovery after deep returns", "Strong late-set communication"],
            seasonGoal: "Win the local spring ladder and improve return accuracy above 74%.",
            notes: "Best used as a benchmark team for club-night scoring and ELO testing."
        ),
        TeamProfile(
            name: "Verona Black",
            city: "Verona",
            country: "Italy",
            founded: "2019",
            homeCourt: "Arena Tamburello Verona Est",
            coach: "Stefano Greco",
            captain: "Andrea Costa",
            roster: ["Andrea Costa", "Matteo Ricci", "Filippo Neri", "Samuele Fontana", "Elia Romano"],
            style: "Patient rally building with strong middle-court coverage",
            strengths: ["Low error count", "Reliable center-zone defense", "Calm tie-break decision making"],
            seasonGoal: "Convert more defensive points into attacking chances.",
            notes: "Ideal opponent profile for longer match-history samples."
        ),
        TeamProfile(
            name: "Montpellier Club",
            city: "Montpellier",
            country: "France",
            founded: "2014",
            homeCourt: "Montpellier Tambourin Club",
            coach: "Hugo Martin",
            captain: "Noah Laurent",
            roster: ["Noah Laurent", "Leo Bernard", "Mathis Roux", "Jules Petit", "Theo Girard", "Maxime Faure"],
            style: "Technical return game with target-based serve placement",
            strengths: ["Serve variation", "Wall-practice rhythm", "Disciplined court spacing"],
            seasonGoal: "Raise clean return streaks in training sessions.",
            notes: "Built for coaches who want a balanced European club sample."
        ),
        TeamProfile(
            name: "Barcelona Tamb",
            city: "Barcelona",
            country: "Spain",
            founded: "2021",
            homeCourt: "Barcelona Tamburello Hub",
            coach: "Pau Ferrer",
            captain: "Marc Vidal",
            roster: ["Marc Vidal", "Oriol Serra", "Pol Navarro", "Jan Soler", "Biel Torres"],
            style: "Quick transition play with family-league friendly formats",
            strengths: ["Short-session intensity", "Doubles chemistry", "Tournament adaptability"],
            seasonGoal: "Host an eight-team local bracket and record every match.",
            notes: "Good default profile for casual clubs, friends, and family championships."
        )
    ]

    static let drills = [
        DrillResult(drill: .servePrecision, made: 18, attempts: 25, date: .now.addingTimeInterval(-40_000)),
        DrillResult(drill: .returnChallenge, made: 21, attempts: 30, date: .now.addingTimeInterval(-120_000))
    ]

    static let rules = [
        RuleSection(title: "Court Layout", summary: "Learn the long rectangular field, service lanes, and player spacing.", bullets: ["Mark the central division before every training block.", "Keep defensive coverage staggered instead of flat.", "Use target zones to rehearse serve direction."], symbol: .court),
        RuleSection(title: "Scoring", summary: "Local clubs commonly play sets to 13 with clear match agreements.", bullets: ["Agree singles or doubles before first serve.", "Track each point immediately to avoid disputes.", "Use a two point margin when your club rules require it."], symbol: .score),
        RuleSection(title: "Equipment", summary: "The tamburello is a round striking frame used to drive and control the ball.", bullets: ["Check frame tension before match play.", "Use training balls suited to court surface and level.", "Warm up wrists and shoulders before power hitting."], symbol: .equipment),
        RuleSection(title: "Fouls", summary: "Interactive reminders for double contacts, illegal serves, and court errors.", bullets: ["Call obvious double contacts quickly and calmly.", "Re-serve only when your local rulebook allows it.", "Respect the line judge or agreed captain call."], symbol: .foul),
        RuleSection(title: "Match Formats", summary: "Singles, doubles, and club tournament formats for weekly play.", bullets: ["Use singles for technical repetitions.", "Use doubles for team movement and defensive returns.", "Use brackets for club nights and family championships."], symbol: .format)
    ]

    static let courts: [CourtLocation] = [
        CourtLocation(name: "Campo Tamburello Mantova Centro", city: "Mantova", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Arena Tamburello Verona Est", city: "Verona", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Circolo Tamburello Trento", city: "Trento", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Campo Rovereto Nord", city: "Rovereto", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Centro Sportivo Cavaion", city: "Cavaion Veronese", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Tamburello Bardolino", city: "Bardolino", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Club Tamburello Sommacampagna", city: "Sommacampagna", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Campo Castellaro", city: "Castellaro Lagusello", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Sferisterio Goito", city: "Goito", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Tamburello Solferino", city: "Solferino", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Campo Medole", city: "Medole", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Centro Guidizzolo", city: "Guidizzolo", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Campo Castiglione", city: "Castiglione delle Stiviere", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Tamburello Cavriana", city: "Cavriana", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Campo Monzambano", city: "Monzambano", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Arena Valeggio", city: "Valeggio sul Mincio", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Campo Volta Mantovana", city: "Volta Mantovana", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Tamburello Asola", city: "Asola", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Campo Casalmoro", city: "Casalmoro", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Sferisterio Ceresara", city: "Ceresara", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Tamburello Marcaria", city: "Marcaria", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Campo Curtatone", city: "Curtatone", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Centro Gonzaga", city: "Gonzaga", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Campo Suzzara", city: "Suzzara", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Tamburello Ostiglia", city: "Ostiglia", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Arena Ferrara Tamb", city: "Ferrara", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Centro Modena Tamburello", city: "Modena", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Campo Bologna Reno", city: "Bologna", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Tamburello Parma Sud", city: "Parma", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Campo Reggio Emilia", city: "Reggio Emilia", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Club Brescia Tamburello", city: "Brescia", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Campo Bergamo Ovest", city: "Bergamo", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Milano Tamburello Lab", city: "Milan", country: "Italy", surface: "Indoor sport court"),
        CourtLocation(name: "Campo Pavia Ticino", city: "Pavia", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Tamburello Torino Dora", city: "Turin", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Campo Asti Monferrato", city: "Asti", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Alba Tamburello Club", city: "Alba", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Campo Cuneo Sud", city: "Cuneo", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Genova Tamburello Mare", city: "Genoa", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Campo La Spezia", city: "La Spezia", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Firenze Tamburello Arno", city: "Florence", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Campo Siena Nord", city: "Siena", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Pisa Tamburello Campo", city: "Pisa", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Livorno Club Tamb", city: "Livorno", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Perugia Tamburello", city: "Perugia", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Roma Tamburello Centro", city: "Rome", country: "Italy", surface: "Indoor sport court"),
        CourtLocation(name: "Campo Latina Lido", city: "Latina", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Napoli Tamburello Vesuvio", city: "Naples", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Bari Tamburello Club", city: "Bari", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Lecce Tamburello Sud", city: "Lecce", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Cagliari Tamburello", city: "Cagliari", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Sassari Campo Tamb", city: "Sassari", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Palermo Tamburello", city: "Palermo", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Catania Tamburello Etna", city: "Catania", country: "Italy", surface: "Outdoor clay"),
        CourtLocation(name: "Messina Tamburello", city: "Messina", country: "Italy", surface: "Outdoor synthetic"),
        CourtLocation(name: "Montpellier Tambourin Club", city: "Montpellier", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Nimes Tambourin Arena", city: "Nimes", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Beziers Tambourin", city: "Beziers", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Sete Club Tambourin", city: "Sete", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Agde Terrain Tambourin", city: "Agde", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Pezenas Tambourin", city: "Pezenas", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Gignac Tambourin", city: "Gignac", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Meze Terrain Tamb", city: "Meze", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Poussan Tambourin", city: "Poussan", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Lunel Tambourin Club", city: "Lunel", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Frontignan Tambourin", city: "Frontignan", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Ales Terrain Tambourin", city: "Ales", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Arles Tambourin", city: "Arles", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Avignon Tambourin", city: "Avignon", country: "France", surface: "Indoor sport court"),
        CourtLocation(name: "Marseille Tambourin Prado", city: "Marseille", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Aix Tambourin Club", city: "Aix-en-Provence", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Toulouse Tambourin", city: "Toulouse", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Narbonne Terrain Tamb", city: "Narbonne", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Carcassonne Tambourin", city: "Carcassonne", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Perpignan Tambourin", city: "Perpignan", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Lyon Tambourin Hall", city: "Lyon", country: "France", surface: "Indoor sport court"),
        CourtLocation(name: "Grenoble Tambourin", city: "Grenoble", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Nice Tambourin Club", city: "Nice", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Cannes Terrain Tamb", city: "Cannes", country: "France", surface: "Outdoor synthetic"),
        CourtLocation(name: "Bordeaux Tambourin", city: "Bordeaux", country: "France", surface: "Outdoor clay"),
        CourtLocation(name: "Barcelona Tamburello Hub", city: "Barcelona", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Girona Tamburello Club", city: "Girona", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Tarragona Tamburello", city: "Tarragona", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Lleida Tamburello", city: "Lleida", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Valencia Tamburello Turia", city: "Valencia", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Castellon Tamburello", city: "Castellon", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Alicante Tamburello", city: "Alicante", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Murcia Tamburello Club", city: "Murcia", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Madrid Tamburello Centro", city: "Madrid", country: "Spain", surface: "Indoor sport court"),
        CourtLocation(name: "Alcala Tamburello", city: "Alcala de Henares", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Zaragoza Tamburello", city: "Zaragoza", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Huesca Tamburello", city: "Huesca", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Pamplona Tamburello", city: "Pamplona", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Bilbao Tamburello", city: "Bilbao", country: "Spain", surface: "Indoor sport court"),
        CourtLocation(name: "San Sebastian Tamb", city: "San Sebastian", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Vitoria Tamburello", city: "Vitoria-Gasteiz", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Burgos Tamburello", city: "Burgos", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Valladolid Tamburello", city: "Valladolid", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Salamanca Tamburello", city: "Salamanca", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Sevilla Tamburello", city: "Seville", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Cordoba Tamburello", city: "Cordoba", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Granada Tamburello", city: "Granada", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Malaga Tamburello", city: "Malaga", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "Cadiz Tamburello", city: "Cadiz", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Oviedo Tamburello", city: "Oviedo", country: "Spain", surface: "Indoor sport court"),
        CourtLocation(name: "Gijon Tamburello", city: "Gijon", country: "Spain", surface: "Outdoor synthetic"),
        CourtLocation(name: "A Coruna Tamburello", city: "A Coruna", country: "Spain", surface: "Outdoor clay"),
        CourtLocation(name: "Vigo Tamburello", city: "Vigo", country: "Spain", surface: "Outdoor synthetic")
    ]
}
