#!/usr/bin/env python3
"""
Ein simulierter Valetudo-Roboter zum Testen von VacuPilot ohne echte Hardware.

Startet einen HTTP-Server, der sich wie ein Roboter mit allen Fähigkeiten
verhält — inklusive Karte mit Räumen, Bodenbelägen (auch Teppich),
Sperrzonen und Karten-Markierungen (Türschwelle, Vorhang, Rampe).

Änderungen werden im Speicher gehalten: Wer einen Raum umbenennt, einen
Bodenbelag setzt oder eine Markierung zeichnet, sieht das Ergebnis danach
auch in der Karte. Beim Neustart ist alles wieder auf Anfang.

Aufruf:  python3 fake_robot.py [--port 8080] [--host 0.0.0.0]
Beenden: Strg-C
"""

import argparse
import json
import math
import re
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

START_TIME = time.time()

# ---------------------------------------------------------------------------
# Karte
# ---------------------------------------------------------------------------

PIXEL_SIZE = 5          # cm pro Kartenpixel
MAP_W, MAP_H = 200, 160  # Kartengröße in Pixeln

# Räume: (id, Name, x0, y0, x1, y1) in Kartenpixeln, plus Bodenbelag
ROOM_DEFS = [
    ("1", "Wohnzimmer",  10, 10,  95,  75, "wood_horizontal"),
    ("2", "Küche",       100, 10, 190,  60, "tile"),
    ("3", "Schlafzimmer", 10, 82,  95, 150, "carpet"),
    ("4", "Bad",         100, 66, 145, 110, "tile"),
    ("5", "Flur",        150, 66, 190, 150, "carpet_high"),
    ("6", "Büro",        100, 116, 145, 150, "carpet_low"),
]


def compress_pixels(pixels):
    """Wandelt [x,y,x,y,...] in die Lauflängenkodierung [xStart,y,count,...]."""
    out = []
    i = 0
    while i < len(pixels):
        x, y = pixels[i], pixels[i + 1]
        count = 1
        j = i + 2
        while j < len(pixels) and pixels[j + 1] == y and pixels[j] == x + count:
            count += 1
            j += 2
        out.extend([x, y, count])
        i = j
    return out


def rect_pixels(x0, y0, x1, y1):
    px = []
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px.extend([x, y])
    return px


def make_layer(layer_type, pixels, meta=None):
    xs = pixels[0::2]
    ys = pixels[1::2]
    return {
        "__class": "MapLayer",
        "type": layer_type,
        "compressedPixels": compress_pixels(pixels),
        "metaData": {
            **(meta or {}),
            "area": (len(pixels) // 2) * PIXEL_SIZE * PIXEL_SIZE,
        },
        "dimensions": {
            "x": {"min": min(xs), "max": max(xs), "mid": (min(xs) + max(xs)) // 2},
            "y": {"min": min(ys), "max": max(ys), "mid": (min(ys) + max(ys)) // 2},
            "pixelCount": len(pixels) // 2,
        },
    }


def wall_pixels():
    """Umrandung um jeden Raum, damit die Karte nach Wänden aussieht."""
    px = set()
    for _id, _name, x0, y0, x1, y1, _mat in ROOM_DEFS:
        for x in range(x0 - 1, x1 + 2):
            px.add((x, y0 - 1))
            px.add((x, y1 + 1))
        for y in range(y0 - 1, y1 + 2):
            px.add((x0 - 1, y))
            px.add((x1 + 1, y))
    flat = []
    for x, y in sorted(px, key=lambda p: (p[1], p[0])):
        if 0 <= x < MAP_W and 0 <= y < MAP_H:
            flat.extend([x, y])
    return flat


class RobotState:
    """Alles, was sich zur Laufzeit ändern kann."""

    def __init__(self):
        self.lock = threading.Lock()
        self.status = "docked"          # docked, cleaning, paused, returning, error
        self.battery = 87
        self.fan_speed = "medium"
        self.water_grade = "low"
        self.operation_mode = "vacuum_and_mop"
        self.rooms = {
            rid: {"name": name, "material": mat}
            for rid, name, _x0, _y0, _x1, _y1, mat in ROOM_DEFS
        }
        self.robot_pos = (52, 40)
        self.robot_angle = 90
        self.path = []
        # Sperrzonen im Format der App (cm-Koordinaten)
        self.virtual_walls = [
            {"points": {"pA": {"x": 480, "y": 400}, "pB": {"x": 480, "y": 560}}},
        ]
        self.no_go_areas = [
            {"points": {
                "pA": {"x": 700, "y": 640}, "pB": {"x": 800, "y": 640},
                "pC": {"x": 800, "y": 740}, "pD": {"x": 700, "y": 740}}},
        ]
        self.no_mop_areas = []
        # Karten-Markierungen: Liste von {"type": ..., "points": [{"x","y"}, ...]}
        self.annotations = [
            {"type": "threshold", "points": [{"x": 480, "y": 300}, {"x": 480, "y": 360}]},
            {"type": "curtain", "points": [{"x": 750, "y": 100}, {"x": 900, "y": 100}]},
            {"type": "ramp", "points": [
                {"x": 520, "y": 600}, {"x": 620, "y": 600},
                {"x": 620, "y": 680}, {"x": 520, "y": 680}]},
        ]
        self.consumables = [
            {"type": "brush", "subType": "main", "remaining": {"value": 260, "unit": "minutes"}},
            {"type": "brush", "subType": "side_right", "remaining": {"value": 120, "unit": "minutes"}},
            {"type": "filter", "subType": "main", "remaining": {"value": 90, "unit": "minutes"}},
            {"type": "sensor", "subType": "all", "remaining": {"value": 25, "unit": "minutes"}},
            {"type": "mop", "subType": "main", "remaining": {"value": 60, "unit": "minutes"}},
        ]
        self.timers = {}
        self.settings = {
            "CarpetModeControlCapability": {"enabled": True},
            "PersistentMapControlCapability": {"enabled": True},
            "KeyLockCapability": {"enabled": False},
            "ObstacleAvoidanceControlCapability": {"enabled": True},
            "PetObstacleAvoidanceControlCapability": {"enabled": False},
            "CollisionAvoidantNavigationControlCapability": {"enabled": True},
            "FloorMaterialDirectionAwareNavigationControlCapability": {"enabled": True},
            "AutoEmptyDockAutoEmptyControlCapability": {"enabled": True},
            "MopDockMopAutoDryingControlCapability": {"enabled": True},
        }
        self.presets = {
            "CarpetSensorModeControlCapability": "lift",
            "OperationModeControlCapability": "vacuum_and_mop",
            "CleanRouteControlCapability": "standard",
            "SpeakerVolumeControlCapability": "medium",
            "AutoEmptyDockAutoEmptyIntervalControlCapability": "normal",
            "AutoEmptyDockAutoEmptyDurationControlCapability": "normal",
            "MopDockMopDryingTimeControlCapability": "two_hours",
            "MopDockMopWashTemperatureControlCapability": "warm",
        }
        self.updater = {
            "__class": "ValetudoUpdaterIdleState",
            "busy": False,
            "currentVersion": "2026.08.0",
            "version": None,
            "releaseTimestamp": None,
            "downloadUrl": None,
            "downloadPath": None,
            "metaData": None,
        }
        self._sim_thread = threading.Thread(target=self._simulate, daemon=True)
        self._sim_thread.start()

    def _simulate(self):
        """Lässt den Roboter beim Reinigen fahren und den Akku sinken."""
        angle = 0.0
        while True:
            time.sleep(1.0)
            with self.lock:
                if self.status == "cleaning":
                    angle += 0.25
                    cx, cy = 52, 40
                    x = int(cx + 28 * math.cos(angle))
                    y = int(cy + 20 * math.sin(angle))
                    self.robot_pos = (x, y)
                    self.robot_angle = int((math.degrees(angle) + 90) % 360)
                    self.path.extend([x * PIXEL_SIZE, y * PIXEL_SIZE])
                    self.path = self.path[-400:]
                    if self.battery > 5:
                        self.battery -= 0.15
                elif self.status == "docked" and self.battery < 100:
                    self.battery = min(100, self.battery + 0.4)

    # -- Karte -------------------------------------------------------------

    def build_map(self):
        with self.lock:
            layers = []
            floor = []
            for _id, _n, x0, y0, x1, y1, _m in ROOM_DEFS:
                floor.extend(rect_pixels(x0, y0, x1, y1))
            layers.append(make_layer("floor", floor))

            for rid, _name, x0, y0, x1, y1, _mat in ROOM_DEFS:
                room = self.rooms[rid]
                layers.append(make_layer(
                    "segment",
                    rect_pixels(x0, y0, x1, y1),
                    {"segmentId": rid, "name": room["name"],
                     "active": False, "material": room["material"]},
                ))

            walls = wall_pixels()
            if walls:
                layers.append(make_layer("wall", walls))

            entities = [
                {"__class": "PointMapEntity", "type": "charger_location",
                 "points": [15 * PIXEL_SIZE, 15 * PIXEL_SIZE], "metaData": {}},
                {"__class": "PointMapEntity", "type": "robot_position",
                 "points": [self.robot_pos[0] * PIXEL_SIZE, self.robot_pos[1] * PIXEL_SIZE],
                 "metaData": {"angle": self.robot_angle}},
            ]
            if self.path:
                entities.append({"__class": "PathMapEntity", "type": "path",
                                 "points": list(self.path), "metaData": {}})

            # Sperrzonen erscheinen auch als Karten-Entitäten
            for w in self.virtual_walls:
                p = w["points"]
                entities.append({"__class": "LineMapEntity", "type": "virtual_wall",
                                 "points": [p["pA"]["x"], p["pA"]["y"], p["pB"]["x"], p["pB"]["y"]],
                                 "metaData": {}})
            for z, kind in ([(z, "no_go_area") for z in self.no_go_areas] +
                            [(z, "no_mop_area") for z in self.no_mop_areas]):
                p = z["points"]
                entities.append({"__class": "PolygonMapEntity", "type": kind,
                                 "points": [p["pA"]["x"], p["pA"]["y"], p["pB"]["x"], p["pB"]["y"],
                                            p["pC"]["x"], p["pC"]["y"], p["pD"]["x"], p["pD"]["y"]],
                                 "metaData": {}})

            # Markierungen: flaches Zahlen-Array, wie die echte Firmware liefert
            for a in self.annotations:
                flat = []
                for pt in a["points"]:
                    flat.extend([pt["x"], pt["y"]])
                cls = "PolygonMapEntity" if a["type"] == "ramp" else "LineMapEntity"
                entities.append({"__class": cls, "type": a["type"],
                                 "points": flat, "metaData": {}})

            return {
                "__class": "ValetudoMap",
                "metaData": {"version": 2, "nonce": str(int(time.time() * 1000))},
                "size": {"x": MAP_W * PIXEL_SIZE, "y": MAP_H * PIXEL_SIZE},
                "pixelSize": PIXEL_SIZE,
                "layers": layers,
                "entities": entities,
            }

    def attributes(self):
        with self.lock:
            return [
                {"__class": "StatusStateAttribute", "type": self.status, "flag": "none"},
                {"__class": "BatteryStateAttribute", "type": "none",
                 "level": int(self.battery),
                 "flag": "charging" if self.status == "docked" and self.battery < 100 else "none"},
                {"__class": "PresetSelectionStateAttribute", "type": "fan_speed",
                 "value": self.fan_speed},
                {"__class": "PresetSelectionStateAttribute", "type": "water_grade",
                 "value": self.water_grade},
                {"__class": "PresetSelectionStateAttribute", "type": "operation_mode",
                 "value": self.operation_mode},
                {"__class": "AttachmentStateAttribute", "type": "dustbin", "attached": True},
                {"__class": "AttachmentStateAttribute", "type": "watertank", "attached": True},
                {"__class": "AttachmentStateAttribute", "type": "mop", "attached": True},
            ]


STATE = RobotState()

CAPABILITIES = [
    "AutoEmptyDockAutoEmptyControlCapability",
    "AutoEmptyDockAutoEmptyDurationControlCapability",
    "AutoEmptyDockAutoEmptyIntervalControlCapability",
    "AutoEmptyDockManualTriggerCapability",
    "BasicControlCapability",
    "CarpetModeControlCapability",
    "CarpetSensorModeControlCapability",
    "CleanRouteControlCapability",
    "CollisionAvoidantNavigationControlCapability",
    "CombinedVirtualRestrictionsCapability",
    "ConsumableMonitoringCapability",
    "CurrentStatisticsCapability",
    "DoNotDisturbCapability",
    "FanSpeedControlCapability",
    "FloorMaterialDirectionAwareNavigationControlCapability",
    "GoToLocationCapability",
    "HighResolutionManualControlCapability",
    "KeyLockCapability",
    "LocateCapability",
    "ManualControlCapability",
    "MapAnnotationsCapability",
    "MapResetCapability",
    "MapSegmentEditCapability",
    "MapSegmentMaterialControlCapability",
    "MapSegmentRenameCapability",
    "MapSegmentationCapability",
    "MapSnapshotCapability",
    "MappingPassCapability",
    "MopDockCleanManualTriggerCapability",
    "MopDockDryManualTriggerCapability",
    "MopDockMopAutoDryingControlCapability",
    "MopDockMopDryingTimeControlCapability",
    "MopDockMopWashTemperatureControlCapability",
    "ObstacleAvoidanceControlCapability",
    "OperationModeControlCapability",
    "PersistentMapControlCapability",
    "PetObstacleAvoidanceControlCapability",
    "QuirksCapability",
    "SpeakerTestCapability",
    "SpeakerVolumeControlCapability",
    "TotalStatisticsCapability",
    "WaterUsageControlCapability",
    "WifiConfigurationCapability",
    "ZoneCleaningCapability",
]

PRESET_LISTS = {
    "FanSpeedControlCapability": ["off", "low", "medium", "high", "max"],
    "WaterUsageControlCapability": ["off", "low", "medium", "high"],
    "OperationModeControlCapability": ["vacuum", "mop", "vacuum_and_mop"],
    "CarpetSensorModeControlCapability": ["off", "avoid", "lift"],
    "CleanRouteControlCapability": ["standard", "intensive", "deep"],
    "SpeakerVolumeControlCapability": ["off", "low", "medium", "high", "max"],
    "AutoEmptyDockAutoEmptyIntervalControlCapability": ["frequent", "normal", "infrequent"],
    "AutoEmptyDockAutoEmptyDurationControlCapability": ["short", "normal", "long"],
    "MopDockMopDryingTimeControlCapability": ["two_hours", "three_hours", "four_hours"],
    "MopDockMopWashTemperatureControlCapability": ["cold", "warm", "hot"],
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print(f"  {self.command:6s} {self.path}")

    # -- Hilfsmittel -------------------------------------------------------

    def _send(self, obj, code=200):
        body = json.dumps(obj).encode() if obj is not None else b""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Valetudo-Version", "2026.08.0")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            return {}

    def _path(self):
        p = self.path.split("?")[0]
        return p[len("/api/v2"):] if p.startswith("/api/v2") else p

    # -- GET ---------------------------------------------------------------

    def do_GET(self):
        p = self._path()

        if p.endswith("/sse"):
            return self._sse(p)

        routes = {
            "/robot": {"manufacturer": "Simulation", "modelName": "Testroboter",
                       "implementation": "FakeValetudoRobot"},
            "/robot/capabilities": CAPABILITIES,
            "/robot/properties": {
                "firmwareVersion": "2026.08.0", "model": "Testroboter",
                "manufacturer": "Simulation",
                "metaData": {"manufacturerSerialNumber": "SIM-0001"}},
            "/robot/state/attributes": STATE.attributes(),
            "/robot/state/map": STATE.build_map(),
            "/valetudo/version": {"release": "2026.08.0", "commit": "simulated"},
            "/valetudo/events": [],
            "/valetudo/config/interfaces/mqtt": {"enabled": False},
            "/ntpclient/config": {"enabled": True, "server": "pool.ntp.org",
                                  "port": 123, "interval": 3600000, "timeout": 10000},
            "/ntpclient/status": {"__class": "ValetudoNTPClientSyncedState",
                                  "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
                                  "offset": 12},
            "/system/host/info": {
                "hostname": "simulierter-roboter", "arch": "aarch64",
                "mem": {"total": 512000000, "free": 210000000,
                        "valetudo_current": 48000000, "valetudo_max": 62000000},
                "uptime": time.time() - START_TIME,
                "load": {"1": 0.15, "5": 0.2, "15": 0.18}},
            "/updater/state": STATE.updater,
            "/timers": STATE.timers,
        }
        if p in routes:
            return self._send(routes[p])

        if p == "/robot/capabilities/MapSegmentationCapability":
            with STATE.lock:
                return self._send([{"id": rid, "name": r["name"]}
                                   for rid, r in STATE.rooms.items()])

        if p == "/robot/capabilities/MapAnnotationsCapability/properties":
            return self._send({"supportedAnnotationTypes": ["threshold", "curtain", "ramp"]})

        if p == "/robot/capabilities/MapSegmentMaterialControlCapability/properties":
            return self._send({"supportedMaterials": [
                "generic", "tile", "wood_horizontal", "wood_vertical",
                "carpet", "carpet_low", "carpet_high"]})

        if p == "/robot/capabilities/ConsumableMonitoringCapability":
            with STATE.lock:
                return self._send(STATE.consumables)

        if p == "/robot/capabilities/CombinedVirtualRestrictionsCapability":
            with STATE.lock:
                return self._send({
                    "virtualWalls": STATE.virtual_walls,
                    "restrictedZones": STATE.no_go_areas,
                    "noMopZones": STATE.no_mop_areas})

        if p == "/robot/capabilities/CombinedVirtualRestrictionsCapability/properties":
            return self._send({"supportedRestrictedZoneTypes": ["regular", "mop"]})

        if p in ("/robot/capabilities/CurrentStatisticsCapability",
                 "/robot/capabilities/TotalStatisticsCapability"):
            factor = 1 if "Current" in p else 240
            return self._send([
                {"__class": "ValetudoDataPoint", "type": "time", "value": 1820 * factor},
                {"__class": "ValetudoDataPoint", "type": "area", "value": 42000000 * factor},
                {"__class": "ValetudoDataPoint", "type": "count", "value": 1 * factor}])

        if p == "/robot/capabilities/DoNotDisturbCapability":
            return self._send({"enabled": False,
                               "start": {"hour": 22, "minute": 0},
                               "end": {"hour": 8, "minute": 0}})

        if p == "/robot/capabilities/MapSnapshotCapability":
            return self._send([])

        if p == "/robot/capabilities/QuirksCapability":
            return self._send([])

        if p == "/robot/capabilities/WifiConfigurationCapability":
            return self._send({"details": {"state": "connected", "downspeed": 72,
                                           "signal": -48, "ips": ["192.168.0.123"]},
                               "ssid": "Simulation"})

        # presets/<Capability>
        m = re.match(r"^/robot/capabilities/(\w+)/presets$", p)
        if m and m.group(1) in PRESET_LISTS:
            return self._send(PRESET_LISTS[m.group(1)])

        # Ein/Aus-Fähigkeiten
        m = re.match(r"^/robot/capabilities/(\w+)$", p)
        if m:
            cap = m.group(1)
            with STATE.lock:
                if cap in STATE.settings:
                    return self._send(STATE.settings[cap])
                if cap in STATE.presets:
                    return self._send({"name": STATE.presets[cap]})
            if cap in CAPABILITIES:
                return self._send({})

        self._send({"error": "not found", "path": p}, 404)

    # -- PUT ---------------------------------------------------------------

    def do_PUT(self):
        p = self._path()
        body = self._read_body()

        if p == "/robot/capabilities/BasicControlCapability":
            action = body.get("action")
            with STATE.lock:
                STATE.status = {"start": "cleaning", "stop": "docked",
                                "pause": "paused", "home": "returning"}.get(action, STATE.status)
                if action == "home":
                    STATE.path = []
            if action == "home":
                threading.Timer(4.0, self._dock).start()
            return self._send(None, 200)

        if p == "/robot/capabilities/MapAnnotationsCapability":
            if not isinstance(body, list):
                return self._send({"error": "expected an array"}, 400)
            cleaned = []
            for a in body:
                t = a.get("type")
                pts = a.get("points") or []
                if t not in ("threshold", "curtain", "ramp"):
                    return self._send({"error": f"unsupported type {t}"}, 400)
                need = 4 if t == "ramp" else 2
                if len(pts) != need:
                    return self._send({"error": f"{t} needs {need} points"}, 400)
                cleaned.append({"type": t, "points": [
                    {"x": int(pt["x"]), "y": int(pt["y"])} for pt in pts]})
            with STATE.lock:
                STATE.annotations = cleaned
            print(f"    -> Markierungen jetzt: {len(cleaned)}")
            return self._send(None, 200)

        if p == "/robot/capabilities/CombinedVirtualRestrictionsCapability":
            with STATE.lock:
                STATE.virtual_walls = body.get("virtualWalls", [])
                zones = body.get("restrictedZones", [])
                STATE.no_go_areas = [z for z in zones if z.get("type") != "mop"]
                STATE.no_mop_areas = [z for z in zones if z.get("type") == "mop"]
            return self._send(None, 200)

        if p == "/robot/capabilities/MapSegmentMaterialControlCapability":
            sid, mat = body.get("segmentId"), body.get("material")
            with STATE.lock:
                if sid in STATE.rooms:
                    STATE.rooms[sid]["material"] = mat
            print(f"    -> Raum {sid}: Belag = {mat}")
            return self._send(None, 200)

        if p == "/robot/capabilities/MapSegmentRenameCapability":
            sid, name = body.get("segmentId"), body.get("name")
            with STATE.lock:
                if sid in STATE.rooms:
                    STATE.rooms[sid]["name"] = name
            return self._send(None, 200)

        if p == "/robot/capabilities/MapSegmentationCapability":
            with STATE.lock:
                STATE.status = "cleaning"
            return self._send(None, 200)

        if p in ("/robot/capabilities/ZoneCleaningCapability",
                 "/robot/capabilities/GoToLocationCapability",
                 "/robot/capabilities/MappingPassCapability"):
            with STATE.lock:
                STATE.status = "cleaning"
            return self._send(None, 200)

        if p == "/updater":
            return self._send(None, 200)

        # Presets: {"name": "..."}
        m = re.match(r"^/robot/capabilities/(\w+)/preset$", p) or \
            re.match(r"^/robot/capabilities/(\w+)$", p)
        if m:
            cap = m.group(1)
            with STATE.lock:
                if "name" in body:
                    if cap == "FanSpeedControlCapability":
                        STATE.fan_speed = body["name"]
                    elif cap == "WaterUsageControlCapability":
                        STATE.water_grade = body["name"]
                    elif cap == "OperationModeControlCapability":
                        STATE.operation_mode = body["name"]
                    STATE.presets[cap] = body["name"]
                elif body.get("action") in ("enable", "disable"):
                    STATE.settings.setdefault(cap, {})["enabled"] = body["action"] == "enable"
                elif "enabled" in body:
                    STATE.settings.setdefault(cap, {})["enabled"] = bool(body["enabled"])
            return self._send(None, 200)

        self._send(None, 200)

    def do_POST(self):
        self.do_PUT()

    def do_DELETE(self):
        self._send(None, 200)

    def _dock(self):
        with STATE.lock:
            STATE.status = "docked"

    # -- Ereignisstrom -----------------------------------------------------

    def _sse(self, path):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        is_map = "map" in path
        try:
            while True:
                payload = STATE.build_map() if is_map else STATE.attributes()
                name = "MapUpdated" if is_map else "StateAttributesUpdated"
                chunk = f"event: {name}\ndata: {json.dumps(payload)}\n\n".encode()
                self.wfile.write(chunk)
                self.wfile.flush()
                time.sleep(2)
        except (BrokenPipeError, ConnectionResetError):
            pass


def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--host", default="0.0.0.0")
    args = ap.parse_args()

    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    ip = local_ip()
    print("=" * 62)
    print("  Simulierter Roboter läuft")
    print("=" * 62)
    print(f"  In der App hinzufügen:   {ip}:{args.port}")
    print(f"  Im Browser prüfen:       http://{ip}:{args.port}/api/v2/robot")
    print()
    print("  Räume:       Wohnzimmer (Holz), Küche (Fliese),")
    print("               Schlafzimmer (Teppich), Bad (Fliese),")
    print("               Flur (Teppich hochflorig), Büro (Teppich kurzflorig)")
    print("  Markierungen: je eine Türschwelle, ein Vorhang, eine Rampe")
    print()
    print("  Beenden mit Strg-C")
    print("=" * 62)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nBeendet.")
        srv.shutdown()


if __name__ == "__main__":
    main()
