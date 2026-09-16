import SwiftUI

struct OnboardingWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            WorldBackground(world: .ember)
            HStack(spacing: 0) {
                Image("ObjectCapsule")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 556)
                    .offset(x: -20, y: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text("voicemode").font(.onest(40, .bold))
                    Text("Голосовой ввод для macOS. Распознаёт речь на этом Mac, без интернета.")
                        .font(.onest(15))
                        .foregroundStyle(.white.opacity(0.84))
                        .padding(.top, 12)
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(object: "ObjectKeycap", title: "Зажми fn", detail: "и говори в любом приложении")
                        FeatureRow(object: "ObjectTextcard", title: "Готовый текст", detail: "запятые, абзацы, списки")
                        FeatureRow(object: "ObjectLock", title: "Офлайн", detail: "голос не покидает Mac")
                    }
                    .padding(.top, 30)
                }
                .frame(width: 330, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.top, 40)

            VStack {
                Spacer()
                RoundActionButton(title: "Начать", world: .ember) {
                    model.finishOnboarding()
                    model.windows.showMain()
                }
                .padding(.bottom, 30)
            }
            VStack {
                Text("Шаг 1 из 8").font(.onest(13, .semibold)).foregroundStyle(.white.opacity(0.9)).padding(.top, 14)
                Spacer()
            }
        }
        .frame(width: 960, height: 640)
        .foregroundStyle(.white)
    }
}

private struct FeatureRow: View {
    let object: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(object).resizable().scaledToFit().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.onest(15, .semibold))
                Text(detail).font(.onest(13)).foregroundStyle(.white.opacity(0.74))
            }
        }
    }
}
