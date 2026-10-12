import NotchPrompterKit
import SwiftUI

/// The text under the camera.
///
/// The reading line sits half a line below the top edge, as close to the
/// lens as the panel allows. The line being read is at full strength and the
/// rest are dimmed. The view only draws: the position for each frame comes
/// from the Kit's scroll engine, evaluated at the frame's timestamp.
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
    }

    private func frame(at date: Date) -> some View {
        let session = controller.session
        let settings = controller.settings
        return ZStack(alignment: .top) {
            Color.black
            if let remaining = session.countdownRemaining(at: date) {
                Text("\(remaining)")
                    .font(.system(size: settings.fontSize * 2, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PrompterLines(layout: session.scroll.layout, position: session.position(at: date), settings: settings)
                    .padding(.vertical, PrompterSettings.verticalPadding)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            PrompterStatus(session: session, settings: settings, date: date)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
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
