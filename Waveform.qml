pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  property var samples: []
  property int barCount: 18
  property bool active: false
  property bool live: false
  property color foreground: "white"
  property real gap: 2
  property real minimumBarHeight: 2

  implicitWidth: 72
  implicitHeight: 20

  function sampleAt(index) {
    if (!samples || samples.length === 0 || !live) return active ? 0.08 : 0.03
    var sourceIndex = Math.min(samples.length - 1,
      Math.floor(index * samples.length / Math.max(1, barCount)))
    return Math.max(0, Math.min(1, Number(samples[sourceIndex]) || 0))
  }

  Repeater {
    model: root.barCount

    Rectangle {
      required property int index
      readonly property real level: root.sampleAt(index)
      readonly property real slotWidth: root.width / Math.max(1, root.barCount)

      x: index * slotWidth + root.gap / 2
      width: Math.max(1, slotWidth - root.gap)
      height: Math.max(root.minimumBarHeight, Math.round(root.height * (0.08 + level * 0.92)))
      y: Math.round((root.height - height) / 2)
      radius: width / 2
      color: root.foreground
      opacity: root.live ? 0.95 : (root.active ? 0.48 : 0.28)

      Behavior on height {
        NumberAnimation { duration: 72; easing.type: Easing.OutQuad }
      }
      Behavior on opacity { NumberAnimation { duration: 140 } }
    }
  }
}
