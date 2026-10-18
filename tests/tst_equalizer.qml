import QtQuick
import QtTest
import "../package/contents/ui"

TestCase {
    id: test
    name: "Equalizer"
    when: windowShown

    Component {
        id: equalizerComponent
        EqualizerBars {
            width: 200
            height: 60
            barCount: 10
        }
    }

    function bars(equalizer) {
        // The Repeater itself is a child too.
        return equalizer.children.filter(child => child.level !== undefined);
    }

    function levels(equalizer) {
        return bars(equalizer).map(bar => bar.level.toFixed(4)).join(",");
    }

    function test_restsWhenNotRunning() {
        const equalizer = createTemporaryObject(equalizerComponent, test);
        compare(bars(equalizer).length, 10);
        const before = levels(equalizer);
        wait(300);
        compare(levels(equalizer), before, "nothing moves while not running");
        for (const bar of bars(equalizer)) {
            compare(bar.level, equalizer.restLevel);
        }
    }

    function test_bouncesWhileRunningThenSettles() {
        const equalizer = createTemporaryObject(equalizerComponent, test);
        equalizer.running = true;
        wait(500);
        verify(bars(equalizer).some(bar => bar.level > 0.2), "bars move up while running");

        equalizer.running = false;
        // Every bar eases back to the rest level within its 400 ms, then stops.
        tryVerify(() => bars(equalizer).every(bar => Math.abs(bar.level - equalizer.restLevel) < 0.001), 1500);
        const settled = levels(equalizer);
        wait(300);
        compare(levels(equalizer), settled, "no animation keeps running after settling");
    }
}
