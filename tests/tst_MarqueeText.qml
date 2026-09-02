import QtQuick
import QtTest
import ".."

TestCase {
  id: testCase
  name: "MarqueeText"

  Component {
    id: marqueeComponent
    MarqueeText { active: false }
  }

  function test_shortTitleStaysStill() {
    var item = createTemporaryObject(marqueeComponent, testCase, {
      width: 300,
      text: "Short title"
    })
    verify(item)
    verify(!item.needsScroll)
    verify(item.clip)
  }

  function test_longTitleNeedsScrollInsideClip() {
    var item = createTemporaryObject(marqueeComponent, testCase, {
      width: 60,
      text: "A deliberately long media title that cannot fit"
    })
    verify(item)
    verify(item.needsScroll)
    verify(item.implicitWidth > item.width)
    verify(item.clip)
  }
}
