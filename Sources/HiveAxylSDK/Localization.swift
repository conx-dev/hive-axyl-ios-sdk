import Foundation

func resolveLocalized(_ map: [String: String], language: String) -> String? {
    if let exact = map[language] {
        return exact
    }
    let base = language.split(separator: "-").first.map(String.init) ?? language
    if let baseMatch = map[base] {
        return baseMatch
    }
    if let english = map["en"] {
        return english
    }
    // 키 순서가 비결정적이므로 정렬 후 첫 항목으로 폴백
    guard let firstKey = map.keys.sorted().first else {
        return nil
    }
    return map[firstKey]
}
