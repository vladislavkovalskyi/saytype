import Testing
@testable import VMCore

@Suite struct BuiltInDictionaryTests {
    let rewriter = DictionaryRewriter(entries: [], builtIn: true, builtInTerms: [])

    @Test(arguments: [
        ("поправь юз эффект в реакте и задеплой на версель", "поправь useEffect в React и задеплой на Vercel"),
        ("спроси у клода или в чат джипити", "спроси у Claude или в ChatGPT"),
        ("подними докер композ с постгресом", "подними Docker Compose с Postgres"),
        ("Запушь на гитхаб, потом открой пи ар.", "Запушь на GitHub, потом открой PR."),
        ("сверстай в фигме и перенеси на тейлвинд", "сверстай в Figma и перенеси на Tailwind"),
        ("добавь эндпоинт на фаст апи и схему в зод", "добавь эндпоинт на FastAPI и схему в Zod"),
        ("разверни в кубернетесе через терраформ", "разверни в Kubernetes через Terraform"),
        ("запусти next js и github actions", "запусти Next.js и GitHub Actions"),
        ("Открой вс код.", "Открой VS Code."),
        ("положи ключ в дот енв", "положи ключ в .env"),
    ])
    func rewritesDeveloperSpeech(input: String, expected: String) {
        #expect(rewriter.apply(to: input) == expected)
    }

    @Test(arguments: [
        "Я расту и учусь каждый день.",
        "Поставь курсор в начало строки.",
        "Смотри на это через призму опыта.",
        "Он читает Кафку в метро.",
        "Купи редиску, огурцы и хлеб.",
        "Мы сидели в кафе у окна.",
        "Давай созвонимся в пять, ок?",
        "Кот спит на диване, не буди его.",
        "Реакция была очень бурной.",
        "Позвони маме и скажи, что я скоро буду.",
        "Где ближайшая аптека?",
        "Возьми зонт, на улице дождь.",
        "Сегодня хорошая погода, пойдём гулять.",
        "Налей чаю и садись.",
        "Встреча перенеслась на завтра.",
        "Посмотрим фильм вечером.",
        "Это мой брат, он работает в банке.",
        "У нас гости, приходи позже.",
        "Он играет в футбол по субботам.",
        "Нужно отремонтировать крыльцо и покрасить дом.",
        "Я читал этот кодекс законов.",
        "Бабушка варит варенье из клубники.",
        "Мы летим в Сочи на неделю.",
        "Дети рисуют мелом на асфальте.",
        "we need to react quickly, swift and smart",
    ])
    func leavesEverydaySpeechAlone(sentence: String) {
        #expect(rewriter.apply(to: sentence) == sentence)
    }

    @Test func userEntriesWinOverBuiltIn() {
        let custom = DictionaryRewriter(entries: [DictionaryEntry(heard: "клод", written: "Claude 5")], builtIn: true, builtInTerms: [])
        #expect(custom.apply(to: "спроси клод") == "спроси Claude 5")
    }

    @Test func catalogIsLarge() {
        #expect(BuiltInDictionary.terms.count > 500)
        #expect(BuiltInDictionary.categories.count >= 8)
        #expect(!BuiltInDictionary.canonicalTerms.contains("React"))
        #expect(BuiltInDictionary.canonicalTerms.contains("Next.js"))
    }
}

@Suite struct WordFilterTests {
    @Test func removesFiltersAndTidiesUp() {
        #expect(WordFilter.remove(["короче", "как бы"], from: "Короче, я как бы закончил задачу.") == "Я закончил задачу.")
        #expect(WordFilter.remove(["literally"], from: "It literally works.") == "It works.")
        #expect(WordFilter.remove(["ну"], from: "Нужно купить хлеб.") == "Нужно купить хлеб.")
    }

    @Test func censorsProfanityButNotLookalikes() {
        #expect(WordFilter.censorProfanity("бля, опять упал билд") == "б**, опять упал билд")
        #expect(WordFilter.censorProfanity("this is fucking broken") == "this is f****** broken")
        #expect(WordFilter.censorProfanity("Хулиган оскорблял небо") == "Хулиган оскорблял небо")
        #expect(WordFilter.censorProfanity("Сукно и сумка") == "Сукно и сумка")
    }
}
