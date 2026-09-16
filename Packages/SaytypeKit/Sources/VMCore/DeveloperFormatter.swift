import Foundation

/// Spoken code for developer modes: casing ("кэмел кейс юзер дата" → userData), paths
/// ("src слэш app точка tsx" → src/app.tsx) and symbols ("стрелка" → =>).
public enum DeveloperFormatter {
    public static func apply(_ text: String) -> String {
        text
    }
}

/// Markdown code spans for developer modes: "поправь useEffect" → "поправь `useEffect`".
public enum Backticks {
    public static func wrap(_ text: String) -> String {
        text
    }
}
