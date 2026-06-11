import Foundation

/// The first-run welcome script (#31): a guided tour that exercises every
/// piece of script syntax so new users hear each feature working before
/// they read any documentation. Scripts have no comment syntax, so the
/// narration explains itself out loud.
enum SampleScript {
    static let text = """
    # Welcome to Kokoro Studio
    This sample script is a guided tour. Press command return to generate \
    it, then listen along.
    The line above starts with a hash sign, so it reads as a heading and \
    gets a longer pause after it.
    You can ask for a deliberate beat anywhere. [pause:800] That silence \
    came from an inline pause marker.
    Words wrapped in asterisks get *gentle emphasis*, with a breath on \
    either side.
    @Maya: A line that starts with an at-sign and a name becomes dialogue.
    @Sam: Open Speakers in the sidebar to give each of us a different \
    voice and speed.
    The pronunciation dictionary controls acronyms: NASA can read as a \
    word, while APA spells out letter by letter.
    One-off fixes go right in the text, like the name {Roush|rowsh}.
    Numbers and symbols read naturally: $5.50, 25%, and version v1.2.
    ## file: splitting-demo
    A line of two hash signs, the word file, and a colon splits a long \
    script into separate audio files on export.
    That is the whole tour. Select all, delete, and paste in your own \
    script.
    """
}
