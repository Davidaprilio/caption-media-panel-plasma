import QtQuick
import QtTest
import "../package/contents/ui"
import "../package/contents/code/cues.js" as Cues
import "../package/contents/code/dummyTranscript.js" as Dummy

TestCase {
    id: test
    name: "CueClock"
    when: windowShown

    readonly property var sample: [
        { start: 0, end: 300, text: "a" },
        { start: 400, end: 700, text: "b" },
        { start: 700, end: 1000, text: "c" },
    ]

    Component {
        id: clockComponent
        CueClock {}
    }

    SignalSpy {
        id: finishedSpy
        signalName: "finished"
    }

    function test_indexAt() {
        compare(Cues.indexAt(sample, -5), -1);
        compare(Cues.indexAt(sample, 0), 0);
        compare(Cues.indexAt(sample, 350), 0);
        compare(Cues.indexAt(sample, 400), 1);
        compare(Cues.indexAt(sample, 700), 2);
        compare(Cues.indexAt(sample, 5000), 2);
        compare(Cues.indexAt([], 10), -1);
    }

    function test_nextBoundary() {
        compare(Cues.nextBoundary(sample, -1, -5), 0);
        compare(Cues.nextBoundary(sample, 0, 100), 300);
        compare(Cues.nextBoundary(sample, 0, 350), 400);
        compare(Cues.nextBoundary(sample, 2, 800), 1000);
        compare(Cues.nextBoundary(sample, 2, 1200), -1);
    }

    function test_formatTime() {
        compare(Cues.formatTime(0), "0:00");
        compare(Cues.formatTime(65000), "1:05");
        compare(Cues.formatTime(3725000), "1:02:05");
    }

    function test_dummy() {
        const one = Dummy.build(1);
        verify(one.length > 20);
        compare(Dummy.build(3).length, one.length * 3);
        for (let i = 1; i < one.length; ++i) {
            verify(one[i].start >= one[i - 1].end, "cues must be sorted and not overlap");
        }
        compare(Dummy.passesFor(0), 1);
        compare(Dummy.passesFor(Dummy.LOOP_MS + 1), 2);
    }

    function test_pausedSync() {
        const clock = createTemporaryObject(clockComponent, test, { cues: sample });
        clock.sync(350);
        compare(clock.currentIndex, 0);
        compare(clock.active, false);
        clock.sync(500);
        compare(clock.currentIndex, 1);
        compare(clock.active, true);
        compare(clock.currentCue.text, "b");
        // Paused: the position does not move.
        wait(150);
        compare(clock.currentIndex, 1);
    }

    function test_playingAdvances() {
        const clock = createTemporaryObject(clockComponent, test, { cues: sample });
        clock.sync(200);
        clock.playing = true;
        compare(clock.currentIndex, 0);
        tryCompare(clock, "active", false, 400);   // passes end of "a" at 300
        tryCompare(clock, "currentIndex", 1, 400); // "b" starts at 400
        verify(clock.active);
        tryCompare(clock, "currentIndex", 2, 600);
    }

    function test_pauseFreezes() {
        const clock = createTemporaryObject(clockComponent, test, { cues: sample });
        clock.sync(0);
        clock.playing = true;
        wait(120);
        clock.playing = false;
        const frozen = clock.positionNow();
        verify(frozen >= 100 && frozen < 300, "frozen at " + frozen);
        wait(300);
        compare(clock.positionNow(), frozen);
        compare(clock.currentIndex, 0);
    }

    function test_rate() {
        const clock = createTemporaryObject(clockComponent, test, { cues: sample, rate: 4 });
        clock.sync(0);
        clock.playing = true;
        // 700 ms of media at 4x is ~175 ms of wall time.
        tryCompare(clock, "currentIndex", 2, 400);
    }

    function test_finished() {
        const clock = createTemporaryObject(clockComponent, test, { cues: sample });
        finishedSpy.target = clock;
        finishedSpy.clear();
        clock.sync(900);
        clock.playing = true;
        finishedSpy.wait(500);
        compare(clock.currentIndex, 2);
        compare(clock.active, false);
    }
}
