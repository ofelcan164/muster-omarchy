#!/usr/bin/env python3
"""Loads the widget's real QML headless and runs Harness.qml against it.

Quickshell and Omarchy's qs.* modules only exist inside omarchy-shell, so
stubs/ stands in for them with the same properties, signals and functions.
What this catches is everything in this repo's QML: a typo in a property, a
binding that throws or assigns the wrong type, a broken import, a key or
click wired to the wrong thing. Any QML warning fails the run, as does any
failed check.

Needs PySide6 (pip install PySide6-Essentials). Run from anywhere:

    python3 tests/qml/run.py
"""

import datetime
import json
import os
import pathlib
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
PLUGIN = HERE.parent.parent
FIXTURE = HERE.parent / "fixtures" / "snapshot.json"

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"

try:
    from PySide6.QtCore import QObject, QTimer, QUrl, Slot, qInstallMessageHandler
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
except ImportError as e:
    # Skipped rather than failed: the node tests need nothing but node, and
    # this one needs a Qt install. Say which part is missing.
    print(f"skipped: PySide6 did not load ({e}). pip install PySide6-Essentials")
    sys.exit(0)


class Files(QObject):
    """Writes a file for the harness, the way musterd does: a new file
    renamed over the old one."""

    @Slot(str, str)
    def write(self, path, text):
        tmp = pathlib.Path(path + ".tmp")
        tmp.write_text(text)
        tmp.replace(path)


def rfc3339(t):
    """Go's time.Time JSON form, nanoseconds and all."""
    return t.strftime("%Y-%m-%dT%H:%M:%S.%f") + "123Z"


def snapshot(generated, edit=None):
    raw = json.loads(FIXTURE.read_text())
    raw["generated_at"] = rfc3339(generated)
    if edit:
        edit(raw)
    return json.dumps(raw)


def main():
    now = datetime.datetime.now(datetime.timezone.utc)
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="muster-omarchy-qml-"))
    dirs = {name: tmp / name for name in ["fresh", "stale", "missing", "newer", "broken"]}
    for d in dirs.values():
        d.mkdir()

    (dirs["fresh"] / "snapshot.json").write_text(snapshot(now))
    (dirs["fresh"] / "ui.json").write_text(json.dumps({
        "sort": 1,
        "dismissed": {"w1:p2": "blocked"},
        "colors": {"acme/api": 0},
    }))
    (dirs["stale"] / "snapshot.json").write_text(snapshot(now - datetime.timedelta(minutes=5)))
    (dirs["newer"] / "snapshot.json").write_text(
        snapshot(now, lambda r: r.__setitem__("snapshot_version", 2)))
    (dirs["broken"] / "snapshot.json").write_text("{not json")
    quiet = snapshot(now, lambda r: r.__setitem__("attention", []))

    app = QGuiApplication(sys.argv)
    engine = QQmlEngine()
    engine.addImportPath(str(HERE / "stubs"))
    engine.setOutputWarningsToStandardError(False)

    problems = []
    done = []

    def on_message(mode, context, message):
        if message.startswith("DONE "):
            done.append(message)
            print(message)
        elif message.startswith("FAIL: "):
            problems.append(message)
            print(message)
        else:
            problems.append("qml: " + message)
            print("qml: " + message)

    def on_warnings(warnings):
        for w in warnings:
            problems.append("warning: " + w.toString())
            print("warning: " + w.toString())

    qInstallMessageHandler(on_message)
    engine.warnings.connect(on_warnings)

    ctx = engine.rootContext()
    ctx.setContextProperty("pluginDir", str(PLUGIN))
    ctx.setContextProperty("dirs", {k: str(v) for k, v in dirs.items()})
    ctx.setContextProperty("testEnv", {"HOME": str(tmp / "home")})
    ctx.setContextProperty("fixtureQuiet", quiet)
    files = Files()
    ctx.setContextProperty("files", files)

    component = QQmlComponent(engine, QUrl.fromLocalFile(str(HERE / "Harness.qml")))
    harness = component.create()
    if harness is None:
        for e in component.errors():
            print("error: " + e.toString())
        return 1

    def poll():
        if done:
            app.quit()

    ticker = QTimer()
    ticker.timeout.connect(poll)
    ticker.start(50)
    QTimer.singleShot(20000, app.quit)
    app.exec()

    if not done:
        problems.append("the harness never finished")
        print("the harness never finished")
    if problems:
        print(f"{len(problems)} problem(s)")
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
