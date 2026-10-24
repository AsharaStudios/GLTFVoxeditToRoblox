# VoxEdit project -> GLTF: turns a VoxEdit project (.vxr rig + its .vxm models + .vxa animations) into a GLTF
# laid out like the one VoxEdit exports itself ("<id>-Global" / "<id>-Local" nodes, one mesh + texture per piece,
# per-frame LINEAR animations at 24 fps), so voxedit_to_roblox.py / voxedit_kit_to_roblox.py read it unchanged.
# Needs Python 3 + numpy: Blender's own Python is used (<Blender>\<version>\python\bin\python.exe).
# Usage: python voxedit_project_to_gltf.py PROJECT.vxr OUT.gltf
#        python voxedit_project_to_gltf.py --list JOBS.txt [--progress-file F] [--log-file F]
#        (JOBS.txt: one "project.vxr<TAB>out.gltf" per line; used by the "VoxEdit Project to GLTF" window)
import sys, os, json, struct, zlib, base64, glob, time, traceback, argparse
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voxedit_formats import read_vxm, read_vxr, read_vxa, walk

FPS = 24
EMPTY = 255


# ------------------------------------------------------------------ maths (conventions found by comparison, INFORME.md)
def ease(kind, t):
    if kind == 0: return 0.0                       # instant
    if kind == 2: return t * t                     # quad in
    if kind == 3: return t * (2 - t)               # quad out
    if kind == 4: return 2 * t * t if t < .5 else -1 + (4 - 2 * t) * t
    if kind == 5: return t ** 3                    # cubic in (not seen yet in a real project)
    if kind == 6: return (t - 1) ** 3 + 1
    if kind == 7: return 4 * t ** 3 if t < .5 else (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
    return t                                       # linear


def chan(keys, f, default):
    """value of one channel at frame f; the LEFT key's curve drives each segment"""
    if not keys: return default
    if f <= keys[0][0]: return keys[0][3]
    if f >= keys[-1][0]: return keys[-1][3]
    for a, b in zip(keys, keys[1:]):
        if a[0] <= f <= b[0]:
            t = (f - a[0]) / (b[0] - a[0]) if b[0] != a[0] else 0.0
            return a[3] + (b[3] - a[3]) * ease(a[1], t)


def qmul(a, b):
    x1, y1, z1, w1 = a; x2, y2, z2, w2 = b
    return np.array([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2])


def quat_zyx(e):
    q = np.array([0, 0, 0, 1.0])
    for ax in (2, 1, 0):  # Z * Y * X
        r = np.zeros(4); r[3] = np.cos(e[ax] / 2); r[ax] = np.sin(e[ax] / 2)
        q = qmul(q, r)
    return q


def slerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0: b, d = -b, -d
    if d > 0.9995:
        q = a + (b - a) * t; return q / np.linalg.norm(q)
    th = np.arccos(d)
    return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)


def pose_v2(anode, f):
    """VXA 2: whole keyframes (translation, quaternion x y z w, scale)"""
    ks = anode["keys"]
    if not ks:
        return [0.0, 0.0, 0.0], np.array([0, 0, 0, 1.0]), 1.0
    def at(k): return list(k["t"]), np.array(k["q_raw"], float), k["s"]
    if f <= ks[0]["frame"]: return at(ks[0])
    if f >= ks[-1]["frame"]: return at(ks[-1])
    for a, b in zip(ks, ks[1:]):
        if a["frame"] <= f <= b["frame"]:
            t = ease(a["interp"], (f - a["frame"]) / (b["frame"] - a["frame"]))
            ta, qa, sa = at(a); tb, qb, sb = at(b)
            return [x + (y - x) * t for x, y in zip(ta, tb)], slerp(qa, qb, t), sa + (sb - sa) * t


def pose(anode, f):
    """(translation, rotation quaternion xyzw, scale) of one bone at frame f"""
    if "keys" in anode:
        return pose_v2(anode, f)
    ch = anode["channels"]
    tr = [chan(ch[c], f, 0.0) for c in range(3)]
    euler_at = lambda fr: [chan(ch[c], fr, 0.0) for c in range(3, 6)]
    q = quat_zyx(euler_at(f))
    rk = ch[3]
    for a, b in zip(rk, rk[1:]):  # rotation keys marked "slerp": interpolate the whole orientation
        if a[0] <= f <= b[0] and a[2] and b[0] != a[0]:
            q = slerp(quat_zyx(euler_at(a[0])), quat_zyx(euler_at(b[0])), ease(a[1], (f - a[0]) / (b[0] - a[0])))
            break
    sc = chan(ch[6][:1], 0, 1.0)  # (VoxEdit only uses the frame-0 scale)
    return tr, q, sc


# ------------------------------------------------------------------ PNG (no external modules)
def png_bytes(rgba):
    h, w = rgba.shape[:2]
    raw = b"".join(b"\0" + rgba[y].tobytes() for y in range(h))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# ------------------------------------------------------------------ GLTF building
class Gltf:
    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "VoxToRoblox vxr_to_gltf"}, "scene": 0, "scenes": [{"nodes": [0]}],
                  "nodes": [], "meshes": [], "materials": [], "textures": [], "images": [], "accessors": [],
                  "bufferViews": [], "buffers": [], "animations": [],
                  "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}]}
        self.bin = bytearray()

    def view(self, data):
        while len(self.bin) % 4: self.bin += b"\0"
        self.j["bufferViews"].append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)})
        self.bin += data
        return len(self.j["bufferViews"]) - 1

    def accessor(self, arr, kind, minmax=False):
        arr = np.ascontiguousarray(arr, np.float32)
        a = {"bufferView": self.view(arr.tobytes()), "componentType": 5126, "count": len(arr), "type": kind}
        if minmax:
            a["min"] = arr.reshape(len(arr), -1).min(0).tolist(); a["max"] = arr.reshape(len(arr), -1).max(0).tolist()
        self.j["accessors"].append(a)
        return len(self.j["accessors"]) - 1

    def image(self, rgba):
        self.j["images"].append({"mimeType": "image/png", "bufferView": self.view(png_bytes(rgba))})
        self.j["textures"].append({"source": len(self.j["images"]) - 1, "sampler": 0})
        return len(self.j["textures"]) - 1

    def node(self, d):
        self.j["nodes"].append(d)
        return len(self.j["nodes"]) - 1

    def save(self, path):
        self.j["buffers"] = [{"byteLength": len(self.bin),
                              "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(self.bin)).decode()}]
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.j, f, separators=(",", ":"))


def gl_name(node_id):
    return node_id.replace(" ", "$$", 1)  # (VoxEdit writes the first space of an id as "$$")


def piece_mesh(G, name, m):
    lod = m["lods"][0]
    size = np.array(m["size"], float)
    S = 2 * np.ceil(size.max() / 2)               # the quads are stored in units of the piece's even-rounded longest side
    corners = np.array([v[:3] for f in lod["faces"] for q in f for v in q]) * S
    vox = np.array([k for md in m["models"] for k in md["voxels"]] or [(0, 0, 0)])
    off = (vox.min(0) - size / 2) - corners.min(0)  # (place the mesh on its voxels, centred on the piece)
    tw, th = lod["tex_size"]
    ind = np.frombuffer(lod["tex"], np.uint8).reshape(th, tw)
    alb = np.array(m["albedo"], np.uint8); emi = np.array(m["emissive"], np.uint8)
    alb[EMPTY] = 0; emi[EMPTY] = 0
    pos, uv, nrm = [], [], []
    for q in (q for f in lod["faces"] for q in f):
        c = np.array([v[:3] for v in q]) * S + off
        t = np.array([v[3:] for v in q], float) / [tw, th]
        n = np.cross(c[1] - c[0], c[2] - c[0]); n = n / (np.linalg.norm(n) or 1)
        for k in (0, 1, 2, 2, 3, 0):
            pos.append(c[k]); uv.append(t[k]); nrm.append(n)
    pos = np.array(pos); uv = np.array(uv); nrm = np.array(nrm)
    base = G.image(alb[ind]); glow = G.image(emi[ind])
    G.j["materials"].append({"name": name + "-Material", "pbrMetallicRoughness": {"baseColorTexture": {"index": base},
                             "metallicFactor": 0, "roughnessFactor": 1},
                             "emissiveTexture": {"index": glow, "texCoord": 1}, "emissiveFactor": [1, 1, 1]})
    G.j["meshes"].append({"name": name + "-Mesh", "primitives": [{"mode": 4, "material": len(G.j["materials"]) - 1, "attributes": {
        "POSITION": G.accessor(pos, "VEC3", True), "NORMAL": G.accessor(nrm, "VEC3"),
        "TEXCOORD_0": G.accessor(uv, "VEC2"), "TEXCOORD_1": G.accessor(uv, "VEC2")}}]})
    return len(G.j["meshes"]) - 1


def convert(vxr_path, out_path, step=lambda f, label: None):
    folder = os.path.dirname(os.path.abspath(vxr_path))
    base = os.path.splitext(os.path.basename(vxr_path))[0]
    step(0.0, "Reading rig")
    rig = read_vxr(vxr_path)
    missing = sorted({nd["file"] for nd, _, _, _ in walk(rig["children"])
                      if nd["file"] and not os.path.isfile(os.path.join(folder, nd["file"]))})
    if missing:
        raise FileNotFoundError("missing model file(s): " + ", ".join(missing))
    step(0.05, "Reading animations")
    anims = []
    for f in sorted(glob.glob(os.path.join(folder, glob.escape(base) + ".*.vxa"))):
        anims.append(read_vxa(f))
    default = next((a for a in anims if a["name"] == rig["default_anim"]), anims[0] if anims else None)
    G = Gltf()
    world = G.node({"name": "World-Global", "rotation": [0, -1, 0, -4.371138828673793e-08], "translation": [0, 0, 0],
                    "scale": [-1, 1, 1], "children": []})
    G.j["nodes"][world]["children"].append(G.node({"name": "World-Local"}))
    meshes = {}
    glob_of = {}
    total = max(1, sum(1 for _ in walk(rig["children"])))
    done = [0]

    def add(nd, an, parent):
        done[0] += 1
        step(0.1 + 0.4 * done[0] / total, "Building models")
        name = gl_name(nd["id"])
        tr, q, sc = pose(an, 0) if an else ([0, 0, 0], np.array([0, 0, 0, 1.0]), 1.0)
        gi = G.node({"name": name + "-Global", "translation": [float(x) for x in tr], "rotation": [float(x) for x in q],
                     "scale": [sc, sc, sc], "children": []})
        G.j["nodes"][parent]["children"].append(gi)
        local = {"name": name + "-Local"}
        if nd["file"]:
            m = read_vxm(os.path.join(folder, nd["file"]))
            if nd["file"] not in meshes:
                meshes[nd["file"]] = piece_mesh(G, os.path.splitext(nd["file"])[0], m)
            size = np.array(m["size"], float); piv = np.array(m["pivot"])
            local["translation"] = [float(x) for x in -(piv * size - size / 2)]
            local["mesh"] = meshes[nd["file"]]
        G.j["nodes"][gi]["children"].append(G.node(local))
        glob_of[nd["id"]] = gi
        for c, ca in zip(nd["children"], an["children"] if an else [None] * len(nd["children"])):
            add(c, ca, gi)

    for c, ca in zip(rig["children"], default["children"] if default else [None] * len(rig["children"])):
        add(c, ca, world)
    # animations: every bone sampled at every frame (LINEAR), like VoxEdit
    for ai, a in enumerate(anims):
        step(0.5 + 0.4 * ai / max(1, len(anims)), "Building animations")
        nodes = list(walk(rig["children"], a["children"]))
        if a["version"] == 2:
            last = max([k["frame"] for _, an, _, _ in nodes for k in an["keys"]] + [0])
        else:
            last = max([k[0] for _, an, _, _ in nodes for c in an["channels"] for k in c] + [0])
        last = max(last, 1)  # (at least 2 samples, like VoxEdit's 1-frame poses)
        frames = np.arange(last + 1)
        times = G.accessor(frames / FPS, "SCALAR", True)
        chans, samps = [], []
        for nd, an, _, _ in nodes:
            P = [pose(an, f) for f in frames]
            for path, data, kind in (("translation", [p[0] for p in P], "VEC3"), ("rotation", [p[1] for p in P], "VEC4"),
                                     ("scale", [[p[2]] * 3 for p in P], "VEC3")):
                samps.append({"input": times, "output": G.accessor(np.array(data), kind), "interpolation": "LINEAR"})
                chans.append({"sampler": len(samps) - 1, "target": {"node": glob_of[nd["id"]], "path": path}})
        G.j["animations"].append({"name": a["name"], "channels": chans, "samplers": samps})
    step(0.92, "Writing GLTF")
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    tmp = out_path + ".part"
    G.save(tmp)
    os.replace(tmp, out_path)  # (no half-written GLTF in Input if something fails)
    return {"pieces": total, "meshes": len(G.j["meshes"]), "animations": [a["name"] for a in anims],
            "size_kb": os.path.getsize(out_path) // 1024}


class Progress:
    """same tab-separated lines as voxedit_to_roblox.py, read by the window"""
    def __init__(self, path=None):
        self.f = open(path, "w", encoding="utf-8") if path else None
        self.last = None

    def emit(self, *fields):
        if self.f:
            self.f.write("\t".join(str(x).replace("\t", " ").replace("\n", " ") for x in fields) + "\n")
            self.f.flush()

    def step(self, f, label):
        key = (round(min(max(f, 0.0), 1.0), 2), label)
        if key != self.last:
            self.last = key
            self.emit("STEP", *key)


def main():
    ap = argparse.ArgumentParser(prog="voxedit_project_to_gltf")
    ap.add_argument("files", nargs="*", help="PROJECT.vxr OUT.gltf")
    ap.add_argument("--list", help="text file with one 'project.vxr<TAB>out.gltf' per line")
    ap.add_argument("--progress-file", help="writes progress lines here (used by the window)")
    ap.add_argument("--log-file", help="writes the log here instead of the console")
    args = ap.parse_args()
    if args.log_file:
        sys.stdout = sys.stderr = open(args.log_file, "a", encoding="utf-8", buffering=1)
    jobs = []
    if args.list:
        with open(args.list, encoding="utf-8") as f:
            jobs = [l.rstrip("\r\n").split("\t") for l in f if "\t" in l]
    elif len(args.files) == 2:
        jobs = [args.files]
    else:
        ap.error("give PROJECT.vxr OUT.gltf, or --list")
    bar = Progress(args.progress_file)
    ok = 0
    for i, (src, dst) in enumerate(jobs, 1):
        bar.emit("FILE", i, len(jobs), src)
        print("[VoxEdit project]", src, "->", dst, flush=True)
        t0 = time.time()
        try:
            info = convert(src, dst, bar.step)
            ok += 1
            print("[VoxEdit project] OK", info, flush=True)
            bar.emit("DONE", f"{time.time() - t0:.1f}")
        except Exception as e:
            print("[VoxEdit project] ERROR with", src, flush=True); traceback.print_exc()
            bar.emit("ERROR", str(e)[:150] or type(e).__name__)
    print(f"[VoxEdit project] Done: {ok}/{len(jobs)} converted.", flush=True)
    bar.emit("END", ok, len(jobs))


if __name__ == "__main__":
    main()
