import Foundation

struct App {
    let name: String
    let path: String
    let id: String  // bundle id; path reported at runtime can differ (Safari lives in a cryptex)
}

let appDirs = [
    "/Applications", "/Applications/Utilities",
    "/System/Applications", "/System/Applications/Utilities",
    NSHomeDirectory() + "/Applications",
]

let extraApps = ["/System/Library/CoreServices/Finder.app"]

// ponytail: top-level dir scan only, misses apps in other folders. Upgrade: NSMetadataQuery on kMDItemContentType == "com.apple.application-bundle".
func scanApps() -> [App] {
    let fm = FileManager.default
    var seen = Set<String>()
    var apps: [App] = []
    let paths = appDirs.flatMap { dir in
        ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".app") }.map { dir + "/" + $0 }
    }
    for path in paths + extraApps {
        var name = fm.displayName(atPath: path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        let id = Bundle(path: path)?.bundleIdentifier ?? path
        if seen.insert(name).inserted { apps.append(App(name: name, path: path, id: id)) }
    }
    return apps
}

/// Higher is better, nil = no match. Tiers: prefix > initials > word prefix > subsequence; shorter name wins ties.
func score(_ query: String, _ name: String) -> Int? {
    let q = query.lowercased(), n = name.lowercased()
    guard !q.isEmpty else { return nil }
    let words = n.split(whereSeparator: { " -._".contains($0) })
    let tier: Int
    if n.hasPrefix(q) {
        tier = 4
    } else if String(words.compactMap(\.first)).hasPrefix(q) {
        tier = 3
    } else if words.contains(where: { $0.hasPrefix(q) }) {
        tier = 2
    } else {
        var i = n.startIndex
        for c in q {
            guard let j = n[i...].firstIndex(of: c) else { return nil }
            i = n.index(after: j)
        }
        tier = 1
    }
    return tier * 1000 - n.count
}

func selftest() {
    precondition(score("saf", "Safari")! > score("saf", "Some App Folder")!)
    precondition(score("vsc", "Visual Studio Code") != nil)
    precondition(score("vsc", "Visual Studio Code")! > score("vsc", "Xvscode Helper Tool Long")!)
    precondition(score("term", "Terminal")! > score("term", "Activity Terminal Monitor")!)
    precondition(score("xyz", "Safari") == nil)
    precondition(score("", "Safari") == nil)
    precondition(score("NOTES", "Notes") != nil)
    precondition(calc("2+3*4") == 14)
    precondition(calc("(2+3)*4") == 20)
    precondition(calc("-2^2") == -4)
    precondition(calc("2^-1") == 0.5)
    precondition(calc("2^3^2") == 512)
    precondition(calc("3,5 * 2") == 7)
    precondition(calc("1/0") == nil)
    precondition(calc("2+") == nil)
    precondition(calc("(1+2") == nil)
    precondition(calc("safari") == nil)
    precondition(urlItem("github.com")?.title == "https://github.com")
    precondition(urlItem("http://localhost.dev/a?b=1")?.title == "http://localhost.dev/a?b=1")
    precondition(urlItem("www.apple.com/tr ") != nil)
    precondition(urlItem("ugurgunes.dev")?.title == "https://ugurgunes.dev")
    precondition(urlItem("tanstack.dev/start")?.title == "https://tanstack.dev/start")
    precondition(urlItem("linear.app") != nil)
    precondition(urlItem("studio") == nil)
    precondition(urlItem("Package.swift") == nil)
    precondition(urlItem("main.py") == nil)
    precondition(urlItem("safari") == nil)
    precondition(urlItem("2+2") == nil)
    precondition(urlItem("foo bar.com") == nil)
    precondition(urlItem("me@mail.com") == nil)
    print("selftest ok")
}
