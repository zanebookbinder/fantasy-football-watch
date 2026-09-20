import SwiftUI

/// Tells whoever opens this on their phone where the app actually lives.
struct CompanionView: View {
    private let steps = [
        "Open the Watch app on this iPhone.",
        "Scroll to Fantasy Football Watch and turn on Show App on Apple Watch.",
        "Open it on your watch and pick your team.",
    ]

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "applewatch")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Fantasy Football Watch")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Your live matchup, on your wrist.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(.tint, in: Circle())
                        Text(step)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14))

            Text("There is nothing to do here — the app runs on the watch.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(24)
    }
}

#if DEBUG
#Preview {
    CompanionView()
}
#endif
