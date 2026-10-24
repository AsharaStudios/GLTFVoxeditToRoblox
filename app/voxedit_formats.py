# Readers for VoxEdit project files (.vxm v12 / .vxr v9 / .vxa v2-v4), used by voxedit_project_to_gltf.py.
# The field layout follows the open-source readers of vengi (https://github.com/vengi-voxel/vengi, MIT license,
# Copyright (c) Martin Gerhardy); the rest was worked out by comparing projects with VoxEdit's own GLTF exports.
import struct, zlib, os


class Reader:
    def __init__(self, data):
        self.d, self.p = data, 0

    def take(self, n):
        b = self.d[self.p:self.p + n]
        if len(b) < n:
            raise EOFError(f"need {n} bytes at {self.p}")
        self.p += n
        return b

    def u8(self): return self.take(1)[0]
    def b(self): return self.u8() != 0
    def u32(self): return struct.unpack("<I", self.take(4))[0]
    def i32(self): return struct.unpack("<i", self.take(4))[0]
    def f32(self): return struct.unpack("<f", self.take(4))[0]
    def u64(self): return struct.unpack("<Q", self.take(8))[0]

    def s(self):
        e = self.d.index(b"\0", self.p)
        t = self.d[self.p:e].decode("latin-1")
        self.p = e + 1
        return t

    def left(self): return len(self.d) - self.p


def version_of(magic):
    c = chr(magic[3])
    return int(c) if c.isdigit() else 10 + ord(c) - ord("A")


# ------------------------------------------------------------------ VXM
def read_vxm(path):
    r = Reader(open(path, "rb").read())
    magic = r.take(4)
    assert magic[:3] == b"VXM", magic
    v = version_of(magic)
    m = {"version": v}
    m["size"] = (r.u32(), r.u32(), r.u32())
    m["pivot"] = (r.f32(), r.f32(), r.f32())
    if r.u8():  # surface
        vals = [r.u32() for _ in range(7)]
        w, h = r.u32(), r.u32()
        r.take(w * h)
    m["lod"] = [r.f32() for _ in range(4)]
    lods = []
    for _ in range(r.u32()):
        tw, th = r.u32(), r.u32()
        zipped = r.take(r.u32())
        tex = zlib.decompress(zipped) if zipped else b""
        faces = []
        for _ in range(6):
            quads = []
            for _ in range(r.u32()):
                vs = []
                for _ in range(4):
                    x, y, z = r.f32(), r.f32(), r.f32()
                    u, vv = r.i32(), r.i32()
                    vs.append((x, y, z, u, vv))
                quads.append(vs)
            faces.append(quads)
        lods.append({"tex_size": (tw, th), "tex": tex, "faces": faces})
    m["lods"] = lods
    m["albedo"] = [tuple(r.take(4)) for _ in range(256)]
    m["emissive"] = [tuple(r.take(4)) for _ in range(256)]
    chunks = []
    for _ in range(r.u8()):
        chunks.append((r.s(), r.u8(), r.u8()))
    m["chunks"] = chunks
    mats = []
    for _ in range(r.u8()):
        bl, g, rd, a = r.take(4)
        mats.append(((rd, g, bl, a), r.u8()))
    m["materials"] = mats
    models = []
    sx, sy, sz = m["size"]
    for _ in range(r.u8()):
        name, visible = r.s(), r.b()
        vox, idx = {}, 0
        while True:
            ln = r.u8()
            if ln == 0:
                break
            mi = r.u8()
            if mi != 0xFF:
                for i in range(idx, idx + ln):
                    vox[(i // (sy * sz), (i // sz) % sy, i % sz)] = mi
            idx += ln
        models.append({"name": name, "visible": visible, "voxels": vox})
    m["models"] = models
    m["tail"] = r.left()
    return m


# ------------------------------------------------------------------ VXR
def read_vxr(path):
    r = Reader(open(path, "rb").read())
    magic = r.take(4)
    assert magic[:3] == b"VXR", magic
    v = version_of(magic)
    rig = {"version": v, "default_anim": r.s() if v >= 7 else ""}
    n = r.i32()
    if v >= 8:
        rig["base_template"] = r.s()
        rig["static"] = r.b()
        assert not rig["static"], "static VXR not handled"

    def child():
        nd = {"id": r.s(), "file": r.s()}
        if v >= 9:
            nd["collidable"], nd["decorative"] = r.b(), r.b()
        if v >= 6:
            nd["color"] = r.u32(); nd["favorite"] = r.b(); nd["visible"] = r.b()
        nd["mirror"] = [r.b() for _ in range(3)]
        nd["preview_mirror"] = [r.b() for _ in range(3)]
        nd["ik_anchor"] = r.b()
        if v >= 9:
            nd["ik_effector"] = r.s(); nd["ik_visible"] = r.b()
            nd["roll"] = (r.f32(), r.f32())
            nd["swing"] = [(r.f32(), r.f32(), r.f32()) for _ in range(r.i32())]
        nd["children"] = [child() for _ in range(r.i32())]
        return nd

    rig["children"] = [child() for _ in range(n)]
    rig["tail"] = r.left()
    return rig


# ------------------------------------------------------------------ VXA
def read_vxa(path):
    r = Reader(open(path, "rb").read())
    magic = r.take(4)
    assert magic[:3] == b"VXA", magic
    v = version_of(magic)
    assert v in (2, 3, 4), v
    a = {"version": v, "md5": (r.u64(), r.u64()), "name": r.s()}

    def node_v2():
        # one list of whole keyframes: translation, orientation (4 floats) and scale (+ "ignored" copies)
        keys = []
        for _ in range(r.i32()):
            k = {"frame": r.i32(), "interp": r.i32(), "long_rotation": r.b()}
            k["t"] = (r.f32(), r.f32(), r.f32()); k["t_ignored"] = (r.f32(), r.f32(), r.f32())
            k["q_raw"] = (r.f32(), r.f32(), r.f32(), r.f32()); k["q_ignored"] = (r.f32(), r.f32(), r.f32(), r.f32())
            k["s"] = r.f32(); k["s_ignored"] = r.f32()
            keys.append(k)
        return {"keys": keys, "children": [node_v2() for _ in range(r.i32())]}

    if v == 2:
        a["children"] = [node_v2() for _ in range(r.i32())]
        a["tail"] = r.left()
        return a

    def node():
        ch = []
        for c in range(7):
            keys = []
            for _ in range(r.i32()):
                frame, interp = r.i32(), r.i32()
                slerp = r.b() if c == 3 else None
                keys.append((frame, interp, slerp, r.f32()))
            ch.append(keys)
        return {"channels": ch, "children": [node() for _ in range(r.i32())]}

    a["children"] = [node() for _ in range(r.i32())]
    a["tail"] = r.left()
    return a


def walk(rig_nodes, anim_nodes=None, depth=0, parent=None):
    """yields (rig node, anim node, depth, parent id) in file order"""
    for i, nd in enumerate(rig_nodes):
        an = anim_nodes[i] if anim_nodes else None
        yield nd, an, depth, parent
        yield from walk(nd["children"], an["children"] if an else None, depth + 1, nd["id"])
