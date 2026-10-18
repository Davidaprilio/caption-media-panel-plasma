.pragma library

// Placeholder transcript used until a real transcript source exists.
// Each entry is [duration in ms, text].
const LINES = [
    [3000, "♪ Intro music ♪"],
    [3200, "Welcome back to the show."],
    [3600, "Today we are talking about desktop widgets on Linux."],
    [2800, "Why KDE Plasma?"],
    [4200, "Because everything can be customised, right down to the panel."],
    [3000, "This line is a dummy caption."],
    [5200, "Real captions will come later, from subtitle files, lyrics services or speech recognition running on this machine."],
    [2600, "For now, timing is what matters."],
    [3600, "Every line follows the position of the media player."],
    [3000, "Pause it, and the caption stops."],
    [3200, "Seek it, and the caption jumps."],
    [2400, "Pretty neat."],
    [4000, "Under the hood a single timer wakes up exactly at the next line."],
    [3600, "No polling, so the battery stays happy."],
    [3000, "♪ Short musical break ♪"],
    [3400, "Okay, back to the topic."],
    [4600, "This sentence is intentionally long, so that the marquee mode has something to scroll across the panel."],
    [2800, "Did you notice it?"],
    [3200, "In lyric mode, lines move up one by one."],
    [3600, "You can show between one and five lines at once."],
    [3800, "Click the widget to open the full transcript."],
    [3600, "Click a line in that list to seek the player there."],
    [2600, "That works for players that support seeking."],
    [3400, "Width can be automatic or set by hand."],
    [4200, "Automatic width uses the longest line, so the panel does not jitter."],
    [3000, "Almost done with this dummy text."],
    [2600, "Thanks for watching!"],
    [3200, "♪ Outro music ♪"],
];

const GAP_MS = 250;

// Duration of one pass through LINES.
const LOOP_MS = LINES.reduce((total, line) => total + line[0] + GAP_MS, 0);

function passesFor(coverMs) {
    return Math.max(1, Math.ceil(coverMs / LOOP_MS));
}

// Builds cues for the given number of passes through LINES.
function build(passes) {
    const cues = [];
    let t = 0;
    for (let p = 0; p < passes; ++p) {
        for (let i = 0; i < LINES.length; ++i) {
            const duration = LINES[i][0];
            cues.push({ start: t, end: t + duration, text: LINES[i][1] });
            t += duration + GAP_MS;
        }
    }
    return cues;
}
