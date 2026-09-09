import json
from pathlib import Path
import unittest


PLUGIN_DIR = Path(__file__).resolve().parents[1]


class ManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads((PLUGIN_DIR / "manifest.json").read_text(encoding="utf-8"))

    def test_identity_and_entry_points(self) -> None:
        self.assertEqual(self.manifest["id"], "io.github.erikburdett.wavebar")
        self.assertEqual(self.manifest["name"], "WaveBar: Waveform Media Controller")
        self.assertEqual(set(self.manifest["kinds"]), {"service", "bar-widget"})
        self.assertEqual(self.manifest["entryPoints"]["service"], "Service.qml")
        self.assertEqual(self.manifest["entryPoints"]["barWidget"], "BarWidget.qml")

    def test_widget_defaults_match_schema(self) -> None:
        widget = self.manifest["barWidget"]
        defaults = widget["defaults"]
        schema = {field["key"]: field for field in widget["schema"]}
        self.assertEqual(set(defaults), set(schema))
        for key, value in defaults.items():
            self.assertEqual(schema[key]["defaultValue"], value)

        self.assertEqual(schema["waveformWidth"]["min"], 40)
        self.assertEqual(schema["waveformWidth"]["max"], 240)
        self.assertEqual(schema["maxTitleWidth"]["min"], 60)
        self.assertEqual(schema["maxTitleWidth"]["max"], 320)

    def test_preview_and_license_are_packaged(self) -> None:
        self.assertTrue((PLUGIN_DIR / "preview.png").is_file())
        self.assertTrue((PLUGIN_DIR / "LICENSE").is_file())
        self.assertTrue((PLUGIN_DIR / "CHANGELOG.md").is_file())

    def test_service_uses_installed_source_and_one_stream_match(self) -> None:
        service = (PLUGIN_DIR / "Service.qml").read_text(encoding="utf-8")
        self.assertIn("manifest.__sourceDir", service)
        self.assertNotIn(
            '"/.config/omarchy/plugins/io.github.erikburdett.wavebar/waveform.py"',
            service,
        )
        self.assertEqual(service.count("MediaModel.chooseVolumeNode("), 1)
        self.assertNotIn("MediaModel.chooseCapture(", service)
        self.assertIn("!root.fatalHelperError", service)
        self.assertIn("exitCode === 127", service)
        self.assertIn("clearEnvironment: true", service)
        self.assertIn(
            "visualizer.environment = sanitizedVisualizerEnvironment()", service
        )
        self.assertIn('"PATH": "/usr/bin"', service)
        self.assertIn(
            "visualizer.exited.connect(root.handleVisualizerExited)", service
        )
        self.assertNotIn("onExited:", service)

    def test_service_owns_media_state_and_panel_saves_settings(self) -> None:
        # Omarchy 4.0 scopes the shell handed to third-party plugins: the
        # first-party media service is null for bar-widget plugins and
        # mutateShellConfig is refused. Both must stay out of this plugin.
        service = (PLUGIN_DIR / "Service.qml").read_text(encoding="utf-8")
        self.assertIn("import Quickshell.Services.Mpris", service)
        self.assertIn("import Quickshell.Services.Pipewire", service)
        self.assertIn("PwObjectTracker { objects: root.playbackStreams }", service)
        self.assertNotIn("firstPartyServiceFor(", service)
        self.assertNotIn("mediaService", service)
        self.assertIn("MediaModel.syncPlayOrder(", service)
        self.assertIn("function onIsPlayingChanged() { root.syncPlayers() }", service)

        panel = (PLUGIN_DIR / "Panel.qml").read_text(encoding="utf-8")
        self.assertIn("shell.updateEntryInline(root.moduleName", panel)
        self.assertNotIn("mutateShellConfig", panel)

    def test_version_has_changelog_entry(self) -> None:
        changelog = (PLUGIN_DIR / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertIn(f"## {self.manifest['version']} ", changelog)

    def test_widget_keeps_runtime_bounds_and_vertical_layout(self) -> None:
        widget = (PLUGIN_DIR / "BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn("Math.min(240", widget)
        self.assertIn("Math.min(320", widget)
        self.assertIn("width: parent.height", widget)
        self.assertIn("height: parent.width", widget)
        self.assertIn("visible: root.showControls", widget)

    def test_repeater_delegates_have_bound_component_behavior(self) -> None:
        for filename in ("Panel.qml", "Waveform.qml", "Service.qml"):
            source = (PLUGIN_DIR / filename).read_text(encoding="utf-8")
            self.assertTrue(source.startswith("pragma ComponentBehavior: Bound\n"))


if __name__ == "__main__":
    unittest.main()
