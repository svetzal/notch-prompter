/// The script written into a new, empty scripts folder.
///
/// It doubles as a demonstration of the cue syntax, so a first-time user sees
/// pauses and notes working before reading any documentation.
public enum SampleScript {

    public static let fileName = "Welcome.md"

    public static let markdown = """
    # Welcome

    Hi. This is Notch Prompter. Your script scrolls right under the camera, so
    your eyes stay close to the lens while you read.

    [note: Smile, and look at the camera between lines.]

    Write each thought as its own paragraph. The left arrow jumps back a
    paragraph if you stumble, and the right arrow skips ahead.

    [pause 2]

    Press space to pause or resume. Use plus and minus to change the speed,
    and the up and down arrows to nudge the text by a line.

    <!-- Comments like this one never reach the prompter. -->

    When you are ready, press Record. After a short countdown, the prompter
    and the recording start together. Press escape to stop.

    Thanks for watching.
    """
}
