import QtQuick
import qs.Commons
import qs.Ui

// A grouped, scrollable scene selector for a single device.
// Scenes are grouped by base name (stripping -A/-B/-C suffixes).
// Groups with multiple variants are collapsible.
Item {
  id: root

  property var bar: null
  property var scenes: null          // ListModel with { name, value }
  property int activeScene: -1       // Currently active scene index, or -1
  property bool enabled: true

  signal scenePicked(int sceneValue)

  readonly property color fg: bar ? bar.foreground : "#ffffff"
  readonly property string fontFam: bar ? bar.fontFamily : ""

  // Built from the scenes ListModel — array of group objects:
  // { label, items: [{ name, value }], expanded }
  property var groups: []
  property int expandedGroup: -1  // Index of currently expanded group, -1 = none

  onScenesChanged: buildGroups()
  Component.onCompleted: buildGroups()

  // React to items being added to the scenes ListModel after it's assigned
  Connections {
    target: root.scenes
    function onCountChanged() { root.buildGroups() }
  }

  function buildGroups() {
    if (!scenes) { groups = []; return }
    var groupMap = {}
    var groupOrder = []
    for (var i = 0; i < scenes.count; i++) {
      var item = scenes.get(i)
      var label = groupLabel(item.name)
      if (!(label in groupMap)) {
        groupMap[label] = []
        groupOrder.push(label)
      }
      groupMap[label].push({ name: item.name, value: item.value })
    }
    var result = []
    for (var j = 0; j < groupOrder.length; j++) {
      var lbl = groupOrder[j]
      result.push({ label: lbl, items: groupMap[lbl] })
    }
    groups = result
    expandedGroup = -1
  }

  // Strip trailing -A, -B, -C, -D etc. to get the group label.
  function groupLabel(name) {
    var match = name.match(/^(.+?)[-\s]+[A-Z]$/)
    if (match) return match[1]
    return name
  }

  function isActiveInGroup(group) {
    if (activeScene < 0) return false
    for (var i = 0; i < group.items.length; i++) {
      if (group.items[i].value === activeScene) return true
    }
    return false
  }

  implicitHeight: groupColumn.implicitHeight

  Column {
    id: groupColumn
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: root.groups.length

      Column {
        id: groupDelegate
        required property int index
        readonly property var group: root.groups[index]
        readonly property bool isSingle: group.items.length === 1
        readonly property bool isExpanded: root.expandedGroup === index
        readonly property bool hasActive: root.isActiveInGroup(group)

        width: parent.width
        spacing: Style.space(3)

        // Group header / single-item button
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

            // Expand/collapse indicator for multi-item groups
            Text {
              visible: !groupDelegate.isSingle
              text: groupDelegate.isExpanded ? "\u{F0140}" : "\u{F0142}"  // chevron down/right
              color: Qt.darker(root.fg, 1.5)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: group.label
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

            // Variant count badge for multi-item groups
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
