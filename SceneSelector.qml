import QtQuick
import qs.Commons
import qs.Ui

// A categorized, grouped scene selector.
// Level 1: Category tabs (Nature, Music, Gaming, etc.)
// Level 2: Scene groups within the active category (collapsible)
// Level 3: Variant pills within a group (Action-A, Action-B, etc.)
Item {
  id: root

  property var bar: null
  property var scenes: null          // ListModel with { name, value }
  property int activeScene: -1       // Currently active scene index, or -1

  signal scenePicked(int sceneValue)

  readonly property color fg: bar ? bar.foreground : "#ffffff"
  readonly property string fontFam: bar ? bar.fontFamily : ""

  // Categorized structure: [ { label, groups: [ { label, items: [{name, value}] } ] } ]
  property var categories: []
  property int activeCategory: 0
  property int expandedGroup: -1

  // Rebuild categories when:
  // 1. The scenes property itself changes (different model assigned)
  // 2. On initial creation (model may already be populated)
  // 3. When items are added/removed from the current model (ListModel mutations
  //    don't trigger onScenesChanged since the object reference is unchanged)
  onScenesChanged: buildCategories()
  Component.onCompleted: buildCategories()

  Connections {
    target: root.scenes
    function onCountChanged() { root.buildCategories() }
  }

  // ─── Category keyword definitions ──────────────────────────────────────

  readonly property var categoryDefs: [
    { label: "Nature", keywords: ["sunrise", "sunset", "rainbow", "ocean", "forest", "aurora", "waterfall", "river", "volcano", "desert", "sand", "spring wind", "fall", "snow", "rain", "lightning", "wave", "firefly", "fire", "sailboat", "karst cave", "undersea", "sunny", "rustling", "sky", "summer", "winter", "ripple", "deep sea", "glacier", "moonlight", "cornfield", "flower field", "cherry", "blossom", "petal", "downpour", "cloud", "morning", "afternoon", "leaf", "water drop", "fish tank"] },
    { label: "Mood", keywords: ["meditation", "quiet", "leisure", "healing", "breathe", "night", "dreamland", "accompany", "care", "refreshing", "cheerful", "happy", "fascination", "romance", "candy", "strawberry", "love", "marshmallow", "calm", "cozy", "warm", "candlelight", "gentle", "soft", "dream"] },
    { label: "Music", keywords: ["dance party", "dancing", "electro dance", "latin dance", "tango", "waltz", "ballet", "jazz", "swing", "pole dance", "rock", "pop", "rhythm", "disco"] },
    { label: "Gaming", keywords: ["game", "racing", "cards game", "puzzle", "fight", "action", "poker", "shoot", "crossing", "stacking"] },
    { label: "Party", keywords: ["party", "fireworks", "carnival", "neon", "energetic", "birthday"] },
    { label: "Holiday", keywords: ["christmas", "halloween", "easter", "valentine", "thanksgiving", "new year", "father", "mother", "st. patrick", "ghost"] },
    { label: "Cinema", keywords: ["science fiction", "war films", "suspense", "horror", "comedy", "tension", "rivalry", "dracarys", "green reign", "fire & blood"] },
    { label: "Space", keywords: ["venus", "earth", "mars", "jupiter", "uranus", "milky way", "universe", "star", "meteor"] },
    { label: "Dynamic", keywords: ["gradient", "gleam", "drift", "graffiti", "train", "candy crush", "flow", "spin", "portal", "zdp", "breaking", "streak", "flicker"] }
  ]

  function buildCategories() {
    if (!scenes || scenes.count === 0) { categories = []; return }

    // Assign each scene to a category
    var catMap = {}  // category label -> [ { name, value } ]
    for (var i = 0; i < categoryDefs.length; i++)
      catMap[categoryDefs[i].label] = []
    catMap["Other"] = []

    for (var s = 0; s < scenes.count; s++) {
      var item = scenes.get(s)
      var bn = baseName(item.name).toLowerCase()
      var assigned = false
      for (var c = 0; c < categoryDefs.length; c++) {
        var kws = categoryDefs[c].keywords
        for (var k = 0; k < kws.length; k++) {
          if (bn.indexOf(kws[k]) >= 0) {
            catMap[categoryDefs[c].label].push({ name: item.name, value: item.value })
            assigned = true
            break
          }
        }
        if (assigned) break
      }
      if (!assigned) catMap["Other"].push({ name: item.name, value: item.value })
    }

    // Build final categories with groups inside each
    var result = []
    for (var ci = 0; ci < categoryDefs.length; ci++) {
      var label = categoryDefs[ci].label
      var items = catMap[label]
      if (items.length > 0)
        result.push({ label: label, groups: buildGroups(items), count: items.length })
    }
    if (catMap["Other"].length > 0)
      result.push({ label: "Other", groups: buildGroups(catMap["Other"]), count: catMap["Other"].length })

    categories = result
    activeCategory = 0
    expandedGroup = -1
  }

  function buildGroups(items) {
    var groupMap = {}
    var groupOrder = []
    for (var i = 0; i < items.length; i++) {
      var label = groupLabel(items[i].name)
      if (!(label in groupMap)) {
        groupMap[label] = []
        groupOrder.push(label)
      }
      groupMap[label].push(items[i])
    }
    var result = []
    for (var j = 0; j < groupOrder.length; j++) {
      var lbl = groupOrder[j]
      result.push({ label: lbl, items: groupMap[lbl] })
    }
    return result
  }

  function baseName(name) {
    // Normalize non-breaking spaces
    name = name.replace(/\u00a0/g, " ")
    var match = name.match(/^(.+?)[-\s]+[A-Z]$/)
    if (match) return match[1]
    return name
  }

  function groupLabel(name) {
    return baseName(name)
  }

  function isActiveInGroup(group) {
    if (activeScene < 0) return false
    for (var i = 0; i < group.items.length; i++) {
      if (group.items[i].value === activeScene) return true
    }
    return false
  }

  readonly property var activeGroups: categories.length > activeCategory ? categories[activeCategory].groups : []

  implicitHeight: mainColumn.implicitHeight

  Column {
    id: mainColumn
    width: parent.width
    spacing: Style.space(8)

    // ── Category tabs ──
    Flow {
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: root.categories.length

        Rectangle {
          required property int index
          readonly property var cat: root.categories[index]

          width: catTabText.implicitWidth + Style.space(14)
          height: Style.space(26)
          radius: height / 2
          color: {
            if (index === root.activeCategory)
              return Color.accent
            if (catTabArea.containsMouse)
              return Style.hoverFillFor(root.fg, Color.accent)
            return Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
          }

          Behavior on color { ColorAnimation { duration: 100 } }

          Text {
            id: catTabText
            anchors.centerIn: parent
            text: cat.label + " (" + cat.count + ")"
            textFormat: Text.PlainText
            color: index === root.activeCategory ? "#ffffff" : root.fg
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
            font.bold: index === root.activeCategory
          }

          MouseArea {
            id: catTabArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.activeCategory = index
              root.expandedGroup = -1
            }
          }
        }
      }
    }

    // ── Divider ──
    Rectangle {
      width: parent.width
      height: 1
      color: root.fg
      opacity: 0.08
    }

    // ── Groups within active category ──
    Column {
      width: parent.width
      spacing: Style.space(3)

      Repeater {
        model: root.activeGroups.length

        Column {
          id: groupDelegate
          required property int index
          readonly property var group: root.activeGroups[index]
          readonly property bool isSingle: group.items.length === 1
          readonly property bool isExpanded: root.expandedGroup === index
          readonly property bool hasActive: root.isActiveInGroup(group)

          width: parent.width
          spacing: Style.space(3)

          // Group header
          Rectangle {
            width: parent.width
            height: Style.space(28)
            radius: Style.space(4)
            color: {
              if (groupDelegate.isSingle && group.items[0].value === root.activeScene)
                return Color.accent
              if (groupDelegate.hasActive && !groupDelegate.isExpanded)
                return Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
              if (headerArea.containsMouse && root.enabled)
                return Style.hoverFillFor(root.fg, Color.accent)
              return Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
            }

            Behavior on color { ColorAnimation { duration: 100 } }

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                visible: !groupDelegate.isSingle
                text: groupDelegate.isExpanded ? "\u{F0140}" : "\u{F0142}"
                color: Qt.darker(root.fg, 1.5)
                font.family: root.fontFam
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: group.label
                textFormat: Text.PlainText
                color: {
                  if (groupDelegate.isSingle && group.items[0].value === root.activeScene)
                    return "#ffffff"
                  return root.fg
                }
                font.family: root.fontFam
                font.pixelSize: Style.font.bodySmall
                font.bold: groupDelegate.hasActive
                anchors.verticalCenter: parent.verticalCenter
              }

              Rectangle {
                visible: !groupDelegate.isSingle
                width: countText.implicitWidth + Style.space(8)
                height: Style.space(16)
                radius: height / 2
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: countText
                  anchors.centerIn: parent
                  text: group.items.length
                  color: Qt.darker(root.fg, 1.4)
                  font.family: root.fontFam
                  font.pixelSize: Style.font.caption
                }
              }
            }

            MouseArea {
              id: headerArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              enabled: root.enabled
              onClicked: {
                if (groupDelegate.isSingle) {
                  root.scenePicked(group.items[0].value)
                } else {
                  root.expandedGroup = groupDelegate.isExpanded ? -1 : index
                }
              }
            }
          }

          // Expanded variant pills
          Flow {
            visible: groupDelegate.isExpanded && !groupDelegate.isSingle
            width: parent.width
            leftPadding: Style.space(20)
            spacing: Style.space(5)

            Repeater {
              model: groupDelegate.isExpanded ? group.items.length : 0

              Rectangle {
                required property int index
                readonly property var sceneItem: group.items[index]

                width: variantText.implicitWidth + Style.space(12)
                height: Style.space(22)
                radius: height / 2
                color: {
                  if (sceneItem.value === root.activeScene)
                    return Color.accent
                  if (variantArea.containsMouse && root.enabled)
                    return Style.hoverFillFor(root.fg, Color.accent)
                  return Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                }

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                  id: variantText
                  anchors.centerIn: parent
                  text: sceneItem.name
                  textFormat: Text.PlainText
                  color: sceneItem.value === root.activeScene ? "#ffffff" : root.fg
                  font.family: root.fontFam
                  font.pixelSize: Style.font.caption
                  font.bold: sceneItem.value === root.activeScene
                }

                MouseArea {
                  id: variantArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  enabled: root.enabled
                  onClicked: root.scenePicked(sceneItem.value)
                }
              }
            }
          }
        }
      }
    }
  }
}
