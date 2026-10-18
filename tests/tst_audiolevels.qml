import QtQuick
import QtTest
import "../package/contents/ui"

TestCase {
    id: test
    name: "AudioLevels"

    readonly property string fakeCava: decodeURIComponent(Qt.resolvedUrl("fake_cava.py").toString().replace(/^file:\/\//, ""))

    Component {
        id: levelsComponent
        AudioLevels {
            // Away from the widget's port, so a running widget doesn't interfere.
            port: 47299
        }
    }

    function test_streamsLevelsWhileActive() {
        const audio = createTemporaryObject(levelsComponent, test, { cava: fakeCava });
        compare(audio.levels, null);
        audio.active = true;
        tryVerify(() => audio.levels !== null, 5000, "levels arrive from the bridge");
        compare(audio.levels.length, 20);
        compare(audio.levels[0], 0);
        compare(audio.levels[10], 0.5);
        compare(audio.levels[19], 0.95);

        audio.active = false;
        compare(audio.levels, null, "levels are dropped when inactive");
        // The bridge exits by itself once nobody listens; give it time before the next test.
        wait(2500);
    }

    function test_missingCavaFallsBack() {
        const audio = createTemporaryObject(levelsComponent, test, { cava: "no-such-cava-binary" });
        audio.active = true;
        tryCompare(audio, "available", false, 5000);
        compare(audio.levels, null);
    }
}
