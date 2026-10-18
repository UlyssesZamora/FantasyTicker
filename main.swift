// FantasyTicker — live ESPN fantasy football matchup in a floating window + menu bar.
import AppKit
import SwiftUI
import Carbon

// MARK: - JSON helpers

typealias J = [String: Any]
extension Dictionary where Key == String, Value == Any {
    func d(_ k: String) -> J? { self[k] as? J }
    func a(_ k: String) -> [J] { self[k] as? [J] ?? [] }
    func s(_ k: String) -> String? { self[k] as? String }
    func n(_ k: String) -> Double? { (self[k] as? NSNumber)?.doubleValue }
    func i(_ k: String) -> Int? {
        if let v = self[k] as? NSNumber { return v.intValue }
        if let v = self[k] as? String { return Int(v) }
        return nil
    }
}

// MARK: - Config (stored in ~/Library/Application Support/FantasyTicker/config.json, owner-only)

struct Config: Codable, Equatable {
    var leagueIds: [String] = []
    var espnS2 = ""
    var swid = ""
    var season = Config.defaultSeason
    var refreshSeconds = 20

    static var defaultSeason: Int {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return (c.month ?? 9) >= 3 ? (c.year ?? 2026) : (c.year ?? 2026) - 1
    }

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FantasyTicker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return c
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Config.url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.url.path)
    }

    var normalizedSwid: String {
        var s = swid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !s.isEmpty && !s.hasPrefix("{") { s = "{" + s + "}" }
        return s
    }
}

// MARK: - Models

struct LiveGame: Sendable {
    let state: String          // "pre" | "in" | "post"
    let detail: String         // "Q3 4:12", "Sun 4:25 PM", "Final"
    let possession: Int?       // ESPN team id with the ball
    let redZone: Bool
    let downDistance: String?  // "1st & 10 at LAR 28"
    let abbrevs: [Int: String]
    let scores: [Int: String]
}

struct PlayerLine: Identifiable, Sendable {
    let id: Int
    let name: String
    let slot: Int
    let position: Int
    let proTeamId: Int
    let points: Double
    let projected: Double
    var breakdown: [StatLine] = []

    var shortName: String {
        if position == 16 { return name.replacingOccurrences(of: " D/ST", with: " D/ST") }
        let parts = name.split(separator: " ")
        guard parts.count > 1, let f = parts.first?.first else { return name }
        return "\(f). " + parts.dropFirst().joined(separator: " ")
    }
    var slotName: String { slotNames[slot] ?? "" }
}

let slotNames: [Int: String] = [0: "QB", 2: "RB", 3: "RB/WR", 4: "WR", 5: "WR/TE", 6: "TE", 7: "OP",
                                16: "D/ST", 17: "K", 20: "BE", 21: "IR", 23: "FLEX"]
// One scored stat in a player's fantasy total ("Rec Yds  87  8.7").
struct StatLine: Identifiable, Sendable {
    let id: Int
    let label: String
    let value: Double?   // raw stat (yards, catches…); nil for yes/no bonuses
    let points: Double
}

// ESPN stat IDs → labels. Yardage-bonus IDs (every 5/10/25… yds) fold into their base yards stat.
let statLabels: [Int: String] = [
    0: "Pass Att", 1: "Completions", 2: "Incompletions", 3: "Pass Yds", 4: "Pass TD", 15: "40+ Yd Pass TD",
    16: "50+ Yd Pass TD", 17: "300-399 Pass Yd Game", 18: "400+ Pass Yd Game", 19: "Pass 2PT", 20: "INT Thrown",
    22: "Pass Yds", 23: "Rush Att", 24: "Rush Yds", 25: "Rush TD", 26: "Rush 2PT", 35: "40+ Yd Rush TD",
    36: "50+ Yd Rush TD", 37: "100-199 Rush Yd Game", 38: "200+ Rush Yd Game", 40: "Rush Yds", 41: "Receptions",
    42: "Rec Yds", 43: "Rec TD", 44: "Rec 2PT", 45: "40+ Yd Rec TD", 46: "50+ Yd Rec TD", 53: "Receptions",
    56: "100-199 Rec Yd Game", 57: "200+ Rec Yd Game", 58: "Targets", 61: "Rec Yds", 62: "2PT Conv",
    63: "Fumble Rec TD", 64: "Sacked", 68: "Fumbles", 72: "Fumbles Lost", 73: "Turnovers",
    74: "FG 50+", 75: "FG 50+ Att", 76: "FG 50+ Missed", 77: "FG 40-49", 78: "FG 40-49 Att", 79: "FG 40-49 Missed",
    80: "FG 0-39", 81: "FG 0-39 Att", 82: "FG 0-39 Missed", 83: "FG Made", 84: "FG Att", 85: "FG Missed",
    86: "XP Made", 87: "XP Att", 88: "XP Missed", 198: "FG 50-59", 199: "FG 50-59 Att", 200: "FG 50-59 Missed",
    201: "FG 60+", 202: "FG 60+ Att", 203: "FG 60+ Missed",
    89: "0 Pts Allowed", 90: "1-6 Pts Allowed", 91: "7-13 Pts Allowed", 92: "14-17 Pts Allowed",
    93: "Blocked Kick TD", 94: "Def TD", 95: "Interceptions", 96: "Fumble Rec", 97: "Blocked Kicks",
    98: "Safeties", 99: "Sacks", 101: "Kick Return TD", 102: "Punt Return TD", 103: "INT Return TD",
    104: "Fumble Return TD", 105: "Def/ST TD", 106: "Forced Fumbles", 107: "Assisted Tackles", 108: "Solo Tackles",
    109: "Tackles", 113: "Passes Defensed", 114: "Kick Return Yds", 115: "Punt Return Yds", 118: "Punts Returned",
    120: "Pts Allowed", 121: "18-21 Pts Allowed", 122: "22-27 Pts Allowed", 123: "28-34 Pts Allowed",
    124: "35-45 Pts Allowed", 125: "46+ Pts Allowed", 127: "Yds Allowed", 128: "<100 Yds Allowed",
    129: "100-199 Yds Allowed", 130: "200-299 Yds Allowed", 131: "300-349 Yds Allowed", 132: "350-399 Yds Allowed",
    133: "400-449 Yds Allowed", 134: "450-499 Yds Allowed", 135: "500-549 Yds Allowed", 136: "550+ Yds Allowed",
    187: "Pts Allowed", 205: "2PT Return", 206: "2PT Return",
]
func baseStat(_ id: Int) -> Int {
    switch id {
    case 5...14, 22: 3
    case 27...34, 40: 24
    case 47...52, 54, 55, 61: 42
    case 41: 53
    case 100: 99
    case 187: 120
    default: id
    }
}
// Flag-style stats (bucket bonuses) whose raw value is just 1, so it isn't worth showing.
let flagStats = Set([17, 18, 37, 38, 56, 57, 89, 90, 91, 92, 121, 122, 123, 124, 125] + Array(128...136))

func breakdown(applied: J, raw: J) -> [StatLine] {
    var merged: [Int: Double] = [:]
    for (k, v) in applied {
        guard let id = Int(k), let pts = (v as? NSNumber)?.doubleValue, pts != 0 else { continue }
        merged[baseStat(id), default: 0] += pts
    }
    return merged.map { id, pts in
        StatLine(id: id, label: statLabels[id] ?? "Stat \(id)",
                 value: flagStats.contains(id) ? nil : raw.n(String(id)), points: pts)
    }.sorted { abs($0.points) > abs($1.points) }
}

let slotOrder: [Int: Int] = [0: 0, 2: 1, 4: 2, 6: 3, 23: 4, 3: 4, 5: 4, 7: 5, 16: 8, 17: 9]

struct TeamSide: Sendable {
    let teamId: Int
    let name: String
    let abbrev: String
    let score: Double
    let projected: Double?
    let starters: [PlayerLine]
}

struct LeagueMeta: Sendable {
    let name: String
    let myTeamId: Int
    let teams: [Int: (name: String, abbrev: String)]
    let matchupPeriod: Int
    let scoringPeriod: Int
    let fetchedAt: Date
}

struct LeagueState: Identifiable, Sendable {
    let id: String
    var name: String
    var me: TeamSide?
    var opp: TeamSide?
    var error: String?
    var noMatchup = false
}

enum PlayStatus {
    case redZone(String), hasBall(String), defense(String, redZone: Bool), live(String), upcoming(String), final, bye

    var rank: Int {
        switch self { case .redZone: 0; case .hasBall, .defense: 1; case .live: 2; case .upcoming: 3; case .final: 4; case .bye: 5 }
    }
    var icon: String {
        switch self { case .redZone: "🔴"; case .hasBall: "🏈"; case .defense: "🛡️"; case .live: "🟢"; case .upcoming: "⏳"; case .final: "✓"; case .bye: "–" }
    }
    // Play situation for players currently on the field ("1st & 10 at LAR 28").
    var fieldDetail: String? {
        switch self { case .redZone(let d), .hasBall(let d), .defense(let d, _): d; default: nil }
    }
    var isDangerZone: Bool { if case .defense(_, true) = self { true } else { false } }
}

func status(of p: PlayerLine, games: [Int: LiveGame]) -> PlayStatus {
    guard let g = games[p.proTeamId] else { return .bye }
    switch g.state {
    case "in":
        let dd = g.downDistance ?? g.detail
        if p.position == 16 {
            // A D/ST is on the field when the other team has the ball.
            if let poss = g.possession, poss != p.proTeamId { return .defense(dd, redZone: g.redZone) }
            return .live(g.detail)
        }
        if g.possession == p.proTeamId { return g.redZone ? .redZone(dd) : .hasBall(dd) }
        return .live(g.detail)
    case "post": return .final
    default: return .upcoming(g.detail)
    }
}

// MARK: - ESPN client

struct APIError: Error { let message: String }

enum ESPN {
    static let fantasyBase = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons"
    static let scoreboardURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard")!

    static func get(_ url: URL, cfg: Config? = nil, filter: String? = nil) async throws -> J {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (Macintosh) FantasyTicker", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpShouldHandleCookies = false
        if let cfg {
            req.setValue("espn_s2=\(cfg.espnS2.trimmingCharacters(in: .whitespacesAndNewlines)); SWID=\(cfg.normalizedSwid)",
                         forHTTPHeaderField: "Cookie")
        }
        if let filter { req.setValue(filter, forHTTPHeaderField: "x-fantasy-filter") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 401, 403: throw APIError(message: "ESPN rejected your login cookies — re-copy espn_s2 and SWID in Settings.")
        case 404: throw APIError(message: "League not found — check the league ID and season.")
        default: throw APIError(message: "ESPN returned HTTP \(code).")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? J else {
            throw APIError(message: "Unexpected response from ESPN.")
        }
        return obj
    }

    static func scoreboard() async throws -> [Int: LiveGame] {
        let root = try await get(scoreboardURL)
        var games: [Int: LiveGame] = [:]
        for e in root.a("events") {
            guard let c = e.a("competitions").first else { continue }
            let type = e.d("status")?.d("type")
            let sit = c.d("situation")
            var abbrevs: [Int: String] = [:], scores: [Int: String] = [:]
            for comp in c.a("competitors") {
                guard let team = comp.d("team"), let id = team.i("id") else { continue }
                abbrevs[id] = team.s("abbreviation") ?? "?"
                scores[id] = comp.s("score") ?? "0"
            }
            let g = LiveGame(state: type?.s("state") ?? "pre",
                             detail: type?.s("shortDetail") ?? "",
                             possession: sit?.i("possession"),
                             redZone: (sit?["isRedZone"] as? Bool) ?? false,
                             downDistance: sit?.s("downDistanceText"),
                             abbrevs: abbrevs, scores: scores)
            for id in abbrevs.keys { games[id] = g }
        }
        return games
    }

    static func meta(league id: String, cfg: Config) async throws -> LeagueMeta {
        let url = URL(string: "\(fantasyBase)/\(cfg.season)/segments/0/leagues/\(id)?view=mTeam&view=mSettings&view=mStatus")!
        let root = try await get(url, cfg: cfg)
        let swid = cfg.normalizedSwid
        var teams: [Int: (String, String)] = [:]
        var mine: Int?
        for t in root.a("teams") {
            guard let tid = t.i("id") else { continue }
            let name = t.s("name") ?? [t.s("location"), t.s("nickname")].compactMap { $0 }.joined(separator: " ")
            teams[tid] = (name, t.s("abbrev") ?? String(name.prefix(4)).uppercased())
            let owners = (t["owners"] as? [String] ?? []) + [t.s("primaryOwner")].compactMap { $0 }
            if owners.contains(where: { $0.uppercased() == swid }) { mine = mine ?? tid }
        }
        guard let mine else {
            throw APIError(message: "Couldn't find your team in this league — double-check your SWID.")
        }
        let status = root.d("status")
        let sp = root.i("scoringPeriodId") ?? 1
        let final = status?.i("finalScoringPeriod") ?? sp
        return LeagueMeta(name: root.d("settings")?.s("name") ?? "League \(id)",
                          myTeamId: mine, teams: teams.mapValues { (name: $0.0, abbrev: $0.1) },
                          matchupPeriod: status?.i("currentMatchupPeriod") ?? sp,
                          scoringPeriod: min(sp, final), fetchedAt: Date())
    }

    static func matchup(league id: String, meta: LeagueMeta, cfg: Config) async throws -> LeagueState {
        let url = URL(string: "\(fantasyBase)/\(cfg.season)/segments/0/leagues/\(id)?view=mMatchupScore&view=mScoreboard&scoringPeriodId=\(meta.scoringPeriod)")!
        let filter = #"{"schedule":{"filterMatchupPeriodIds":{"value":[\#(meta.matchupPeriod)]}}}"#
        let root = try await get(url, cfg: cfg, filter: filter)
        var state = LeagueState(id: id, name: meta.name)
        let game = root.a("schedule").first {
            ($0.d("home")?.i("teamId") == meta.myTeamId || $0.d("away")?.i("teamId") == meta.myTeamId)
                && ($0.i("matchupPeriodId") ?? meta.matchupPeriod) == meta.matchupPeriod
        }
        guard let game else { state.noMatchup = true; return state }
        let sides = [game.d("home"), game.d("away")].compactMap { $0 }.map { side(from: $0, meta: meta) }
        state.me = sides.first { $0.teamId == meta.myTeamId }
        state.opp = sides.first { $0.teamId != meta.myTeamId }
        return state
    }

    static func side(from s: J, meta: LeagueMeta) -> TeamSide {
        let tid = s.i("teamId") ?? -1
        var starters: [PlayerLine] = []
        for en in s.d("rosterForCurrentScoringPeriod")?.a("entries") ?? [] {
            let slot = en.i("lineupSlotId") ?? 20
            guard slot != 20, slot != 21, let ppe = en.d("playerPoolEntry"), let p = ppe.d("player") else { continue }
            var pts = ppe.n("appliedStatTotal") ?? 0, proj = 0.0, lines: [StatLine] = []
            for st in p.a("stats") where st.i("scoringPeriodId") == meta.scoringPeriod {
                if st.i("statSourceId") == 0 {
                    pts = st.n("appliedTotal") ?? pts
                    lines = breakdown(applied: st.d("appliedStats") ?? [:], raw: st.d("stats") ?? [:])
                }
                if st.i("statSourceId") == 1 { proj = st.n("appliedTotal") ?? proj }
            }
            starters.append(PlayerLine(id: p.i("id") ?? starters.count, name: p.s("fullName") ?? "?", slot: slot,
                                       position: p.i("defaultPositionId") ?? 0, proTeamId: p.i("proTeamId") ?? 0,
                                       points: pts, projected: proj, breakdown: lines))
        }
        starters.sort { (slotOrder[$0.slot] ?? 6) < (slotOrder[$1.slot] ?? 6) }
        let info = meta.teams[tid]
        let live = s.n("totalPointsLive")
        return TeamSide(teamId: tid, name: info?.name ?? "Team \(tid)", abbrev: info?.abbrev ?? "?",
                        score: live ?? s.n("totalPoints") ?? starters.reduce(0) { $0 + $1.points },
                        projected: live != nil ? s.n("totalProjectedPointsLive") : nil,
                        starters: starters)
    }
}

// MARK: - Store

@MainActor final class Store: ObservableObject {
    @Published var config = Config.load()
    @Published var leagues: [LeagueState] = []
    @Published var games: [Int: LiveGame] = [:]
    @Published var lastUpdated: Date?
    @Published var scoreboardError: String?
    @Published var loading = false
    @Published var selectedId: String? = UserDefaults.standard.string(forKey: "selectedLeague") {
        didSet { UserDefaults.standard.set(selectedId, forKey: "selectedLeague") }
    }
    @Published var compact = UserDefaults.standard.bool(forKey: "compact") {
        didSet { UserDefaults.standard.set(compact, forKey: "compact") }
    }

    var onUpdate: (() -> Void)?
    private var metas: [String: LeagueMeta] = [:]
    private var timer: Timer?

    var selected: LeagueState? { leagues.first { $0.id == selectedId } ?? leagues.first }
    // Fake roster spread across real NFL teams, so the UI can be checked against live games without ESPN cookies.
    private func demoLeagues() -> [LeagueState] {
        let ids = Array(Set(games.keys)).sorted()
        func side(_ tid: Int, _ abbrev: String, _ offset: Int) -> TeamSide {
            let slots = [0, 2, 2, 4, 4, 6, 23, 16, 17]
            let ps = slots.enumerated().map { i, slot in
                PlayerLine(id: tid * 100 + i, name: "Demo Player\(i + 1)", slot: slot, position: slot == 23 ? 2 : slot,
                           proTeamId: ids.isEmpty ? 0 : ids[(i * 3 + offset) % ids.count], points: Double((i * 7 + offset) % 19), projected: 12,
                           breakdown: [StatLine(id: 42, label: "Rec Yds", value: 64, points: 6.4),
                                       StatLine(id: 53, label: "Receptions", value: 5, points: 2.5),
                                       StatLine(id: 72, label: "Fumbles Lost", value: 1, points: -2)])
            }
            return TeamSide(teamId: tid, name: abbrev, abbrev: abbrev, score: ps.reduce(0) { $0 + $1.points },
                            projected: 118.4, starters: ps)
        }
        return [LeagueState(id: "1", name: "Demo League", me: side(1, "ULY", 0), opp: side(2, "OPP", 1)),
                LeagueState(id: "2", name: "Work League", me: side(1, "ULY", 2), opp: side(2, "BOSS", 5))]
    }

    var isConfigured: Bool { ProcessInfo.processInfo.environment["FT_DEMO"] != nil || hasCredentials }
    var hasCredentials: Bool { !config.leagueIds.isEmpty && !config.espnS2.isEmpty && !config.swid.isEmpty }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(10, config.refreshSeconds)), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func apply(_ newConfig: Config) {
        let credsChanged = newConfig.espnS2 != config.espnS2 || newConfig.swid != config.swid || newConfig.season != config.season
        config = newConfig
        config.save()
        if credsChanged { metas = [:] }
        leagues = leagues.filter { config.leagueIds.contains($0.id) }
        start()
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        Task { await doRefresh(); loading = false; onUpdate?() }
    }

    private func doRefresh() async {
        let cfg = config
        let cached = metas
        async let sb: [Int: LiveGame]? = try? ESPN.scoreboard()

        var results: [(Int, LeagueState, LeagueMeta?)] = []
        if hasCredentials {
            await withTaskGroup(of: (Int, LeagueState, LeagueMeta?).self) { group in
                for (idx, id) in cfg.leagueIds.enumerated() {
                    let old = cached[id]
                    group.addTask {
                        do {
                            var meta = old
                            if meta == nil || Date().timeIntervalSince(meta!.fetchedAt) > 600 {
                                meta = try await ESPN.meta(league: id, cfg: cfg)
                            }
                            return (idx, try await ESPN.matchup(league: id, meta: meta!, cfg: cfg), meta)
                        } catch {
                            let msg = (error as? APIError)?.message ?? error.localizedDescription
                            return (idx, LeagueState(id: id, name: old?.name ?? "League \(id)", error: msg), old)
                        }
                    }
                }
                for await r in group { results.append(r) }
            }
        }
        for r in results { if let m = r.2 { metas[r.1.id] = m } }
        leagues = results.sorted { $0.0 < $1.0 }.map { $0.1 }

        if let g = await sb { games = g; scoreboardError = nil } else { scoreboardError = "Couldn't reach the NFL scoreboard." }
        if ProcessInfo.processInfo.environment["FT_DEMO"] != nil { leagues = demoLeagues() }
        lastUpdated = Date()
    }

    // Live alerts for a side, red zone first.
    func alerts(_ side: TeamSide?) -> [(PlayerLine, PlayStatus)] {
        (side?.starters ?? []).compactMap { p in
            let s = status(of: p, games: games)
            return s.fieldDetail != nil ? (p, s) : nil
        }.sorted { $0.1.rank < $1.1.rank }
    }

    var menuBarTitle: String {
        guard let l = selected else { return "🏈" }
        guard let me = l.me else { return l.error != nil ? "🏈 ⚠︎" : "🏈" }
        let mine = alerts(me)
        let icon = mine.contains { if case .redZone = $0.1 { true } else { false } } ? "🔴" : (mine.isEmpty ? "🏈" : "🟢")
        return "\(icon) \(fmt(me.score))–\(fmt(l.opp?.score ?? 0))"
    }
}

func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

// MARK: - Views

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct WidgetView: View {
    @ObservedObject var store: Store
    var openSettings: () -> Void
    var hide: () -> Void
    @State private var pulse = false
    @State private var openPlayers: Set<Int> = []

    var body: some View {
        let league = store.selected
        let myRedZone = store.alerts(league?.me).contains { if case .redZone = $0.1 { true } else { false } }

        VStack(alignment: .leading, spacing: 8) {
            header(league)
            if !store.isConfigured {
                Text("Add your league IDs and ESPN cookies to get started.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Open Settings…", action: openSettings)
            } else if let league {
                content(league)
            } else {
                Text("Loading…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 310, alignment: .leading)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(myRedZone ? Color.red : Color.white.opacity(0.12), lineWidth: myRedZone ? 2.5 : 1)
                .opacity(myRedZone ? (pulse ? 1 : 0.35) : 1)
        )
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true } }
    }

    func header(_ league: LeagueState?) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(store.leagues) { l in
                    Button { store.selectedId = l.id; store.onUpdate?() } label: {
                        Text((l.id == league?.id ? "✓ " : "") + l.name)
                    }
                }
                Divider()
                Button("Settings…", action: openSettings)
            } label: {
                Text(league?.name ?? "Fantasy").font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            if store.loading { ProgressView().controlSize(.mini) }
            iconButton(store.compact ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                       help: store.compact ? "Show all players" : "Compact") {
                store.compact.toggle(); store.onUpdate?()
            }
            iconButton("arrow.clockwise", help: "Refresh") { store.refresh() }
            iconButton("xmark", help: "Hide (⌃⌥F)", action: hide)
        }
    }

    func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 10, weight: .semibold)) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(help)
    }

    @ViewBuilder func content(_ league: LeagueState) -> some View {
        if let err = league.error {
            Text(err).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        } else if league.noMatchup {
            Text("No matchup this week (bye).").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if let me = league.me {
            scoreRow(me: me, opp: league.opp)
            let mine = store.alerts(me), theirs = store.alerts(league.opp)
            if store.compact {
                if !mine.isEmpty || !theirs.isEmpty {
                    Divider().opacity(0.4)
                    ForEach(mine, id: \.0.id) { alertRow($0.0, $0.1, mine: true) }
                    ForEach(theirs, id: \.0.id) { alertRow($0.0, $0.1, mine: false) }
                }
            } else {
                Divider().opacity(0.4)
                roster(title: "YOU · \(me.abbrev)", side: me, mine: true)
                if let opp = league.opp {
                    Divider().opacity(0.4)
                    roster(title: "OPP · \(opp.abbrev)", side: opp, mine: false)
                }
            }
            footer
        }
    }

    func scoreRow(me: TeamSide, opp: TeamSide?) -> some View {
        let lead = me.score - (opp?.score ?? 0)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(me.abbrev).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Text(fmt(me.score)).font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(lead > 0 ? .green : lead < 0 ? .red : .primary)
                if let p = me.projected { Text("proj \(fmt(p))").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(lead == 0 ? "tied" : (lead > 0 ? "+" : "") + fmt(lead))
                .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(opp?.abbrev ?? "—").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Text(fmt(opp?.score ?? 0)).font(.system(size: 24, weight: .bold, design: .rounded))
                if let p = opp?.projected { Text("proj \(fmt(p))").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
        }
    }

    func alertRow(_ p: PlayerLine, _ s: PlayStatus, mine: Bool) -> some View {
        let team = store.games[p.proTeamId]?.abbrevs[p.proTeamId] ?? ""
        let detail = s.isDangerZone ? "D on field · ⚠︎ red zone · " + (s.fieldDetail ?? "")
            : (p.position == 16 ? "D on field · " : "") + (s.fieldDetail ?? "")
        return HStack(spacing: 6) {
            Text(s.icon).font(.system(size: 11))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(mine ? "" : "OPP · ")\(p.shortName)")
                    .font(.system(size: 12, weight: mine ? .semibold : .regular))
                    .foregroundStyle(mine ? .primary : .secondary)
                Text("\(team) · \(detail)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(fmt(p.points)).font(.system(size: 12, weight: .medium, design: .rounded))
        }
    }

    func roster(title: String, side: TeamSide, mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            ForEach(side.starters) { p in
                let s = status(of: p, games: store.games)
                let team = store.games[p.proTeamId]?.abbrevs[p.proTeamId] ?? ""
                let open = openPlayers.contains(p.id)
                Button {
                    if open { openPlayers.remove(p.id) } else { openPlayers.insert(p.id) }
                    store.onUpdate?()
                } label: {
                    HStack(spacing: 5) {
                        Text(p.slotName).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .leading)
                        Text(s.icon).font(.system(size: 9)).frame(width: 14)
                        Text(p.shortName).font(.system(size: 11, weight: s.rank <= 1 ? .bold : .regular)).lineLimit(1)
                        Text(team).font(.system(size: 9)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(detailText(s)).font(.system(size: 9)).foregroundStyle(s.rank == 0 ? .red : s.isDangerZone ? .orange : .secondary).lineLimit(1)
                        Text(fmt(p.points)).font(.system(size: 11, weight: .medium, design: .rounded))
                            .frame(width: 34, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show scoring breakdown")
                if open { breakdownView(p) }
            }
        }
    }

    func breakdownView(_ p: PlayerLine) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if p.breakdown.isEmpty {
                Text("No scoring yet").foregroundStyle(.secondary)
            }
            ForEach(p.breakdown) { line in
                HStack(spacing: 4) {
                    Text(line.label).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    if let v = line.value { Text(statValue(v)).foregroundStyle(.secondary) }
                    Text((line.points > 0 ? "+" : "") + fmt(line.points))
                        .foregroundStyle(line.points < 0 ? .red : .primary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .font(.system(size: 9, design: .rounded))
        .padding(.leading, 49).padding(.vertical, 2)
    }

    func statValue(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : fmt(v) }

    func detailText(_ s: PlayStatus) -> String {
        switch s {
        case .redZone(let d), .hasBall(let d), .defense(let d, _): return d.replacingOccurrences(of: " & ", with: "&")
        case .live(let d), .upcoming(let d): return d
        case .final: return "Final"
        case .bye: return "BYE"
        }
    }

    var footer: some View {
        HStack {
            if let e = store.scoreboardError { Text(e).foregroundStyle(.orange) }
            Spacer()
            if let t = store.lastUpdated { Text("Updated \(t.formatted(date: .omitted, time: .standard))") }
        }
        .font(.system(size: 9)).foregroundStyle(.secondary)
    }
}

struct SettingsView: View {
    @State var draft: Config
    var onSave: (Config) -> Void
    @State private var idsText: String

    init(config: Config, onSave: @escaping (Config) -> Void) {
        _draft = State(initialValue: config)
        _idsText = State(initialValue: config.leagueIds.joined(separator: ", "))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                TextField("League IDs", text: $idsText, prompt: Text("e.g. 12345678, 87654321"))
                TextField("SWID", text: $draft.swid, prompt: Text("{XXXXXXXX-XXXX-...}"))
                SecureField("espn_s2", text: $draft.espnS2, prompt: Text("long cookie value"))
                Stepper("Season: \(String(draft.season))", value: $draft.season, in: 2018...2100)
                Stepper("Refresh every \(draft.refreshSeconds)s", value: $draft.refreshSeconds, in: 10...300, step: 5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("How to find these").font(.headline)
                Text("""
                **League ID:** open your league on fantasy.espn.com — it's the number after `leagueId=` in the address bar.
                **Cookies:** while logged in on fantasy.espn.com in Chrome, press ⌥⌘I → **Application** tab → **Cookies** → `https://fantasy.espn.com`. Copy the values of **SWID** and **espn_s2**. (Safari: enable Develop menu, then Web Inspector → **Storage** → Cookies.)
                These stay on this Mac only, in ~/Library/Application Support/FantasyTicker.
                """)
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Save") {
                    draft.leagueIds = idsText.split(whereSeparator: { ", \n".contains($0) })
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .map { $0.filter(\.isNumber) }.filter { !$0.isEmpty }
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

// MARK: - Floating panel

final class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 310, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { true }
}

// MARK: - Global hotkey (⌃⌥F toggles the floating window)

final class HotKey {
    static var handler: (() -> Void)?
    private var ref: EventHotKeyRef?

    init(handler: @escaping () -> Void) {
        HotKey.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.handler?() }
            return noErr
        }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: OSType(0x46544B59), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: - App

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = Store()
    var panel: FloatingPanel!
    var hosting: NSHostingView<WidgetView>!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var hotKey: HotKey?

    var panelVisible: Bool {
        get { UserDefaults.standard.object(forKey: "panelVisible") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "panelVisible") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        panel = FloatingPanel()
        hosting = NSHostingView(rootView: WidgetView(store: store,
                                                    openSettings: { [weak self] in self?.openSettings() },
                                                    hide: { [weak self] in self?.setPanel(visible: false) }))
        panel.contentView = hosting
        fitPanel()
        if !panel.setFrameUsingName("FantasyTickerPanel"), let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: vf.minX + 16, y: vf.maxY - 16))
        }
        panel.setFrameAutosaveName("FantasyTickerPanel")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🏈"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotKey = HotKey { [weak self] in self?.setPanel(visible: !(self?.panel.isVisible ?? false)) }

        store.onUpdate = { [weak self] in self?.updateUI() }
        if panelVisible { panel.orderFrontRegardless() }
        store.start()
        if !store.isConfigured { openSettings() }
    }

    func setPanel(visible: Bool) {
        panelVisible = visible
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    func updateUI() {
        statusItem.button?.title = store.menuBarTitle
        DispatchQueue.main.async {
            self.fitPanel()
            if let path = ProcessInfo.processInfo.environment["FT_SNAPSHOT"] { self.snapshot(to: path) }
        }
    }

    // Debug aid: writes the floating window's contents to a PNG.
    func snapshot(to path: String) {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    // Resize to fit content while keeping the top-left corner where the user put it.
    func fitPanel() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        var f = panel.frame
        let top = f.maxY
        f.size = size
        f.origin.y = top - size.height
        panel.setFrame(f, display: true)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func info(_ s: String) { let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }

        if let l = store.selected {
            info(l.name)
            if let e = l.error { info("⚠︎ " + e) }
            if let me = l.me {
                info("\(me.abbrev) \(fmt(me.score))  –  \(fmt(l.opp?.score ?? 0)) \(l.opp?.abbrev ?? "")")
                for (p, s) in store.alerts(me) { info("\(s.icon) \(p.shortName) — \(detail(s))") }
                for (p, s) in store.alerts(l.opp) { info("\(s.icon) OPP \(p.shortName) — \(detail(s))") }
            }
            menu.addItem(.separator())
        }
        if store.leagues.count > 1 {
            for l in store.leagues {
                let item = NSMenuItem(title: l.name, action: #selector(selectLeague(_:)), keyEquivalent: "")
                item.representedObject = l.id
                item.state = l.id == store.selected?.id ? .on : .off
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        add(menu, panel.isVisible ? "Hide Floating Window" : "Show Floating Window", #selector(togglePanel), "f",
            mods: [.control, .option])
        let c = add(menu, "Compact Mode", #selector(toggleCompact), "")
        c.state = store.compact ? .on : .off
        add(menu, "Refresh Now", #selector(refreshNow), "r")
        add(menu, "Settings…", #selector(openSettings), ",")
        menu.addItem(.separator())
        add(menu, "Quit FantasyTicker", #selector(quit), "q")
    }

    private func detail(_ s: PlayStatus) -> String {
        (s.isDangerZone ? "D on field, opp in red zone · " : "") + (s.fieldDetail ?? "")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector, _ key: String,
                     mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc func selectLeague(_ sender: NSMenuItem) { store.selectedId = sender.representedObject as? String; updateUI() }
    @objc func togglePanel() { setPanel(visible: !panel.isVisible) }
    @objc func toggleCompact() { store.compact.toggle(); updateUI() }
    @objc func refreshNow() { store.refresh() }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func openSettings() {
        settingsWindow?.close()
        let view = SettingsView(config: store.config) { [weak self] cfg in
            self?.store.apply(cfg)
            self?.settingsWindow?.close()
        }
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "FantasyTicker Settings"
        w.contentView = NSHostingView(rootView: view)
        w.isReleasedWhenClosed = false
        w.center()
        settingsWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
