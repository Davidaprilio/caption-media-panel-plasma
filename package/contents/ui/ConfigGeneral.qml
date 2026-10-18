import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_displayMode: displayMode.currentIndex
    property alias cfg_textAlignment: textAlignment.currentIndex
    property alias cfg_visibleLines: visibleLines.value
    property int cfg_widthMode
    property alias cfg_manualWidth: manualWidth.value
    property alias cfg_maxAutoWidth: maxAutoWidth.value
    property alias cfg_fontSize: fontSize.value
    property alias cfg_animationDuration: animationDuration.value
    property alias cfg_marqueeSpeed: marqueeSpeed.value
    property alias cfg_demoWhenIdle: demoWhenIdle.checked
    property alias cfg_dummyForOtherMedia: dummyForOtherMedia.checked
    property alias cfg_lrclibEnabled: lrclibEnabled.checked

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: displayMode
            Kirigami.FormData.label: i18n("Display mode:")
            model: [i18n("Lyric (lines move up)"), i18n("Marquee (next line waits on the right)")]
        }

        QQC2.ComboBox {
            id: textAlignment
            Kirigami.FormData.label: i18n("Text alignment:")
            model: [i18n("Left"), i18n("Center"), i18n("Right")]
        }

        QQC2.SpinBox {
            id: visibleLines
            Kirigami.FormData.label: i18n("Visible lines:")
            enabled: displayMode.currentIndex === 0
            from: 1
            to: 5
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.RadioButton {
            id: autoWidth
            Kirigami.FormData.label: i18n("Width:")
            text: i18n("Automatic (fits the longest line)")
            checked: page.cfg_widthMode === 0
            onToggled: page.cfg_widthMode = 0
        }
        RowLayout {
            QQC2.RadioButton {
                id: fixedWidth
                text: i18n("Fixed:")
                checked: page.cfg_widthMode === 1
                onToggled: page.cfg_widthMode = 1
            }
            QQC2.SpinBox {
                id: manualWidth
                enabled: fixedWidth.checked
                from: 60
                to: 2000
                stepSize: 10
            }
            QQC2.Label {
                text: i18nc("pixels", "px")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Maximum automatic width:")
            enabled: autoWidth.checked
            QQC2.SpinBox {
                id: maxAutoWidth
                from: 100
                to: 2000
                stepSize: 10
            }
            QQC2.Label {
                text: i18nc("pixels", "px")
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Font size:")
            QQC2.SpinBox {
                id: fontSize
                from: 0
                to: 48
                textFromValue: (value, locale) => value === 0 ? i18n("Theme") : Number(value).toLocaleString(locale, "f", 0)
                valueFromText: (text, locale) => text === i18n("Theme") ? 0 : Number.fromLocaleString(locale, text)
            }
            QQC2.Label {
                text: i18nc("font points", "pt")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Line animation:")
            QQC2.SpinBox {
                id: animationDuration
                from: 0
                to: 1000
                stepSize: 50
            }
            QQC2.Label {
                text: i18nc("milliseconds", "ms")
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Marquee speed:")
            enabled: displayMode.currentIndex === 1
            QQC2.SpinBox {
                id: marqueeSpeed
                from: 10
                to: 400
                stepSize: 10
            }
            QQC2.Label {
                text: i18nc("pixels per second", "px/s")
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: lrclibEnabled
            Kirigami.FormData.label: i18n("Sources:")
            text: i18n("Synced lyrics from LRCLIB for Spotify")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: dummyForOtherMedia
            Kirigami.FormData.label: i18n("Testing:")
            text: i18n("Show the dummy transcript for media without captions (non-YouTube)")
        }
        QQC2.CheckBox {
            id: demoWhenIdle
            text: i18n("Play the dummy transcript when no player is running")
        }
    }
}
