import Testing
@testable import VMCore

@Suite struct LiveAgreementTests {
    @Test func commitsOnlyWordsTwoHypothesesAgreeOn() {
        var live = LiveAgreement()
        live.update(with: "поправь юз")
        #expect(live.committed.isEmpty)
        #expect(live.pendingText == "поправь юз")

        live.update(with: "поправь useEffect в")
        #expect(live.committedText == "поправь")
        #expect(live.pendingText == "useEffect в")

        live.update(with: "поправь useEffect в Header")
        #expect(live.committedText == "поправь useEffect в")
        #expect(live.pendingText == "Header")
    }

    @Test func committedWordsSurviveAShorterHypothesis() {
        var live = LiveAgreement()
        live.update(with: "задеплой ветку на")
        live.update(with: "задеплой ветку на Vercel")
        live.update(with: "задеплой")
        #expect(live.committedText == "задеплой ветку на")
        #expect(live.pending.isEmpty)
    }

    @Test func agreementIgnoresCaseAndPunctuation() {
        var live = LiveAgreement()
        live.update(with: "так во первых")
        live.update(with: "Так, во первых")
        #expect(live.committedText == "Так, во первых")
    }
}

@Suite struct HallucinationFilterTests {
    @Test func dropsSubtitleCredits() {
        #expect(HallucinationFilter.clean("Субтитры сделал DimaTorzok") == "")
        #expect(HallucinationFilter.clean("задеплой на Vercel. Субтитры делал DimaTorzok.") == "задеплой на Vercel.")
        #expect(HallucinationFilter.clean("Редактор субтитров А. Семкин Корректор А. Егорова") == "")
    }

    @Test func keepsOrdinaryText() {
        #expect(HallucinationFilter.clean("спасибо, поправлю") == "спасибо, поправлю")
    }
}

@Suite struct PromptBuilderTests {
    @Test func listsTermsWithinLimit() {
        #expect(PromptBuilder.prompt(glossary: ["Supabase", " Prisma ", ""]) == "Supabase, Prisma.")
        #expect(PromptBuilder.prompt(glossary: []) == nil)
        let long = PromptBuilder.prompt(glossary: Array(repeating: "VeryLongTermName", count: 200))!
        #expect(long.count <= PromptBuilder.characterLimit)
    }
}

@Suite struct TermCanonicalizerTests {
    let canon = TermCanonicalizer(terms: ["useEffect", "Next.js", "React Query", "Docker Compose"])

    @Test func joinsSplitAndMiscasedTerms() {
        #expect(canon.apply(to: "Поправь Use Effect в Header.") == "Поправь useEffect в Header.")
        #expect(canon.apply(to: "вместо UseEffect, пожалуйста") == "вместо useEffect, пожалуйста")
        #expect(canon.apply(to: "обнови next js и react-query.") == "обнови Next.js и React Query.")
    }

    @Test func leavesOtherWordsAlone() {
        #expect(canon.apply(to: "подними docker, compose отдельно") == "подними docker, compose отдельно")
        #expect(canon.apply(to: "просто текст") == "просто текст")
    }
}

@Suite struct RecordKeyGestureTests {
    @Test func holdRecordsUntilRelease() {
        var g = RecordKeyGesture()
        #expect(g.handle(.keyDown(0)) == .startRecording)
        #expect(g.handle(.keyUp(1.2)) == .finishRecording)
    }

    @Test func shortTapIsDiscarded() {
        var g = RecordKeyGesture()
        #expect(g.handle(.keyDown(0)) == .startRecording)
        #expect(g.handle(.keyUp(0.1)) == .cancelRecording)
    }

    @Test func doubleTapStartsHandsFreeAndNextPressStops() {
        var g = RecordKeyGesture()
        _ = g.handle(.keyDown(0))
        _ = g.handle(.keyUp(0.1))
        #expect(g.handle(.keyDown(0.3)) == .startHandsFree)
        #expect(g.handle(.keyUp(0.35)) == nil)
        #expect(g.isRecording)
        #expect(g.handle(.keyDown(5)) == .finishRecording)
        #expect(g.handle(.keyUp(5.1)) == nil)
    }

    @Test func slowSecondTapIsAFreshHold() {
        var g = RecordKeyGesture()
        _ = g.handle(.keyDown(0))
        _ = g.handle(.keyUp(0.1))
        #expect(g.handle(.keyDown(1)) == .startRecording)
    }

    @Test func escapeAndOtherKeysCancel() {
        var g = RecordKeyGesture()
        _ = g.handle(.keyDown(0))
        #expect(g.handle(.otherKey) == .cancelRecording)
        _ = g.handle(.keyUp(0.5))
        _ = g.handle(.keyDown(2))
        _ = g.handle(.keyUp(2.05))
        _ = g.handle(.keyDown(2.2))
        #expect(g.handle(.escape) == .cancelRecording)
    }

    @Test func handsFreeCanBeDisabled() {
        var g = RecordKeyGesture()
        g.handsFreeEnabled = false
        _ = g.handle(.keyDown(0))
        _ = g.handle(.keyUp(0.1))
        #expect(g.handle(.keyDown(0.3)) == .startRecording)
    }
}
