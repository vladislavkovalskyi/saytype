import Testing
@testable import VMCore

@Suite struct RewriteRequestTests {
    @Test func modeWithoutModelWorkHasNoRequest() {
        #expect(RewriteRequest(mode: DictationMode(id: "standard"), language: .russian) == nil)
        #expect(RewriteRequest(mode: DictationMode(id: "x", rewrite: .custom, instruction: "  "), language: .russian) == nil)
    }

    @Test func translationAloneIsARequest() {
        let request = RewriteRequest(mode: DictationMode(id: "x", translateToEnglish: true), language: .russian)
        #expect(request?.style == DictationMode.Rewrite.none)
        #expect(request?.translate == true)
        #expect(request?.systemPrompt.contains("Write the answer in English.") == true)
    }

    @Test func answerKeepsTheSpeechLanguage() {
        let request = RewriteRequest(mode: DictationMode(id: "x", rewrite: .cleaner), language: .russian)
        #expect(request?.sourceLanguage == "Russian")
        #expect(request?.systemPrompt.hasSuffix("Write the answer in Russian, the language of the dictation.") == true)
        #expect(RewriteRequest(style: .prompt, sourceLanguage: "Russian").systemPrompt.contains("Цель, Контекст, Шаги, Ограничения"))
        #expect(RewriteRequest(style: .prompt, translate: true, sourceLanguage: "Russian").systemPrompt.contains("Goal, Context, Steps, Constraints"))
    }

    /// The overlay's switch translates everything, into whatever language it names.
    @Test func translatesIntoTheChosenLanguage() {
        let mode = DictationMode(id: DictationMode.standardID)
        let request = RewriteRequest(mode: mode, language: .russian, translateTo: AppSettings.SpeechLanguage(rawValue: "uk"))
        #expect(request?.translate == true)
        #expect(request?.targetLanguage == "Ukrainian")
        #expect(request?.answersInEnglish == false)
        #expect(request?.systemPrompt.hasSuffix("Write the answer in Ukrainian.") == true)
        #expect(request?.userMessage("Поправь хедер").hasPrefix("Translate this dictation into Ukrainian.") == true)
        // English is still English, named or not.
        #expect(RewriteRequest(mode: mode, language: .russian, translateTo: .english)?.answersInEnglish == true)
        // Without the switch a mode that does not translate needs no model at all.
        #expect(RewriteRequest(mode: mode, language: .russian) == nil)
    }

    @Test func commitIsEnglishWithoutTranslation() {
        let request = RewriteRequest(style: .commit, sourceLanguage: "Russian")
        #expect(request.answersInEnglish)
        #expect(request.systemPrompt.hasSuffix("Write the answer in English."))
    }

    @Test func everyModeStyleSharesThePromptPrefix() {
        let prompts = DictationMode.Rewrite.modeStyles.map { RewriteRequest(style: $0, instruction: "Сделай баг-репорт").systemPrompt }
        #expect(prompts.allSatisfy { $0.hasPrefix(RewriteRequest.commonRules) })
    }

    /// Editing a selection is a different job: its own rules, its own tag, and the answer's
    /// language is the instruction's business.
    @Test func selectionEditsTheFragment() {
        let request = RewriteRequest(style: .selection, instruction: "перепиши короче")
        #expect(request.systemPrompt.hasPrefix(RewriteRequest.selectionRules))
        #expect(request.systemPrompt.contains("<instruction>\nперепиши короче\n</instruction>"))
        #expect(request.userMessage("Длинный текст").contains("<fragment>\nДлинный текст\n</fragment>"))
        #expect(!request.answersInEnglish)
        #expect(RewriteRequest.clean("<fragment>\nКороче\n</fragment>", input: "Длинный текст") == "Короче")
    }

    @Test func customInstructionIsInThePrompt() {
        #expect(RewriteRequest(style: .custom, instruction: "Сделай баг-репорт").systemPrompt.contains("<instruction>\nСделай баг-репорт\n</instruction>"))
    }

    @Test func tokenLimitGrowsWithInputAndIsCapped() {
        let request = RewriteRequest(style: .cleaner)
        #expect(request.maxTokens(inputTokens: 100) > 100)
        #expect(request.maxTokens(inputTokens: 1000) > request.maxTokens(inputTokens: 100))
        #expect(request.maxTokens(inputTokens: 100_000) == 4096)
    }

    @Test func cleanRemovesWrappers() {
        #expect(RewriteRequest.clean("<think>\nhmm\n</think>\n\nПоправь хедер.", input: "поправь хедер") == "Поправь хедер.")
        #expect(RewriteRequest.clean("Here is the cleaned text:\nПоправь хедер.", input: "поправь хедер") == "Поправь хедер.")
        #expect(RewriteRequest.clean("«Поправь хедер.»", input: "поправь хедер") == "Поправь хедер.")
        #expect(RewriteRequest.clean("```\nfix(ui): header\n```", input: "поправь хедер") == "fix(ui): header")
        #expect(RewriteRequest.clean("<dictation>\nПоправь хедер.\n</dictation>", input: "поправь хедер") == "Поправь хедер.")
    }

    @Test func cleanKeepsWhatTheDictationHad() {
        #expect(RewriteRequest.clean("```\nnpm run dev\n```", input: "запусти ```npm run dev```") == "```\nnpm run dev\n```")
        #expect(RewriteRequest.clean("Цель:\nПоправить хедер.", input: "поправь хедер") == "Цель:\nПоправить хедер.")
    }
}

@Suite struct RewriteValidatorTests {
    let prompt = RewriteRequest(style: .prompt, sourceLanguage: "Russian")
    let cleaner = RewriteRequest(style: .cleaner, sourceLanguage: "Russian")
    let commit = RewriteRequest(style: .commit, sourceLanguage: "Russian")
    let translation = RewriteRequest(style: .none, translate: true, sourceLanguage: "Russian")
    let selection = RewriteRequest(style: .selection, instruction: "переведи на английский")

    let dictation = "Слушай, короче, поправь useEffect в src/components/Header.tsx, он дёргается 3 раза, и глянь https://github.com/acme/app/issues/42."

    @Test func acceptsARestructuredPrompt() {
        let candidate = """
        Цель:
        Исправить лишние срабатывания useEffect.

        Контекст:
        - Файл src/components/Header.tsx, эффект срабатывает 3 раза.
        - Задача: https://github.com/acme/app/issues/42
        """
        #expect(RewriteValidator.check(original: dictation, candidate: candidate, request: prompt) == .accepted)
    }

    /// The user asked for the words to change: only an empty or runaway answer is rejected.
    @Test func selectionIsCheckedForLengthOnly() {
        let fragment = "Сегодня доделываю авторизацию и деплой."
        #expect(RewriteValidator.check(original: fragment, candidate: "Finishing auth and the deploy today.", request: selection) == .accepted)
        #expect(RewriteValidator.check(original: fragment, candidate: "  ", request: selection) == .rejected(.empty))
        #expect(RewriteValidator.check(original: fragment, candidate: String(repeating: "слово ", count: 200), request: selection) == .rejected(.tooLong))
    }

    /// Ukrainian is Cyrillic and Polish is Latin: the script of the answer says nothing about
    /// whether the model translated, so only English is checked.
    @Test func languageIsCheckedForEnglishOnly() {
        let toUkrainian = RewriteRequest(style: .none, translate: true, targetLanguage: "Ukrainian", sourceLanguage: "Russian")
        let fragment = "Поправь хедер в компоненте, он дёргается."
        #expect(RewriteValidator.check(original: fragment, candidate: "Виправ хедер у компоненті, він смикається.", request: toUkrainian) == .accepted)
        #expect(RewriteValidator.check(original: fragment, candidate: "Поправь хедер в компоненте, он дёргается.", request: translation) == .rejected(.wrongLanguage))
    }

    @Test func rejectsDroppedCodePathsNumbersAndLinks() {
        let noPath = "Поправь useEffect в хедере, он дёргается 3 раза, и глянь https://github.com/acme/app/issues/42."
        #expect(RewriteValidator.check(original: dictation, candidate: noPath, request: prompt) == .rejected(.dropped("src/components/Header.tsx")))
        let noNumber = "Поправь useEffect в src/components/Header.tsx, он дёргается несколько раз, и глянь https://github.com/acme/app/issues/42."
        #expect(RewriteValidator.check(original: dictation, candidate: noNumber, request: prompt) == .rejected(.dropped("3")))
        let noLink = "Поправь useEffect в src/components/Header.tsx, он дёргается 3 раза."
        #expect(RewriteValidator.check(original: dictation, candidate: noLink, request: prompt) == .rejected(.dropped("https://github.com/acme/app/issues/42")))
        let renamed = "Поправь useLayoutEffect в src/components/Header.tsx, он дёргается 3 раза, и глянь https://github.com/acme/app/issues/42."
        #expect(RewriteValidator.check(original: dictation, candidate: renamed, request: prompt) == .rejected(.dropped("useEffect")))
    }

    @Test func rejectsInventedPathsLinksAndNumbers() {
        let original = "поправь хедер, он дёргается"
        #expect(RewriteValidator.check(original: original, candidate: "Поправь src/Header.tsx, он дёргается.", request: cleaner) == .rejected(.invented("src/Header.tsx")))
        #expect(RewriteValidator.check(original: original, candidate: "Поправь хедер, он дёргается 250 раз.", request: cleaner) == .rejected(.invented("250")))
    }

    @Test func listNumbersAndSmallNumbersAreNotInvented() {
        let original = "во-первых поправь хедер во-вторых футер и сделай два коммита"
        let candidate = "Шаги:\n1. Поправь хедер.\n2. Поправь футер.\n3. Сделай 2 коммита."
        #expect(RewriteValidator.check(original: original, candidate: candidate, request: prompt) == .accepted)
    }

    @Test func dictionaryTermsMustStay() {
        let original = "задеплой ветку на Vercel и проверь превью"
        #expect(RewriteValidator.check(original: original, candidate: "Задеплой ветку и проверь превью.", request: cleaner, terms: ["Vercel"]) == .rejected(.dropped("Vercel")))
        #expect(RewriteValidator.check(original: original, candidate: "Задеплой ветку на vercel и проверь превью.", request: cleaner, terms: ["Vercel"]) == .accepted)
    }

    @Test func cleanerMayResolveSelfCorrections() {
        let original = "поставь таймаут 5 секунд, нет, подожди, не 5, а 10 секунд в api/client.ts"
        #expect(RewriteValidator.check(original: original, candidate: "Поставь таймаут 10 секунд в api/client.ts.", request: cleaner) == .accepted)
        let deploy = "задеплой не на Vercel, а на Netlify"
        #expect(RewriteValidator.check(original: deploy, candidate: "Задеплой на Netlify.", request: cleaner, terms: ["Vercel", "Netlify"]) == .accepted)
        // A plain translation keeps everything the speaker said.
        #expect(RewriteValidator.check(original: original, candidate: "Set the timeout to 10 seconds in api/client.ts.", request: translation) == .rejected(.dropped("5")))
    }

    @Test func cleanerMayDropFillersAndRepeats() {
        let original = "ну короче короче надо надо поправить useEffect useEffect в Header"
        #expect(RewriteValidator.check(original: original, candidate: "Надо поправить useEffect в Header.", request: cleaner) == .accepted)
    }

    @Test func rejectsEmptyTooLongAndTooShort() {
        #expect(RewriteValidator.check(original: dictation, candidate: "  \n", request: cleaner) == .rejected(.empty))
        let runaway = String(repeating: dictation + " ", count: 3)
        #expect(RewriteValidator.check(original: dictation, candidate: runaway, request: cleaner) == .rejected(.tooLong))
        #expect(RewriteValidator.check(original: dictation, candidate: "Поправь useEffect.", request: cleaner) == .rejected(.tooShort))
    }

    @Test func translationKeepsTokensAndIsEnglish() {
        let english = "Fix useEffect in src/components/Header.tsx, it fires 3 times, and check https://github.com/acme/app/issues/42."
        #expect(RewriteValidator.check(original: dictation, candidate: english, request: translation) == .accepted)
        #expect(RewriteValidator.check(original: dictation, candidate: dictation, request: translation) == .rejected(.wrongLanguage))
    }

    @Test func rewriteKeepsTheLanguageUnlessTranslating() {
        let english = "Fix useEffect in src/components/Header.tsx, it fires 3 times, and check https://github.com/acme/app/issues/42."
        #expect(RewriteValidator.check(original: dictation, candidate: english, request: cleaner) == .rejected(.wrongLanguage))
    }

    @Test func commitNeedsAConventionalHeader() {
        let original = "поправил баг в useEffect в Header, он срабатывал 3 раза"
        #expect(RewriteValidator.check(original: original, candidate: "fix(header): stop useEffect from running 3 times", request: commit) == .accepted)
        #expect(RewriteValidator.check(original: original, candidate: "Fixed useEffect in Header running 3 times", request: commit) == .rejected(.notConventionalCommit))
        #expect(RewriteValidator.check(original: original, candidate: "fix(smart-structure): stop useEffect in Header from running 3 times", request: commit) == .accepted)
    }

    @Test func commitMayLeaveOutContextButNotMost() {
        let original = "переделал хедер на SwiftUI, поправил useEffect в src/Header.tsx, порт 6379"
        #expect(RewriteValidator.check(original: original, candidate: "fix(header): fix useEffect in src/Header.tsx", request: commit) == .accepted)
        #expect(RewriteValidator.check(original: original, candidate: "fix(header): rework header", request: commit) == .rejected(.dropped("SwiftUI")))
    }

    @Test func unitsThousandsAndTimesCountAsKept() {
        let original = "высота строки 48 пикселей, объектов около 12 тысяч, тихий режим с 23:00 до 8:00"
        let english = "Row height is 48px, about 12,000 objects, quiet hours from 23:00 to 08:00."
        #expect(RewriteValidator.check(original: original, candidate: english, request: translation) == .accepted)
    }

    @Test func spokenNumbersMayBecomeDigits() {
        let original = "восемнадцатую версию ноды убираем, эндпоинтов около сорока, две тысячи минут"
        let english = "We drop Node 18, there are about 40 endpoints, 2000 minutes."
        #expect(RewriteValidator.check(original: original, candidate: english, request: translation) == .accepted)
        #expect(RewriteValidator.check(original: original, candidate: "We drop Node 16, there are about 40 endpoints, 2000 minutes.", request: translation) == .rejected(.invented("16")))
    }

    @Test func acronymTermsMatchTheirCase() {
        let original = "cursor это id последнего лида"
        #expect(RewriteValidator.check(original: original, candidate: "cursor is the last lead's identifier", request: translation, terms: ["ID"]) == .accepted)
        #expect(RewriteValidator.check(original: "передай ID лида", candidate: "pass the lead", request: translation, terms: ["ID"]) == .rejected(.dropped("ID")))
    }

    @Test func numberWordValues() {
        #expect(NumberWords.values(in: "двадцать пять").contains(25))
        #expect(NumberWords.values(in: "две тысячи").contains(2000))
        #expect(NumberWords.values(in: "тысяч десяти").contains(10000))
        #expect(NumberWords.values(in: "12 тысяч").contains(12000))
        #expect(!NumberWords.values(in: "пятница").contains(5))
    }

    @Test func decimalCommaMatchesDecimalPoint() {
        let original = "обнови Next.js до 15,2"
        #expect(RewriteValidator.check(original: original, candidate: "Update Next.js to 15.2", request: translation) == .accepted)
        #expect(RewriteValidator.check(original: original, candidate: "Update Next.js to 15", request: translation) == .rejected(.dropped("15,2")))
    }

    @Test func protectedTokensCoverCodeShapes() {
        let tokens = RewriteValidator.protectedTokens(in: "добавь OPENAI_API_KEY в .env, вызови fetch() и поставь react-window v1.8.10 на localhost:3000, ветка EC-123, API", terms: []).map(\.text)
        #expect(tokens.contains("OPENAI_API_KEY"))
        #expect(tokens.contains("fetch"))
        #expect(tokens.contains("react-window"))
        #expect(tokens.contains("v1.8.10"))
        #expect(tokens.contains("localhost:3000"))
        #expect(tokens.contains("EC-123"))
        #expect(tokens.contains("API"))
        #expect(tokens.contains("3000"))
    }

    @Test func wholeTokenSearch() {
        #expect(RewriteValidator.contains("поправь useeffect.", "useeffect"))
        #expect(!RewriteValidator.contains("поправь useeffects", "useeffect"))
        #expect(!RewriteValidator.contains("версия 15.2", "5.2"))
        #expect(!RewriteValidator.contains("версия 5.2", "5"))
        #expect(RewriteValidator.contains("до 5.", "5"))
    }
}
