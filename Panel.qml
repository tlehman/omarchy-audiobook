import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget + popup for omarchy-audiobook. Everything real happens in
// bin/omarchy-audiobook; this file only polls `status`, lists recent EPUBs,
// and hands clicks back to the CLI.
Panel {
  id: root
  moduleName: "omarchy-audiobook"
  ipcTarget: "omarchy-audiobook"

  // Qt.resolvedUrl gives a percent-encoded file:// URL; the CLI wants a path.
  readonly property string cli: {
    var raw = String(Qt.resolvedUrl("bin/omarchy-audiobook")).replace(/^file:\/\//, "")
    try { return decodeURIComponent(raw) } catch (e) { return raw }
  }

  property var jobs: []
  property var abs: ({ configured: false, running: false, url: "" })
  // The ebook2audiobook image: which one, whether it's downloaded, and what
  // (if anything) stops it from running — Docker missing, no GPU runtime.
  property var engine: ({ present: false, device: "", problem: null, message: null, pulling: null })
  property var epubs: []
  // How to sign in from Absorb: the tailnet address (if Tailscale Serve
  // fronts the server) and the generated username. Fetched on open.
  property var server: ({ managed: false, running: false, url: "", tailnet: null, username: "" })

  readonly property var activeJobs: jobs.filter(function(j) { return j.state === "converting" || j.state === "importing" || j.state === "queued" })
  readonly property var finishedJobs: jobs.filter(function(j) { return j.state === "done" || j.state === "failed" || j.state === "cancelled" }).slice(0, 3)
  readonly property var current: {
    for (var i = 0; i < jobs.length; i++)
      if (jobs[i].state === "converting" || jobs[i].state === "importing") return jobs[i]
    return null
  }
  readonly property int currentPercent: current ? Math.floor((current.progress || 0) * 100) : 0

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshEpubs() {
    if (!epubsProc.running) epubsProc.running = true
  }

  function run(args) {
    Quickshell.execDetached([root.cli].concat(args))
    refreshSoon.restart()
  }

  function formatDuration(sec) {
    if (sec === undefined || sec === null || !isFinite(sec)) return ""
    sec = Math.max(0, Math.round(sec))
    var h = Math.floor(sec / 3600)
    var m = Math.floor((sec % 3600) / 60)
    if (h > 0) return h + "h " + m + "m"
    if (m > 0) return m + "m"
    return sec + "s"
  }

  function jobValue(job) {
    if (job.state === "queued") return "QUEUED"
    if (job.state === "importing") return "IMPORTING"
    var text = Math.floor((job.progress || 0) * 100) + "%"
    if (String(job.phase || "").indexOf("Downloading") === 0) return text + " · DOWNLOADING ENGINE"
    if (job.eta !== undefined && job.eta !== null) text += " · " + formatDuration(job.eta) + " LEFT"
    else if (job.phase) text += " · " + String(job.phase).toUpperCase()
    return text
  }

  // Button has no elide, so keep labels short enough for the popup.
  function clip(text, max) {
    text = String(text || "")
    return text.length > max ? text.slice(0, max - 1) + "…" : text
  }

  function jobLabel(job) {
    var glyph = job.state === "done" ? "󰄬" : (job.state === "failed" ? "󰀦" : "󰜺")
    var text = glyph + "  " + clip(job.title, 34)
    if (job.state === "done" && job.author) text += " — " + clip(job.author, 18)
    if (job.state === "failed") text += " — failed"
    if (job.state === "cancelled") text += " — cancelled"
    return text
  }

  function openJob(job) {
    if (job.state === "failed" && job.problem)
      root.fixSetup()
    else if (job.state === "failed")
      Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", root.cli + " log " + job.id])
    else if (job.link)
      Quickshell.execDetached(["xdg-open", job.link])
    root.close()
  }

  // Docker, the GPU runtime and the docker group need sudo, so repairs run
  // in a terminal where they can prompt.
  function fixSetup() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", root.cli + " doctor --fix"])
    root.close()
  }

  onOpenedChanged: if (opened) { refresh(); refreshEpubs(); if (!serverProc.running) serverProc.running = true }
  Component.onCompleted: {
    // Puts the CLI on PATH and registers Open With, so a plain
    // `omarchy plugin add` install needs no extra step.
    Quickshell.execDetached([root.cli, "_integrate"])
    refresh()
  }

  // Fast while something is happening or the popup is up, lazy otherwise.
  Timer {
    interval: (root.opened || root.activeJobs.length > 0 || root.engine.pulling) ? 2000 : 20000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshSoon
    interval: 600
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: [root.cli, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.jobs = data.jobs || []
          root.abs = data.abs || root.abs
          root.engine = data.engine || root.engine
        } catch (e) {
          console.warn("omarchy-audiobook: bad status JSON:", e)
        }
      }
    }
  }

  Process {
    id: serverProc
    command: [root.cli, "server", "info"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.server = JSON.parse(String(text || "{}")) } catch (e) { }
      }
    }
  }

  Process {
    id: epubsProc
    command: [root.cli, "epubs", "5"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.epubs = JSON.parse(String(text || "[]")) } catch (e) { root.epubs = [] }
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.current ? "󰋋 " + root.currentPercent + "%" : "󰋋"
    slotSize: root.current ? Style.bar.iconSlot * 2 : Style.bar.iconSlot
    tooltipText: root.current
      ? root.current.title + " · " + root.jobValue(root.current).toLowerCase()
      : (root.activeJobs.length > 0 ? root.activeJobs.length + " queued" : "Convert an EPUB to an audiobook")
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(860))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          title: "Audiobooks"
          meta: (root.current
                 ? root.current.phase || "Converting"
                 : (root.activeJobs.length > 0 ? "Queued" : "Idle")).toUpperCase()
                + " · " + (root.engine.device === "cpu" ? "CPU" : "GPU")
                + " · " + (root.abs.running ? "AUDIOBOOKSHELF UP" : "AUDIOBOOKSHELF DOWN")
          iconComponent: Text {
            text: "󰋋"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }
        }

        // ---------- Engine: needs fixing, or downloading on its own ----------
        Button {
          visible: !!root.engine.problem
          width: parent.width
          leftAlign: true
          iconText: "󰀦"
          text: (root.engine.message || "Setup needed") + " — fix"
          tooltipText: "Opens a terminal; installing needs your password"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.fixSetup()
        }

        MeterRow {
          visible: !!root.engine.pulling && root.activeJobs.length === 0
          width: parent.width
          label: "Downloading ebook2audiobook"
          fraction: root.engine.pulling && root.engine.pulling.total > 0 ? root.engine.pulling.done / root.engine.pulling.total : 0
          valueText: root.engine.pulling
            ? (root.engine.pulling.done / 1e9).toFixed(1) + " / " + (root.engine.pulling.total / 1e9).toFixed(1) + " GB"
            : ""
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        // ---------- Setup nudge: deep links need an API key ----------
        Button {
          visible: root.abs.running && !root.abs.configured
          width: parent.width
          leftAlign: true
          iconText: "󰌆"
          text: "Add Audiobookshelf API key for direct links"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: {
            Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", root.cli + " setup"])
            root.close()
          }
        }

        // ---------- In progress ----------
        PanelSeparator {
          visible: root.activeJobs.length > 0
          foreground: root.bar.foreground
        }

        Repeater {
          model: root.activeJobs

          Item {
            required property var modelData
            width: panelColumn.width
            implicitHeight: meter.implicitHeight

            MeterRow {
              id: meter
              anchors.left: parent.left
              anchors.right: cancelButton.left
              anchors.rightMargin: Style.space(8)
              label: modelData.title
              fraction: modelData.progress || 0
              valueText: root.jobValue(modelData)
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            PanelActionButton {
              id: cancelButton
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              iconText: "󰅖"
              tooltipText: "Cancel"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.run(["cancel", modelData.id])
            }
          }
        }

        // ---------- Recently finished ----------
        PanelSeparator {
          visible: root.finishedJobs.length > 0
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          visible: root.finishedJobs.length > 0
          text: "RECENT"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Repeater {
          model: root.finishedJobs

          Button {
            required property var modelData
            width: panelColumn.width
            leftAlign: true
            text: root.jobLabel(modelData)
            tooltipText: modelData.state === "failed" ? (modelData.error || "Show log") : (modelData.output || "")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.openJob(modelData)
          }
        }

        // ---------- Convert ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          text: "CONVERT AN EPUB"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Text {
          visible: root.epubs.length === 0
          width: parent.width
          wrapMode: Text.WordWrap
          text: "No EPUBs found in Downloads, Documents or Books. Right-click any EPUB in Files → Open With → Convert to Audiobook."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.epubs

          Button {
            required property var modelData
            width: panelColumn.width
            leftAlign: true
            iconText: "󰂺"
            text: root.clip(modelData.name, 50)
            tooltipText: modelData.path
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.run(["convert", modelData.path])
          }
        }

        // ---------- Sign in from Absorb (or any Audiobookshelf app) ----------
        PanelSeparator {
          visible: root.server.managed
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          visible: root.server.managed
          text: "LISTEN ON YOUR PHONE"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Text {
          visible: root.server.managed
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.server.tailnet
            ? "In Absorb, add server " + root.server.tailnet + " and sign in as " + root.server.username + "."
            : "The server only listens on this PC. To reach it from Absorb, share port 13378 with Tailscale Serve (see README)."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          visible: root.server.managed && !!root.server.tailnet
          spacing: Style.space(8)

          Button {
            iconText: "󰆏"
            text: "Copy server"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: Quickshell.execDetached(["wl-copy", root.server.tailnet || ""])
          }

          Button {
            iconText: "󰌆"
            text: "Copy password"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: Quickshell.execDetached([root.cli, "server", "copy-password"])
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Row {
          spacing: Style.space(8)

          Button {
            iconText: "󰏌"
            text: "Audiobookshelf"
            enabled: root.abs.running
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: {
              Quickshell.execDetached(["xdg-open", root.abs.url + "/audiobookshelf/"])
              root.close()
            }
          }

          Button {
            iconText: "󰉋"
            text: "Browse…"
            tooltipText: "Right-click an EPUB → Open With → Convert to Audiobook"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: {
              Quickshell.execDetached(["uwsm-app", "--", "nautilus", "--new-window", Quickshell.env("HOME") + "/Downloads"])
              root.close()
            }
          }

          Button {
            visible: root.finishedJobs.length > 0
            iconText: "󰃢"
            text: "Clear"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.run(["clear"])
          }
        }

        Item {
          width: parent.width
          height: Style.space(2)
        }
      }
    }
  }

  component MeterRow: Column {
    id: meterRow
    property string label: ""
    property real fraction: 0
    property string valueText: ""
    property color foreground: Color.foreground
    property string fontFamily: ""

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(meterHeader.implicitHeight, meterValue.implicitHeight)

      Text {
        id: meterHeader
        text: meterRow.label
        color: meterRow.foreground
        font.family: meterRow.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: meterValue.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: meterValue
        text: meterRow.valueText
        color: Qt.darker(meterRow.foreground, 1.4)
        font.family: meterRow.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    CursorSurface {
      width: parent.width
      height: Style.space(14)
      bordered: true
      foreground: meterRow.foreground
      radius: Style.cornerRadius

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(3)
        width: Math.max(radius, (parent.width - Style.space(6)) * Math.max(0, Math.min(1, meterRow.fraction)))
        radius: Math.max(1, Style.cornerRadius - Style.space(2))
        color: Color.accent
        Behavior on width { NumberAnimation { duration: 250 } }
      }
    }
  }
}
