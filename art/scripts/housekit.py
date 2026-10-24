"""Shared pieces for the Blender houses after the Victorian (farmhouse.py, mansard.py): walls of any
outline with their openings cut, pointed (Gothic) windows, board-and-batten strips, and the house
data file the game reads (src/server/World/HouseData/<Style>.luau): the doors' hinges, invisible
colliders, lights, decoration anchors, the rooms' lamps and figures, and where the yard goes.

All coordinates are Blender ones: x right, y back from the street, z up; the front door's centre
on the ground-floor front wall is the house's origin in x, the front wall is y = 0.
"""

import math

from mathutils import Matrix, Vector


def poly_wall(V, frame, points, openings, grp):
    """A wall whose outline is `points` ((x, z) in the frame, -Y outward), T thick inward, with
    rectangular openings (dicts x, y, w, h) cut through. Returns the wall object."""
    wall = V.prism(grp, points, V.T, frame, name="Wall")
    cutters = [V.box("_cutters", (o["w"], V.T * 3, o["h"]), (o["x"], V.T / 2, o["y"] + o["h"] / 2), matrix=frame) for o in openings]
    if cutters:
        V.cut(wall, cutters)
    return wall


def arch_points(x, y, w, h, n=6):
    """Outline of a pointed (lancet) arch opening from (x - w/2, y) to the apex, w wide and h tall:
    straight jambs, then two arcs of radius w, each centred on the opposite jamb, meeting at 60
    degrees. Returns the points (counter-clockwise, in the frame's XZ) and the apex height."""
    spring = y + h - w * math.sin(math.radians(60))
    pts = [(x - w / 2, y), (x + w / 2, y), (x + w / 2, spring)]
    right = []
    for i in range(1, n):
        a = math.radians(60) * i / n
        right.append((x - w / 2 + w * math.cos(a), spring + w * math.sin(a)))
    apex = (x, spring + w * math.sin(math.radians(60)))
    pts += right + [apex] + [(2 * x - px, pz) for px, pz in reversed(right)] + [(x - w / 2, spring)]
    return pts, apex[1]


def gothic_window(V, frame, x, y, w, h, wall=None, grp="Trim"):
    """A pointed-arch window: cut through `wall`, with a moulded surround, Y-tracery, a sill and
    glass, and recorded as an opening (its bounding rectangle) for the room walls behind."""
    pts, apex = arch_points(x, y, w, h)
    if wall is not None:
        cutter = V.prism("_cutters", pts, V.T * 3, frame @ Matrix.Translation((0, -V.T, 0)))
        V.cut(wall, [cutter])
    V.OPENINGS.append(dict(frame=frame, o=dict(x=x, y=y, w=w, h=apex - y)))
    # Surround: the same outline grown outward, as a ring standing proud of the wall.
    outer, _ = arch_points(x, y - 0.3, w + 1.0, h + 0.8)
    ring = V.prism(grp, outer, 0.3, frame @ Matrix.Translation((0, -0.3, 0)), name="Surround")
    V.cut(ring, [V.prism("_cutters", pts, 1.0, frame @ Matrix.Translation((0, -0.6, 0)))])
    V.box(grp, (w + 1.6, 0.9, 0.3), (x, -0.3, y - 0.15), bevel=0.05, matrix=frame)  # sill
    inset = 0.5
    V.prism("Glass", pts, 0.05, frame @ Matrix.Translation((0, inset + 0.1, 0)))
    # Y-tracery: a mullion that forks into the arch, a transom.
    V.box(grp, (0.14, 0.2, h * 0.62), (x, inset, y + h * 0.31), matrix=frame)
    fork = y + h * 0.62
    for s in (-1, 1):
        a = Vector((x, inset, fork))
        b = Vector((x + s * w * 0.42, inset, apex - w * 0.35))
        d = b - a
        V.box(grp, (0.12, 0.2, d.length), ((a + b) / 2).to_tuple(), rot=(0, -s * math.atan2(abs(d.x), d.z), 0), matrix=frame)
    V.box(grp, (w, 0.18, 0.14), (x, inset, y + h * 0.4), matrix=frame)
    return apex


def battens(V, frame, x0, x1, top, openings, spacing=1.2, grp="Siding", bottom=0.0):
    """Board-and-batten strips up the wall from x0 to x1 (frame coordinates), each from `bottom`
    to top(x), broken round the openings."""
    n = int((x1 - x0) / spacing)
    for i in range(1, n):
        x = x0 + i * (x1 - x0) / n
        spans = [(bottom, top(x))]
        for o in openings:
            if abs(x - o["x"]) < o["w"] / 2 + 0.7:
                lo, hi = o["y"] - 0.5, o["y"] + o["h"] + 1.0
                next_spans = []
                for a, b in spans:
                    if lo > a:
                        next_spans.append((a, min(b, lo)))
                    if hi < b:
                        next_spans.append((max(a, hi), b))
                spans = next_spans
        for a, b in spans:
            if b - a > 0.3:
                V.box(grp, (0.28, 0.16, b - a), (x, -0.08, (a + b) / 2), bevel=0.03, matrix=frame)


def gable_trim(V, low_left, peak, low_right, scallops=True, grp="Trim"):
    """Rake boards along a gable (world points), with a scalloped bargeboard and drops, and a
    turned finial at the peak."""
    for low in (low_left, low_right):
        V.slab(grp, low, peak, 0.35, 1.3)
        if scallops:
            for i in range(1, 9):
                pt = Vector(low).lerp(Vector(peak), i / 9)
                V.lathe(grp, [(0.12, 0), (0.18, 0.25), (0.1, 0.5), (0.14, 0.75), (0.0, 0.9)], (pt.x, pt.y, pt.z - 1.9), segments=6)
    p = Vector(peak)
    V.lathe(grp, [(0.25, 0), (0.3, 0.3), (0.15, 0.6), (0.2, 1.2), (0.12, 1.6), (0.18, 2.0), (0.0, 2.6)], (p.x, p.y, p.z - 0.2), segments=8)
    V.lathe(grp, [(0.15, 0), (0.2, -0.3), (0.0, -1.2)], (p.x, p.y, p.z - 0.4), segments=8)


# House data -------------------------------------------------------------------------------------
class Data:
    """Everything the game needs to know about a house model, gathered while it's built."""

    def __init__(self, style):
        self.style = style
        self.door = None
        self.hinged = []
        self.colliders = []
        self.lights = []
        self.anchors = []
        self.rooms = []
        self.yard = {}
        self.hall = None
        self.props = []

    def front_door(self, x, y, sill):
        """The front door slab's centre: x, the plane it sits in (y), and its threshold height."""
        self.door = dict(x=x, y=y, sill=sill)

    def hinge(self, name, kind, hinge, yaw, angle, openable, prompt=None):
        """A door slab mesh `name` that swings about a vertical axis at `hinge` (world point);
        `yaw` turns the hinge frame from facing the street (degrees)."""
        self.hinged.append(dict(name=name, kind=kind, hinge=Vector(hinge), yaw=yaw, angle=angle, openable=openable, prompt=prompt))

    def collider(self, size, centre, yaw=0.0):
        self.colliders.append((Vector(size), Vector(centre), yaw))

    def light(self, name, at, range_, brightness, color, shadows=True):
        self.lights.append((name, Vector(at), range_, brightness, color, shadows))

    def anchor(self, name, at, yaw=0.0):
        self.anchors.append((name, Vector(at), yaw))

    def room(self, room, lamp, role, front):
        """A room the game lights and furnishes: `room` is its box dict (interiors.box_room's),
        `role` one of living, kitchen, hall, tower, attic, `front` the window wall (y0, y1, x0, x1)."""
        import interiors

        self.rooms.append(interiors.room_entry(room, Vector(lamp), role, front))

    def entrance(self, lamp, figure):
        """The entrance hall behind the front door: its light (at its lamp), and where a figure
        can stand at its far end looking out (World/BlenderLot, the open houses)."""
        self.hall = (Vector(lamp), Vector(figure))

    def prop(self, at, yaw, pieces, chance=1.0):
        """A spot in the entrance hall: one of the furniture `pieces` goes there (or, `chance`
        aside, nothing), turned `yaw` degrees from facing the street."""
        self.props.append((Vector(at), yaw, list(pieces), chance))

    def write(self, root):
        def v3(p):
            return f"Vector3.new({p.x:.2f}, {p.y:.2f}, {p.z:.2f})"

        def c3(c):
            return f"Color3.fromRGB({c[0]}, {c[1]}, {c[2]})"

        d = self.door
        lines = [
            "--!strict",
            f"-- Generated by art/scripts/{self.style.lower()}.py (housekit.Data): everything the game needs to know",
            f"-- about the Blender {self.style} model, in its coordinates (x right, y back from the street,",
            "-- z up). Read by tools/setup_house.luau and World/BlenderLot. Don't edit by hand.",
            "",
            "local HouseData = require(script.Parent.Types)",
            "",
            "local data: HouseData.Data = {",
            f'\tstyle = "{self.style}",',
            f"\tdoor = {{ x = {d['x']:.2f}, y = {d['y']:.2f}, sill = {d['sill']:.2f} }},",
            "\thinged = {",
        ]
        for h in self.hinged:
            prompt = f'"{h["prompt"]}"' if h["prompt"] else "nil"
            lines.append(
                f'\t\t{{ name = "{h["name"]}", kind = "{h["kind"]}", hinge = {v3(h["hinge"])}, yaw = {h["yaw"]:.1f}, '
                f'angle = {h["angle"]:.1f}, openable = {"true" if h["openable"] else "false"}, prompt = {prompt} }},'
            )
        lines += ["\t},", "\tcolliders = {"]
        for size, centre, yaw in self.colliders:
            lines.append(f"\t\t{{ size = {v3(size)}, centre = {v3(centre)}, yaw = {yaw:.1f} }},")
        lines += ["\t},", "\tlights = {"]
        for name, at, range_, brightness, color, shadows in self.lights:
            lines.append(
                f'\t\t{{ name = "{name}", at = {v3(at)}, range = {range_}, brightness = {brightness}, color = {c3(color)}, shadows = {"true" if shadows else "false"} }},'
            )
        lines += ["\t},", "\tanchors = {"]
        for name, at, yaw in self.anchors:
            lines.append(f'\t\t{{ name = "{name}", at = {v3(at)}, yaw = {yaw:.1f} }},')
        lines += ["\t},", "\trooms = {"]
        import interiors

        lines += interiors.room_lines(self.rooms)
        y = self.yard
        graves = ", ".join(v3(Vector(g)) for g in y.get("graves", []))
        lines += [
            "\t},",
            "\tyard = {",
            f'\t\tfence = "{y.get("fence", "Iron")}",',
            f"\t\tpathFrom = {y.get('pathFrom', -12.0):.2f},",
            f"\t\ttree = {v3(Vector(y['tree']))},",
            f"\t\tgraves = {{ {graves} }},",
            "\t},",
        ]
        if self.hall:
            lamp, figure = self.hall
            lines += ["\thall = {", f"\t\tlamp = {v3(lamp)},", f"\t\tfigure = {v3(figure)},", "\t\tprops = {"]
            for at, yaw, pieces, chance in self.props:
                names = ", ".join(f'"{n}"' for n in pieces)
                lines.append(f"\t\t\t{{ at = {v3(at)}, yaw = {yaw:.1f}, pieces = {{ {names} }}, chance = {chance:.2f} }},")
            lines += ["\t\t},", "\t},"]
        lines += [
            "}",
            "",
            "return data",
            "",
        ]
        path = root.parent / "src" / "server" / "World" / "HouseData" / f"{self.style}.luau"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines), encoding="utf-8")
        print("WROTE", path)
