import SwiftUI

struct HomeSection: View {
    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                ReadyTile()
                    .frame(width: 660, height: 360)
                VStack(spacing: 16) {
                    InfoTile(title: "Модель", value: "Whisper turbo", detail: "офлайн · 626 МБ", object: "ObjectChip")
                    InfoTile(title: "Словарь", value: "Терминов пока нет", detail: "добавятся из истории", object: "ObjectAa")
                }
                .frame(width: 392, height: 360)
            }
            GridRow {
                InfoTile(title: "История", value: "Пока пусто", detail: "зажми fn и скажи фразу", object: "ObjectStack")
                    .frame(width: 660, height: 292)
                InfoTile(title: "Текст", value: "Умная структура", detail: "списки и абзацы", object: "ObjectTextcard")
                    .frame(width: 392, height: 292)
            }
        }
    }
}

private struct ReadyTile: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("ObjectCapsule")
                .resizable()
                .scaledToFit()
                .frame(width: 520)
                .offset(x: 250, y: 90)
            VStack(alignment: .leading, spacing: 0) {
                Text("Готово к диктовке").font(.onest(15, .semibold))
                Text("Зажми fn")
                    .font(.onest(46, .bold))
                    .padding(.top, 30)
                Text("Плашка появится у выреза камеры")
                    .font(.onest(14))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 230, alignment: .leading)
                    .padding(.top, 8)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frost(cornerRadius: 22, hot: true)
    }
}

private struct InfoTile: View {
    let title: String
    let value: String
    let detail: String
    let object: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(object)
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 26, y: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.onest(15, .semibold))
                Spacer().frame(height: 30)
                Text(value).font(.onest(21, .semibold))
                Text(detail).font(.onest(13)).foregroundStyle(.white.opacity(0.74))
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frost(cornerRadius: 22)
    }
}
