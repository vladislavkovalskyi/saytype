import Testing
@testable import VMCore

@Suite struct StructureValidatorTests {
    let original = "Сегодня доделываю авторизацию во-первых поправить useEffect в Header во-вторых задеплоить ветку на Vercel"

    @Test func acceptsListWithDroppedOrdinals() {
        let candidate = """
        Сегодня доделываю авторизацию:
        1. Поправить useEffect в Header.
        2. Задеплоить ветку на Vercel.
        """
        #expect(StructureValidator.accepts(original: original, candidate: candidate))
    }

    @Test func rejectsRewrittenWords() {
        #expect(!StructureValidator.accepts(original: original, candidate: "Сегодня заканчиваю авторизацию: поправить useEffect в Header, задеплоить ветку на Vercel."))
    }

    @Test func rejectsReorderedAndAddedWords() {
        #expect(!StructureValidator.accepts(original: "поправь хедер и футер", candidate: "Поправь футер и хедер."))
        #expect(!StructureValidator.accepts(original: "поправь хедер", candidate: "Пожалуйста, поправь хедер."))
    }

    @Test func rejectsDroppedContentWords() {
        #expect(!StructureValidator.accepts(original: "поправь хедер и футер", candidate: "Поправь хедер."))
    }

    @Test func dropsFillersOnlyWhenAllowed() {
        #expect(!StructureValidator.accepts(original: "короче поправь хедер", candidate: "Поправь хедер."))
        #expect(StructureValidator.accepts(original: "короче поправь хедер", candidate: "Поправь хедер.", allowDroppingFillers: true))
        #expect(StructureValidator.accepts(original: "эээ поправь хедер", candidate: "Поправь хедер."))
    }

    @Test func keepsNumbersThatAreNotListMarkers() {
        #expect(StructureValidator.accepts(original: "проверь вёрстку на 375 пикселей", candidate: "Проверь вёрстку на 375 пикселей."))
        #expect(!StructureValidator.accepts(original: "проверь вёрстку на 375 пикселей", candidate: "Проверь вёрстку на пикселей."))
    }

    @Test func cleansWrappersAndBullets() {
        #expect(StructureValidator.clean("```\n**Итог**:\n- раз\n* два\n```") == "Итог:\n— раз\n— два")
        #expect(StructureValidator.clean("<think>\n\n</think>\n\n«Поправь хедер.»") == "Поправь хедер.")
    }
}
