import Testing
@testable import VMCore

@Suite struct SmartStructureTests {
    let text = "Короче, есть три проблемы с GitHub Actions. Первая, шаг build падает. Вторая, кэш npm не подхватывается. Третья, тесты на Jest идут долго. Посмотри, что можно сделать."

    @Test func splitsSentencesButKeepsTermsWhole() {
        #expect(SmartStructure.sentences("Обнови Next.js до 15.2. Потом задеплой!\n\nГотово?") == ["Обнови Next.js до 15.2.", "Потом задеплой!", "Готово?"])
    }

    @Test func parsesLabelsAndIgnoresNoise() {
        let labels = SmartStructure.parseLabels("<think></think>\n1 T\n2 - L\n3: L\n9 L\nкакой-то текст\n", count: 4)
        #expect(labels == [.text, .item, .item, .text])
    }

    @Test func rendersListWithIntroductionAndConclusion() {
        let sentences = SmartStructure.sentences(text)
        let result = SmartStructure.render(sentences, labels: [.text, .item, .item, .item, .paragraph])
        #expect(result == """
        Короче, есть три проблемы с GitHub Actions:
        1. Первая, шаг build падает.
        2. Вторая, кэш npm не подхватывается.
        3. Третья, тесты на Jest идут долго.

        Посмотри, что можно сделать.
        """)
        #expect(StructureValidator.accepts(original: text, candidate: result))
    }

    @Test func loneItemIsPlainText() {
        let sentences = ["Открой localhost.", "Сделай скриншоты."]
        #expect(SmartStructure.render(sentences, labels: [.text, .item]) == "Открой localhost. Сделай скриншоты.")
    }

    @Test func keepsParagraphsFromPauses() {
        let formatted = "Сборка упала. Посмотри логи.\n\nПотом задеплой. И напиши мне."
        let sentences = SmartStructure.sentences(formatted)
        let starts = SmartStructure.paragraphStarts(formatted)
        #expect(starts == [2])
        #expect(SmartStructure.render(sentences, labels: [.text, .text, .text, .text], paragraphStarts: starts) == formatted)
    }

    @Test func skipsShortTextsAndExistingLists() {
        #expect(!SmartStructure.shouldStructure("поправь хедер", minWords: 40))
        #expect(!SmartStructure.shouldStructure(String(repeating: "слово ", count: 50) + "\n1. Пункт", minWords: 40))
        #expect(SmartStructure.shouldStructure(String(repeating: "слово ", count: 50), minWords: 40))
    }
}
