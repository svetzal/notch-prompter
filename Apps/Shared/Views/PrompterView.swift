import NotchPrompterKit
import SwiftUI

/// The prompter: the notch grown downwards, with the script inside it.
///
/// The panel is pure black and clipped to a ``NotchShape``, so it merges
/// with the hardware notch in light and dark mode alike. The text starts
/// just under the camera housing, at the placement's top inset, and the
/// reading line sits half a line below that, as close to the lens as the
/// panel allows. The line being read is at full strength and the rest are
/// dimmed. The view only draws: the position for each frame comes from the
/// Kit's scroll engine, evaluated at the frame's timestamp.
struct PrompterView: View {

    let controller: PrompterController

    private var isAnimating: Bool {
        switch controller.session.phase {
        case .countingDown, .live: true
        default: false
        }
    }

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            frame(at: context.date)
        }
        // The placement already leaves room for the notch; do not let the
        // system's safe area push the text down a second time.
        .ignoresSafeArea()
    }

    private func frame(at date: Date) -> some View {
        let session = controller.session
        let settings = controller.settings
        let topInset = controller.placement?.topInset ?? PrompterPlacement.topInsetWithoutNotch
        return ZStack(alignment: .top) {
            if let remaining = session.countdownRemaining(at: date) {
                Text("\(remaining)")
                    .font(.system(size: settings.fontSize * 2, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PrompterLines(layout: session.scroll.layout, position: session.position(at: date), settings: settings)
            }
        }
        .padding(.top, topInset)
        .padding(.bottom, PrompterSettings.bottomPadding)
        .padding(.horizontal, PrompterPlacement.earRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            PrompterStatus(session: session, settings: settings, date: date)
                .padding(.trailing, PrompterPlacement.earRadius + PrompterPlacement.bottomCornerRadius / 2)
                .padding(.bottom, 4)
        }
        .background(Color.black)
        .clipShape(
            NotchShape(
                topCornerRadius: PrompterPlacement.earRadius,
                bottomCornerRadius: PrompterPlacement.bottomCornerRadius
            )
        )
    }
}

/// The visible window of lines, offset smoothly by the fractional position.
private struct PrompterLines: View {

    let layout: PrompterLayout
    let position: Double
    let settings: PrompterSettings

    var body: some View {
        let lineHeight = settings.lineHeight
        let current = Int(position.rounded(.down))
        let first = max(0, current - 1)
        let last = min(layout.lines.count, current + settings.visibleLines + 2)
        ZStack(alignment: .topLeading) {
            ForEach(first..<max(first, last), id: \.self) { index in
                PrompterLineView(line: layout.lines[index], isCurrent: index == current, fontSize: settings.fontSize)
                    .frame(width: settings.textWidth, height: lineHeight, alignment: .leading)
                    .offset(y: (Double(index) - position + 0.5) * lineHeight)
            }
            if current >= layout.lines.count - 1 {
                Text(layout.lines.isEmpty ? "No script" : "End")
                    .font(.system(size: settings.fontSize * 0.6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: settings.textWidth, height: lineHeight)
                    .offset(y: (Double(layout.lines.count) - position + 0.5) * lineHeight)
            }
        }
        .frame(width: settings.textWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }
}

private struct PrompterLineView: View {

    let line: PrompterLine
    let isCurrent: Bool
    let fontSize: Double

    var body: some View {
        content
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .opacity(isCurrent ? 1 : 0.45)
            .overlay(alignment: .leading) {
                if line.startsBlock, line.kind == .speech {
                    Circle()
                        .fill(.white.opacity(0.35))
                        .frame(width: 5, height: 5)
                        .offset(x: -10)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch line.kind {
        case .speech:
            Text(line.text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white)
        case .note:
            Text(line.text)
                .font(.system(size: fontSize, weight: .semibold).italic())
                .foregroundStyle(.yellow)
        case .pause(let seconds):
            Label("Pause \(seconds.formatted(.number.precision(.fractionLength(0...1))))s", systemImage: "pause.circle")
                .font(.system(size: fontSize * 0.7, weight: .medium))
                .foregroundStyle(.cyan)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Speed, play state, and the take timer, small in the corner.
private struct PrompterStatus: View {

    let session: TakeSession
    let settings: PrompterSettings
    let date: Date

    var body: some View {
        HStack(spacing: 8) {
            if session.isRecording {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text(ElapsedTime.format(session.elapsed(at: date) ?? 0))
            }
            if case .live = session.phase, !session.scroll.isPlaying {
                Text("Paused")
            }
            Text("\(Int(settings.wordsPerMinute)) wpm")
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
    }
}
