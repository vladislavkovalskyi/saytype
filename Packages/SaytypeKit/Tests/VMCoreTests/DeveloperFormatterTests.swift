import Foundation
import Testing
@testable import VMCore

@Suite struct DeveloperCasingTests {
    @Test(arguments: [
        ("кэмел кейс юзер дата", "userData"),
        ("Назови переменную кэмел кейс юзер дата.", "Назови переменную userData."),
        ("паскаль кейс юзер профайл кард в компоненте", "UserProfileCard в компоненте"),
        ("снейк кейс юзер айди", "user_id"),
        ("кебаб кейс юзер профайл", "user-profile"),
        ("константа макс ретраи", "MAX_RETRIES"),
        ("капс снейк апи кей", "API_KEY"),
        ("кэмел кейс из лоадинг", "isLoading"),
        ("Кэмел кейс он клик хендлер", "onClickHandler"),
        ("кэмел кейс гет юзер бай айди и потом отдай", "getUserById и потом отдай"),
        ("Camel case user data, потом", "userData, потом"),
        ("кэмел кейс, юзер дата", "userData"),
        ("кэмелкейс хэндлер", "handler"),
        ("кэмел кейс супабейс клиент", "supabaseClient"),
        ("паскаль кейс UserData провайдер", "UserDataProvider"),
        ("снейк кейс fetchUserData", "fetch_user_data"),
        ("rename it to camel case user data and run tests", "rename it to userData and run tests"),
        ("кэмел кейс юзер дата лист стейт хендлер фетч квери", "userDataListStateHandlerFetch квери"),
        ("кэмел кейс юзер из дома", "user из дома"),
        ("Переименуй в снейк кейс created at.", "Переименуй в created_at."),
        ("Переименуй в снейк кейс created at в базе", "Переименуй в created_at в базе"),
        ("rename it to camel case sort by.", "rename it to sortBy."),
        ("кэмел кейс сайн ин", "signIn"),
        ("Camel-кейс хэндл сабмит.", "handleSubmit."),
        ("Переменная кэмел кейс из модал опен должна быть false", "Переменная isModalOpen должна быть false"),
    ])
    func casing(_ input: String, _ expected: String) {
        #expect(DeveloperFormatter.apply(input) == expected)
    }
}

@Suite struct DeveloperPathTests {
    @Test(arguments: [
        ("src слэш components слэш header точка tsx", "src/components/header.tsx"),
        ("открой src слэш компонентс слэш хедер точка tsx.", "открой src/components/header.tsx."),
        ("поправь пакадж точка джейсон", "поправь package.json"),
        ("поправь хедер точка tsx", "поправь header.tsx"),
        ("выведи process точка env точка NODE_ENV", "выведи process.env.NODE_ENV"),
        ("vlad собака gmail точка com", "vlad@gmail.com"),
        ("добавь в точка env ключ", "добавь в .env ключ"),
        ("андерскор апп точка tsx", "_app.tsx"),
        ("юзер нижнее подчёркивание айди", "user_id"),
        ("андерскор андерскор инит андерскор андерскор", "__init__"),
        ("команда слэш start", "команда /start"),
        ("фронтенд слеш бэкенд", "frontend/backend"),
        ("items точка map", "items.map"),
        ("Добавь роут слэш api слэш health.", "Добавь роут /api/health."),
        ("Открой тс конфиг точка джейсон.", "Открой tsconfig.json."),
        ("Импортируй из собака слэш components слэш ui", "Импортируй из @/components/ui"),
        ("Версия 1 точка 2 уже вышла", "Версия 1.2 уже вышла"),
        ("Добавь в точка env точка local", "Добавь в .env.local"),
        ("паскаль кейс апп стор провайдер точка tsx", "AppStoreProvider.tsx"),
    ])
    func paths(_ input: String, _ expected: String) {
        #expect(DeveloperFormatter.apply(input) == expected)
    }
}

@Suite struct DeveloperSymbolTests {
    @Test(arguments: [
        ("if x не равно null", "if x != null"),
        ("проверь a строго равно b", "проверь a === b"),
        ("count больше или равно 10", "count >= 10"),
        ("count меньше или равно limit", "count <= limit"),
        ("items точка map item стрелка item", "items.map item => item"),
        ("func load() тонкая стрелка String", "func load() -> String"),
        ("передай три точки props", "передай ...props"),
        ("спред пропс в кнопку", "...props в кнопку"),
        ("status строго не равно 200", "status !== 200"),
    ])
    func symbols(_ input: String, _ expected: String) {
        #expect(DeveloperFormatter.apply(input) == expected)
    }
}

/// Ordinary speech that must come out exactly as it went in.
@Suite struct DeveloperFalsePositiveTests {
    static let corpus = [
        "Моя собака любит гулять по утрам.",
        "Собака лает на кошку",
        "Стрелка часов показывает три.",
        "Стрелка вниз не работает",
        "Нажми Shift стрелка вниз",
        "Они не равно распределены по командам.",
        "Это не равно тому, что я говорил",
        "Это строго равно нулю",
        "Цена больше или равно ста рублей",
        "С моей точки зрения это неправильно.",
        "С точки зрения архитектуры лучше разделить",
        "Точка зрения у всех разная.",
        "В точке входа падает ошибка",
        "Встретимся в точке сбора",
        "Поставь точку в конце.",
        "Это конечная точка маршрута",
        "Файл точка json",
        "Напиши через слэш",
        "Текст слэш код",
        "Используй нижнее подчёркивание вместо дефиса.",
        "Три точки в конце предложения.",
        "Поставь три точки и продолжай",
        "Спред оператор в джаваскрипте",
        "Эта константа не меняется",
        "Константа Планка очень маленькая",
        "Пиши в кэмел кейс, а не в снейк кейс.",
        "Кэмел кейс для переменных",
        "Мне больше нравится паскаль кейс",
        "Я пришёл домой и лёг спать",
        "Дата релиза перенесена на пятницу",
        "Лист бумаги лежит на столе",
        "Use an arrow function here.",
        "Press the arrow keys to move.",
        "I prefer snake case because it reads better.",
        "Camel case variables are fine.",
        "They are not equal.",
        "My dog is at home.",
        "From my point of view this is wrong.",
        "Add a dot at the end.",
        "Slash the budget in half.",
        "Switch to snake case on the backend.",
        "I prefer camel case in general.",
        "Use camel case for variables.",
        "Слэш команда start не работает в боте",
        "Сравни через тройное равно",
        "Функция принимает props и возвращает стрелка JSX",
        "Используй стрелочную функцию",
        "Поставь точку с запятой в конце строки",
    ]

    @Test func ordinarySpeechIsUnchanged() {
        for sentence in Self.corpus {
            #expect(DeveloperFormatter.apply(sentence) == sentence)
        }
    }

    @Test func whitespaceAndLineBreaksStay() {
        let text = "первая строка\nвторая  строка "
        #expect(DeveloperFormatter.apply(text) == text)
        #expect(DeveloperFormatter.apply("кэмел кейс юзер дата\nи дальше ") == "userData\nи дальше ")
    }
}

@Suite struct BackticksTests {
    @Test(arguments: [
        ("поправь useEffect в Header.", "поправь `useEffect` в Header."),
        ("открой src/components/header.tsx, там ошибка", "открой `src/components/header.tsx`, там ошибка"),
        ("React, Supabase и GitHub", "React, Supabase и GitHub"),
        ("обнови Next.js и TypeScript", "обнови Next.js и TypeScript"),
        ("вызови fetchUser().", "вызови `fetchUser()`."),
        ("(useState)", "(`useState`)"),
        ("положи OPENAI_API_KEY в .env", "положи `OPENAI_API_KEY` в `.env`"),
        ("проверь API на localhost:3000", "проверь API на `localhost:3000`"),
        ("обнови package.json", "обнови `package.json`"),
        ("см. https://github.com/foo/barBaz и vlad@gmail.com", "см. https://github.com/foo/barBaz и vlad@gmail.com"),
        ("на macOS и iPhone", "на macOS и iPhone"),
        ("уже `useEffect` тут", "уже `useEffect` тут"),
        ("в `foo bar useEffect` тут useMemo", "в `foo bar useEffect` тут `useMemo`"),
        ("```\nconst fooBar = 1\n```\nи fooBar", "```\nconst fooBar = 1\n```\nи `fooBar`"),
        ("т.е. U.S.A. e.g.", "т.е. U.S.A. e.g."),
        ("CI/CD и UI/UX", "CI/CD и UI/UX"),
    ])
    func wraps(_ input: String, _ expected: String) {
        #expect(Backticks.wrap(input) == expected)
    }

    @Test func isIdempotent() {
        let text = "поправь useEffect в src/app.tsx, потом localStorage и `x`."
        let once = Backticks.wrap(text)
        #expect(Backticks.wrap(once) == once)
    }

    @Test func projectTermsAddKebabNames() {
        #expect(Backticks.wrap("хук use-auth", terms: ["use-auth"]) == "хук `use-auth`")
        #expect(Backticks.wrap("хук use-auth") == "хук use-auth")
        // A name from the user's dictionary stays a name.
        #expect(Backticks.wrap("обнови Next.js", terms: ["Next.js"]) == "обнови Next.js")
    }

    @Test func matchesWordsIsCodeLike() {
        let words = ["useEffect", "Next.js", "feature/auth", "OPENAI_API_KEY", "localhost:3000", "/start", ".env", "process.env",
                     "Vercel", "React", "API", "15.2", "U.S", "a.b", "ab", "x_y", "abc_d", "fooBar()", "HTTP/2", "v1.2", "i.e",
                     "iOS", "gpt-4o", "user-data", "C++", "a:b", "abc:d", "/a", "..", "...", "~/code", "@types/node"]
        for word in words {
            #expect(Backticks.isCodeLike(word) == Words.isCodeLike(word), "\(word)")
        }
    }

    @Test func builtInTermsSplitIntoNamesAndIdentifiers() {
        for identifier in ["useEffect", "localStorage", "package.json", ".env", ".gitignore"] {
            #expect(Backticks.builtInIdentifiers.contains(identifier), "\(identifier)")
        }
        for name in ["GitHub", "Next.js", "macOS", "iPhone", "jQuery", "TypeScript", "CI/CD"] {
            #expect(Backticks.builtInNames.contains(name), "\(name)")
        }
    }
}
