import InnerTube
import SwiftUI

private struct SecondaryPillLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.rwButton)
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, Metrics.space16)
            .frame(height: Metrics.pillHeight)
            .background(.surfaceFill, in: Capsule())
            .fixedSize()
    }
}

struct ArtistHeader: View {
    let model: EntityModel
    let artist: ArtistPage
    let isSubscribed: Bool?
    let width: CGFloat
    let inset: CGFloat

    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.requestSignIn) private var requestSignIn
    @State private var isSubscribePromptShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space16) {
            hero
            actions.padding(.horizontal, inset)
        }
    }

    private var hero: some View {
        ArtworkImage(url: artist.thumbnailURL, width: width, height: Metrics.artistHeroHeight, cornerRadius: 0)
            .overlay(alignment: .bottomLeading) {
                Text(artist.name)
                    .font(.rwDisplay)
                    .foregroundStyle(.textPrimary)
                    .padding(Metrics.space24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .themeBase], startPoint: .top, endPoint: .bottom))
                    .accessibilityAddTraits(.isHeader)
            }
    }

    private var actions: some View {
        HStack(spacing: Metrics.space12) {
            if let shuffle = artist.shuffle {
                Button { nowPlaying.play(shuffle) } label: { InversePillLabel(title: "Shuffle") }
                    .buttonStyle(.plain)
            }
            if let radio = artist.radio {
                Button { nowPlaying.play(radio) } label: { SecondaryPillLabel(title: "Radio") }
                    .buttonStyle(.plain)
            }
            if let isSubscribed {
                Button {
                    if nowPlaying.isSignedIn { model.toggleSubscribed() } else { isSubscribePromptShown = true }
                } label: {
                    if isSubscribed { SecondaryPillLabel(title: "Subscribed") } else { InversePillLabel(title: "Subscribe") }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSubscribed ? .isSelected : [])
                .guestPrompt(isPresented: $isSubscribePromptShown, reason: "Sign in to subscribe", onSignIn: requestSignIn.perform)
                if let count = artist.subscriberCountText {
                    Text(count).font(.rwCaption).foregroundStyle(.textSecondary)
                }
            }
            Spacer(minLength: 0)
            ShareButtons(url: model.shareURL)
        }
    }
}

struct ArtistAbout: View {
    let artist: ArtistPage

    var body: some View {
        if artist.description != nil || artist.viewCountText != nil {
            VStack(alignment: .leading, spacing: Metrics.space12) {
                Text("About")
                    .font(.rwShelfTitle)
                    .foregroundStyle(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let description = artist.description, !description.isEmpty { ExpandableText(text: description) }
                if let views = artist.viewCountText {
                    Text(views).font(.rwBody).foregroundStyle(.textSecondary)
                }
            }
        }
    }
}
