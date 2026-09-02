import QtQuick

Item {
  id: root

  property string text: ""
  property color foreground: "white"
  property string fontFamily: ""
  property real fontPixelSize: 14
  property bool fontBold: false
  property bool active: true
  property int pauseDuration: 1100
  property real millisecondsPerPixel: 28

  readonly property bool needsScroll: label.implicitWidth > width

  clip: true
  implicitWidth: label.implicitWidth
  implicitHeight: label.implicitHeight

  Text {
    id: label
    x: 0
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.text
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontPixelSize
    font.bold: root.fontBold
  }

  SequentialAnimation {
    id: scrollAnimation
    running: root.active && root.visible && root.needsScroll
    loops: Animation.Infinite

    PauseAnimation { duration: root.pauseDuration }

    NumberAnimation {
      target: label
      property: "x"
      from: 0
      to: Math.min(0, root.width - label.implicitWidth)
      duration: Math.max(1800,
        Math.round(Math.abs(label.implicitWidth - root.width) * root.millisecondsPerPixel))
      easing.type: Easing.Linear
    }

    PauseAnimation { duration: root.pauseDuration }

    NumberAnimation {
      target: label
      property: "x"
      from: Math.min(0, root.width - label.implicitWidth)
      to: 0
      duration: Math.max(1800,
        Math.round(Math.abs(label.implicitWidth - root.width) * root.millisecondsPerPixel))
      easing.type: Easing.Linear
    }

    PauseAnimation { duration: root.pauseDuration }

    onStopped: label.x = 0
  }
}
