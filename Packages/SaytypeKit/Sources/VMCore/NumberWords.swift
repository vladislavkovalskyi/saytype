import Foundation

/// Numbers spelled out in words, in Russian and English: "восемнадцатую" is 18, "двадцать пять" 25,
/// "12 тысяч" 12000. Lets the rewrite check tell a model's "18" from an invented number.
enum NumberWords {
    /// Every value the text names: each number word, each run of them added up, and runs
    /// scaled by "тысяч" or "million" on either side.
    static func values(in text: String) -> Set<Double> {
        let keys = Words.keys(text)
        var values = Set<Double>()
        var i = 0
        while i < keys.count {
            guard value(keys[i]) != nil else {
                i += 1
                continue
            }
            var total = 0.0
            var current = 0.0
            var previous: Double?
            while i < keys.count, let word = value(keys[i]) {
                values.insert(word)
                if multipliers.contains(word) {
                    if let previous { values.insert(previous * word) }
                    current = (current == 0 ? 1 : current) * word
                    total += current
                    current = 0
                } else {
                    if let previous, multipliers.contains(previous) { values.insert(word * previous) }
                    current += word
                }
                previous = word
                i += 1
            }
            values.insert(total + current)
        }
        return values
    }

    static func value(_ key: String) -> Double? {
        table[key] ?? (key.first?.isNumber == true ? Double(key.replacingOccurrences(of: ",", with: ".")) : nil)
    }

    static let multipliers: Set<Double> = [1000, 1_000_000]

    static let table: [String: Double] = {
        var table: [String: Double] = [:]
        func add(_ value: Double, _ forms: String) {
            for form in forms.split(separator: " ") { table[String(form)] = value }
        }
        let ordinal = ["ый", "ая", "ое", "ую", "ого", "ой", "ом", "ые", "ых"]
        /// "пят" → пять, пяти, пятью, пятый, пятая…
        func regular(_ value: Double, _ stem: String) {
            add(value, ([stem + "ь", stem + "и", stem + "ью"] + ordinal.map { stem + $0 }).joined(separator: " "))
        }

        add(0, "ноль нуль нуля нулю нулем zero")
        add(1, "один одна одно одну одного одной одному одним первый первая первое первую первого первой первом one first")
        add(2, "два две двух двум двумя второй вторая второе вторую второго втором two second")
        add(3, "три трех трем тремя третий третья третье третью третьего третьей третьем three third")
        add(4, "четыре четырех четырем четырьмя четвертый четвертая четвертое четвертую четвертого четвертом four fourth")
        regular(5, "пят")
        add(6, "шесть шести шестью шестой шестая шестое шестую шестого шестом six")
        add(7, "семь семи седьмой седьмая седьмое седьмую седьмого седьмом seven")
        add(8, "восемь восьми восемью восьмой восьмая восьмое восьмую восьмого восьмом eight")
        regular(9, "девят")
        regular(10, "десят")
        for (value, stem) in [(11.0, "одиннадцат"), (12, "двенадцат"), (13, "тринадцат"), (14, "четырнадцат"), (15, "пятнадцат"),
                              (16, "шестнадцат"), (17, "семнадцат"), (18, "восемнадцат"), (19, "девятнадцат"), (20, "двадцат"), (30, "тридцат")] {
            regular(value, stem)
        }
        add(5, "five")
        add(9, "nine")
        add(10, "ten")
        for (value, word) in [(11.0, "eleven"), (12, "twelve"), (13, "thirteen"), (14, "fourteen"), (15, "fifteen"), (16, "sixteen"),
                              (17, "seventeen"), (18, "eighteen"), (19, "nineteen"), (20, "twenty"), (30, "thirty"), (40, "forty"),
                              (50, "fifty"), (60, "sixty"), (70, "seventy"), (80, "eighty"), (90, "ninety"), (100, "hundred")] {
            add(value, word)
        }
        add(40, "сорок сорока сороковой сороковая сороковую")
        add(50, "пятьдесят пятидесяти пятидесятый")
        add(60, "шестьдесят шестидесяти шестидесятый")
        add(70, "семьдесят семидесяти семидесятый")
        add(80, "восемьдесят восьмидесяти восьмидесятый")
        add(90, "девяносто девяноста девяностый")
        add(100, "сто ста сотня сотни сотню сотый")
        add(200, "двести двухсот")
        add(300, "триста трехсот")
        add(400, "четыреста четырехсот")
        add(500, "пятьсот пятисот")
        add(600, "шестьсот шестисот")
        add(700, "семьсот семисот")
        add(800, "восемьсот восьмисот")
        add(900, "девятьсот девятисот")
        add(1000, "тысяча тысячи тысячу тысяч тысячей тысячах тыс thousand thousands")
        add(1_000_000, "миллион миллиона миллионов млн million millions")
        add(24, "сутки суток")
        return table
    }()
}
