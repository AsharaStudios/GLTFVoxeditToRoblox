# VoxToRoblox - converts animated VoxEdit GLTF files into a rig + FBX animations for Roblox
# Usage: blender -b --factory-startup --python voxedit_to_roblox.py -- INPUTS... [options]
import bpy, bmesh, sys, os, re, math, argparse, time, traceback, hashlib
import numpy as np
from mathutils import Matrix, Vector

VERSION = "1.8"
I4 = np.eye(4)

def log(*a):
    print("[VoxToRoblox]", *a, flush=True)

class Progress:
    """tab-separated progress lines for the Convert window (VoxToRoblox.ps1), written to --progress-file:
    FILE i n path | STEP fraction label | DONE seconds | ERROR message | END ok n | FATAL message"""
    def __init__(self, path=None):
        self.f = open(path, "w", encoding="utf-8") if path else None
        self.last = None

    def emit(self, *fields):
        if self.f:
            self.f.write("\t".join(str(x).replace("\t", " ").replace("\n", " ") for x in fields) + "\n")
            self.f.flush()

    def __call__(self, f, txt=""):
        key = (round(min(max(f, 0.0), 1.0), 2), txt)
        if key != self.last:
            self.last = key
            self.emit("STEP", *key)

bar = Progress()

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(prog="voxedit_to_roblox")
    ap.add_argument("inputs", nargs="*", help=".gltf/.glb files or folders")
    ap.add_argument("--out", help="output folder (default: <gltf folder>/Roblox/<name>)")
    ap.add_argument("--height", type=float, default=5.5, help="final height in studs (default 5.5)")
    ap.add_argument("--tex", type=int, default=1024, help="final texture size (default 1024)")
    ap.add_argument("--rest", default=None, help="animation used as the rest pose (default: the T-pose if there is one)")
    ap.add_argument("--max-error", type=float, default=0.5, help="max error when merging bones, in voxels (default 0.5)")
    ap.add_argument("--max-bones", type=int, default=0, help="hard bone limit (0 = no limit)")
    ap.add_argument("--no-reduce", action="store_true", help="do not merge bones")
    ap.add_argument("--simplify", type=float, default=1.0, help="FBX keyframe reduction, 0 = none (default 1.0)")
    ap.add_argument("--anim-skeleton-only", action="store_true", help="animation FBX files with the skeleton only (lighter; the rest pose may be read wrong)")
    ap.add_argument("--no-rotate", action="store_true", help="do not rotate 180 degrees (if the model ends up facing backwards)")
    ap.add_argument("--no-combined", action="store_true", help="do not build the single <Name>_Roblox.fbx with every animation")
    ap.add_argument("--no-blend", action="store_true", help="do not save the .blend with the rig and every animation")
    # --- PBR maps (1.3)
    ap.add_argument("--no-pbr", action="store_true", help="do not generate normal / roughness / metalness / emissive")
    ap.add_argument("--palette", "--paleta", dest="palette", action="store_true", help="cut every face into flat-colour rectangles: sharp in Roblox but ~4x triangles (default: off, performance first)")
    ap.add_argument("--emis-relative", action="store_true", help="emissive mask with VoxEdit's intensity (default: pure white)")
    ap.add_argument("--maps-only", action="store_true", help="atlas + PBR maps only (does not touch the FBX, .blend or animations)")
    ap.add_argument("--normal-strength", type=float, default=1.0, help="normal map strength (default 1.0)")
    ap.add_argument("--bevel", type=float, default=0.25, help="bevel width between voxels of different colour, fraction of a voxel (default 0.25)")
    ap.add_argument("--voxel-bevel", type=float, default=0.0, help="bevel on EVERY voxel edge, 'block' look (default 0 = off; try 0.4)")
    ap.add_argument("--max-size", type=int, default=1024, help="max size of the PBR maps (Roblox downsizes everything to 1024)")
    ap.add_argument("--roughness", type=float, default=0.6, help="base roughness when the model has none (default 0.6)")
    ap.add_argument("--rough-var", type=float, default=0.35, help="roughness variation by colour brightness (default 0.35)")
    ap.add_argument("--metal", type=float, default=0.0, help="base metalness when the model has none (default 0)")
    ap.add_argument("--progress-file", help="writes progress lines here (used by the Convert window)")
    ap.add_argument("--log-file", help="writes the full log here instead of the console")
    ap.add_argument("--thumb-list", help="only render thumbnails: a text file with one 'source.gltf<TAB>thumb.png' per line")
    ap.add_argument("--thumb-size", type=int, default=96, help="thumbnail size in pixels (default 96)")
    return ap.parse_args(argv)

def expand(inputs):
    files = []
    for p in inputs:
        p = os.path.abspath(p.strip('"'))
        if os.path.isdir(p):
            for r, d, f in os.walk(p):
                d[:] = [x for x in d if x.lower() != "roblox"]
                files += [os.path.join(r, x) for x in f if x.lower().endswith((".gltf", ".glb"))]
        elif p.lower().endswith((".gltf", ".glb")) and os.path.isfile(p):
            files.append(p)
        else:
            log("Skipped:", p)
    return files

def find_base(mat):
    if mat is None:
        return None, (0.8, 0.8, 0.8, 1.0)
    if not getattr(mat, "node_tree", None):
        return None, tuple(mat.diffuse_color)
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if not bsdf:
        return None, tuple(mat.diffuse_color)
    inp = bsdf.inputs["Base Color"]
    stack, seen = [l.from_node for l in inp.links], set()
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        if n.type == "TEX_IMAGE" and n.image:
            return n.image, None
        for i in n.inputs:
            stack += [l.from_node for l in i.links]
    return None, tuple(inp.default_value)

def _upstream(sock):
    """(image, channel) wired into a BSDF input; channel = 0/1/2 if it goes through a Separate Color."""
    if not sock.links:
        return None, None
    fs = sock.links[0].from_socket
    ch = None
    if fs.node.type in ("SEPARATE_COLOR", "SEPRGB", "SEPARATE_RGB"):
        ch = {"Red": 0, "R": 0, "Green": 1, "G": 1, "Blue": 2, "B": 2}.get(fs.name)
    stack, seen = [fs.node], set()
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        if n.type == "TEX_IMAGE" and n.image:
            return n.image, ch
        for i in n.inputs:
            stack += [l.from_node for l in i.links]
    return None, ch

def find_mat(mat):
    """base colour + PBR data of the material (metal, roughness, emission; constants or images)."""
    img, col = find_base(mat)
    ex = {"metal": 0.0, "rough": 1.0, "mimg": None, "mch": None, "rimg": None, "rch": None,
          "eimg": None, "ecol": 0.0, "estr": 1.0}
    bsdf = None
    if mat is not None and getattr(mat, "node_tree", None):
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        def inp(*names):
            return next((bsdf.inputs[n] for n in names if n in bsdf.inputs), None)
        m, r = inp("Metallic"), inp("Roughness")
        ec, es = inp("Emission Color", "Emission"), inp("Emission Strength")
        if m is not None:
            ex["metal"] = float(m.default_value)
            ex["mimg"], ex["mch"] = _upstream(m)
        if r is not None:
            ex["rough"] = float(r.default_value)
            ex["rimg"], ex["rch"] = _upstream(r)
        if es is not None:
            ex["estr"] = float(es.default_value)
        if ec is not None:
            ex["eimg"], _ = _upstream(ec)
            if ex["eimg"] is None:
                ex["ecol"] = float(max(tuple(ec.default_value)[:3]))
    return img, col, ex

def _fit(a, h, w):
    """resizes (nearest neighbour) an HxWxC image to h x w."""
    if a.shape[0] == h and a.shape[1] == w:
        return a
    ys = np.arange(h) * a.shape[0] // h
    xs = np.arange(w) * a.shape[1] // w
    return a[ys][:, xs]

def make_maps(color, pbr, K, args, use_defaults):
    """PBR maps from the atlas (A x A, rows bottom to top as in Blender) upscaled xK.
    normal: relief from colour brightness (dark sinks in) with a bevel between voxels.
    returns normal (T,T,3), rough (T,T), metal (T,T), emis (T,T) in 0..1"""
    L = color[..., 0] * 0.2126 + color[..., 1] * 0.7152 + color[..., 2] * 0.0722
    # normalised contrast: a model in dark tones (e.g. navy blue) still gets relief
    used = L[color[..., :3].max(-1) > 0.002]
    if used.size:
        lo, hi = np.percentile(used, 2), np.percentile(used, 98)
        if hi - lo > 1e-3:
            L = np.clip((L - lo) / (hi - lo), 0, 1)
    S = 3.0 * args.normal_strength
    dR = np.roll(L, -1, 1) - L
    dL = np.roll(L, 1, 1) - L
    dU = np.roll(L, -1, 0) - L
    dD = np.roll(L, 1, 0) - L
    up = lambda a: np.repeat(np.repeat(a, K, 0), K, 1)
    T = L.shape[0] * K
    band = max(1, int(round(K * args.bevel)))
    lx = (np.arange(T) % K)[None, :]
    ly = (np.arange(T) % K)[:, None]
    right, left = lx >= K - band, lx < band
    top, bottom = ly >= K - band, ly < band
    nx = np.zeros((T, T), np.float32)
    ny = np.zeros((T, T), np.float32)
    nx -= np.where(right, up(dR), 0) * S
    nx += np.where(left, up(dL), 0) * S
    ny -= np.where(top, up(dU), 0) * S
    ny += np.where(bottom, up(dD), 0) * S
    if args.voxel_bevel > 0 and K >= 2:
        g = args.voxel_bevel
        nx += np.where(right, g, 0) - np.where(left, g, 0)
        ny += np.where(top, g, 0) - np.where(bottom, g, 0)
    nz = np.ones((T, T), np.float32)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    Lu = up(L)
    emis = np.clip(up(pbr[..., 2]), 0, 1)
    if use_defaults:
        rough = np.full((T, T), args.roughness, np.float32)
        metal = np.full((T, T), args.metal, np.float32)
    else:
        rough = up(pbr[..., 1]).astype(np.float32)
        metal = up(pbr[..., 0]).astype(np.float32)
    rough = rough + args.rough_var * (0.5 - Lu)
    rough = rough * (1 - 0.5 * emis)  # glowing parts look more polished
    rough = np.clip(rough, 0.02, 1)
    metal = np.clip(metal, 0, 1)
    return normal.astype(np.float32), rough, metal, emis.astype(np.float32)

def save_png(name, arr, out):
    """saves a (T,T,3) or (T,T) 0..1 array as PNG with no colour conversion."""
    if arr.ndim == 2:
        arr = np.repeat(arr[..., None], 3, -1)
    h, w = arr.shape[:2]
    rgba = np.concatenate([arr, np.ones((h, w, 1), np.float32)], -1)
    im = bpy.data.images.new(name, w, h, alpha=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.filepath_raw = os.path.join(out, name + ".png")
    im.file_format = "PNG"
    im.save()
    return im

def normalize(Wm):
    R = Wm[..., :3, :3].copy()
    neg = np.linalg.det(R) < 0
    R[neg, :, 0] *= -1
    U, _, Vt = np.linalg.svd(R)
    B = np.zeros(Wm.shape)
    B[..., :3, :3] = U @ Vt
    B[..., :3, 3] = Wm[..., :3, 3]
    B[..., 3, 3] = 1
    return B

def sample(objs, actions):
    sc = bpy.context.scene
    for o in objs:
        if o.animation_data:
            for t in o.animation_data.nla_tracks:
                t.mute = True
    frames, ranges = [], {}
    if not actions:
        sc.frame_set(0)
        frames.append([np.array(o.matrix_world) for o in objs])
        ranges["Pose"] = (0, 1)
    for ai, act in enumerate(actions):
        bar(0.05 + 0.20 * ai / len(actions), "Reading animations")
        for o in objs:
            ad = o.animation_data
            if not ad:
                continue
            ad.action = act
            if hasattr(act, "slots"):
                sl = act.slots.get("OB" + o.name)
                if sl:
                    ad.action_slot = sl
        f0, f1 = int(math.floor(act.frame_range[0])), int(math.ceil(act.frame_range[1]))
        start = len(frames)
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            frames.append([np.array(o.matrix_world) for o in objs])
        ranges[act.name] = (start, len(frames))
    return np.array(frames), ranges

def export_fbx(path, objects, anim, simplify, all_actions=False):
    for o in bpy.context.scene.objects:
        o.select_set(o in objects)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, object_types={o.type for o in objects},
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
        mesh_smooth_type="FACE", add_leaf_bones=False, path_mode="COPY", embed_textures=True,
        bake_anim=anim, bake_anim_use_all_actions=all_actions, bake_anim_use_nla_strips=False,
        bake_anim_force_startend_keying=True, bake_anim_simplify_factor=simplify, bake_anim_step=1.0)

def process(path, args):
    t0 = time.time()
    name = os.path.splitext(os.path.basename(path))[0]
    base = re.sub(r"(?i)[_\- ]?(gltf|glb)$", "", name) or name
    base = re.sub(r"[^A-Za-z0-9_]+", "_", base)
    out = os.path.join(args.out, base) if args.out else os.path.join(os.path.dirname(path), "Roblox", base)
    os.makedirs(os.path.join(out, "Animations"), exist_ok=True)
    log("==>", path)

    bar(0.0, "Importing")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = list(bpy.data.objects)
    idx = {o.name: i for i, o in enumerate(objs)}
    parent = [idx[o.parent.name] if o.parent else -1 for o in objs]
    actions = [] if args.maps_only else list(bpy.data.actions)
    W, ranges = sample(objs, actions)
    F, N = W.shape[:2]
    def pick_rest():
        if args.rest:
            for k in ranges:
                if k.lower() == args.rest.lower():
                    return k
            log(f"Warning: there is no animation called '{args.rest}'")
        norm = {k: re.sub(r"[^a-z0-9]", "", k.lower()) for k in ranges}
        for pat in (r"^tpose\d*$", r"^t\d*$", r"tpose", r"^apose\d*$", r"bind|rest"):
            for k, nk in norm.items():
                if re.search(pat, nk):
                    return k
        return next(iter(ranges))
    rest_key = pick_rest()
    r = ranges[rest_key][0]
    log(f"{N} nodes, {len(ranges)} animations, {F} frames. Rest pose: {rest_key}")

    meshes = [i for i, o in enumerate(objs) if o.type == "MESH" and len(o.data.vertices)]
    loc = {}
    raw = []
    for m in meshes:
        me = objs[m].data
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        loc[m] = np.c_[co.reshape(-1, 3), np.ones(len(me.vertices))]
        raw.append((W[r, m] @ loc[m].T).T[:, :3])
    allp = np.vstack(raw)
    mn, mx = allp.min(0), allp.max(0)
    s = args.height / (mx[2] - mn[2])
    S = np.diag([s, s, s, 1.0])
    S[:3, 3] = [-(mn[0] + mx[0]) / 2 * s, -(mn[1] + mx[1]) / 2 * s, -mn[2] * s]
    if not args.no_rotate:
        S = np.diag([-1.0, -1.0, 1.0, 1.0]) @ S

    SW = S @ W
    B = normalize(SW)
    Brest = B[r]
    X = B @ np.linalg.inv(Brest)[None]
    def Xof(i):
        return X[:, i] if i >= 0 else np.broadcast_to(I4, (F, 4, 4))

    animated = [i for i in range(N) if np.abs(X[:, i] - Xof(parent[i])).max() > 1e-4]
    def anc(i, keep):
        while i >= 0 and i not in keep:
            i = parent[i]
        return i

    P, corners, vox = {}, {}, []
    for m in meshes:
        Pm = (SW[r, m] @ loc[m].T).T
        P[m] = Pm
        lo, hi = Pm[:, :3].min(0), Pm[:, :3].max(0)
        corners[m] = np.array([[x, y, z, 1] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]).T
        me = objs[m].data
        ev = np.empty(len(me.edges) * 2, dtype=np.int64)
        me.edges.foreach_get("vertices", ev)
        ev = ev.reshape(-1, 2)
        if len(ev):
            dd = np.linalg.norm(Pm[ev[:, 0], :3] - Pm[ev[:, 1], :3], axis=1)
            dd = dd[dd > 1e-6]
            if len(dd):
                vox.append(dd.min())
    voxel = float(min(vox)) if vox else args.height / 60

    def err_mesh(m, b):
        D = (Xof(b) - X[:, m]) @ corners[m]
        return float(np.sqrt((D[:, :3, :] ** 2).sum(1)).max())

    kept = set(animated)
    def kpar(i):
        return anc(parent[i], kept)
    owned = {}
    for m in meshes:
        owned.setdefault(anc(m, kept), []).append(m)
    merged = []
    bar(0.25, "Merging bones")
    if not args.no_reduce:
        thr = args.max_error * voxel
        cache = {}
        def cost(b):
            p = kpar(b)
            return max([err_mesh(m, p) for m in owned.get(b, [])], default=0.0)
        while kept:
            for b in kept:
                if b not in cache:
                    cache[b] = cost(b)
            b = min(kept, key=lambda k: cache[k])
            c = cache[b]
            if c <= thr or (args.max_bones and len(kept) > args.max_bones):
                p = kpar(b)
                children = [k for k in kept if kpar(k) == b]
                kept.discard(b)
                cache.pop(b, None)
                owned.setdefault(p, []).extend(owned.pop(b, []))
                cache.pop(p, None)
                for k in children:
                    cache.pop(k, None)
                merged.append((objs[b].name, c / voxel))
            else:
                break
    log(f"Bones: {len(animated)} animated -> {len(kept)} after merging (threshold {args.max_error} voxels)")

    verr = {}
    for an, (a0, a1) in ranges.items():
        e = 0.0
        for m in meshes:
            b = anc(m, kept)
            D = (Xof(b)[a0:a1] - X[a0:a1, m]) @ corners[m]
            e = max(e, float(np.sqrt((D[:, :3, :] ** 2).sum(1)).max()))
        verr[an] = e / voxel

    bname, used = {}, {"Root"}
    for b in sorted(kept):
        n = re.sub(r"-(Global|Local)$", "", objs[b].name).replace("$$", "_")
        n = re.sub(r"[^A-Za-z0-9_]+", "_", n).strip("_") or "Bone"
        k, j = n, 2
        while k in used:
            k = f"{n}_{j}"; j += 1
        used.add(k); bname[b] = k

    # --- armature
    arm_data = bpy.data.armatures.new(base + "_Rig")
    arm = bpy.data.objects.new(base, arm_data)
    bpy.context.scene.collection.objects.link(arm)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    root = eb.new("Root"); root.head = (0, 0, 0); root.tail = (0, args.height * 0.05, 0)
    L = args.height * 0.03
    for b in kept:
        e = eb.new(bname[b]); e.head = (0, 0, 0); e.tail = (0, L, 0)
        e.matrix = Matrix(Brest[b].tolist())
    for b in kept:
        p = kpar(b)
        eb[bname[b]].parent = eb[bname[p]] if p >= 0 else root
    bpy.ops.object.mode_set(mode="OBJECT")

    # --- mesh + atlas
    bar(0.35, "Building atlas")
    keys, mat_cache, extras, imgcache = {}, {}, {}, {}
    def img_px(image):
        if image.name not in imgcache:
            w, h = image.size
            px = np.empty(w * h * 4, dtype=np.float32)
            image.pixels.foreach_get(px)
            imgcache[image.name] = px.reshape(h, w, 4)
        return imgcache[image.name]
    def layer(image, ch, const, h, w):
        if image is None:
            return np.full((h, w), const, np.float32)
        a = _fit(img_px(image), h, w)
        return a[..., ch] if ch is not None else a[..., :3].max(-1)
    def pbr_layers(ex, h, w):
        m = layer(ex["mimg"], ex["mch"], ex["metal"], h, w)
        r = layer(ex["rimg"], ex["rch"], ex["rough"], h, w)
        e = layer(ex["eimg"], None, ex["ecol"], h, w) * ex["estr"]
        return np.stack([m, r, e], -1).astype(np.float32)
    verts, faces, loop_uv, poly_keys, vgroup = [], [], [], [], []
    off = 0
    for m in meshes:
        o = objs[m]; me = o.data
        b = anc(m, kept)
        vgroup += [bname[b] if b >= 0 else "Root"] * len(me.vertices)
        flip = np.linalg.det(SW[r, m][:3, :3]) < 0
        verts.append(P[m][:, :3])
        uvl = me.uv_layers.active.data if me.uv_layers.active else None
        mats = [ms.material for ms in o.material_slots] or [None]
        for poly in me.polygons:
            mat = mats[poly.material_index] if poly.material_index < len(mats) else None
            if mat not in mat_cache:
                mat_cache[mat] = find_mat(mat)
            img, col, ex = mat_cache[mat]
            if img is not None and uvl is not None:
                k = ("img", img.name)
                if k not in keys:
                    w, h = img.size
                    px = np.empty(w * h * 4, dtype=np.float32)
                    img.pixels.foreach_get(px)
                    keys[k] = (px.reshape(h, w, 4), w, h)
                    extras[k] = (pbr_layers(ex, h, w), ex)
                uvs = [tuple(uvl[l].uv) for l in poly.loop_indices]
            else:
                col = col or (0.8, 0.8, 0.8, 1.0)
                k = ("col", tuple(round(c, 4) for c in col))
                if k not in keys:
                    keys[k] = (np.tile(np.array(col, dtype=np.float32), (2, 2, 1)), 2, 2)
                    extras[k] = (pbr_layers(ex, 2, 2), ex)
                uvs = [(0.5, 0.5)] * len(poly.vertices)
            vi = [off + v for v in poly.vertices]
            if flip:
                vi, uvs = vi[::-1], uvs[::-1]
            faces.append(vi); loop_uv.append(uvs); poly_keys.append(k)
        off += len(me.vertices)

    # --- PALETTE (optional, --palette): Roblox always smooths mesh textures (SurfaceAppearance.ResampleMode
    #     "Pixelated" exists but is not implemented yet), so pixel art looks blurry. Instead every
    #     VoxEdit face is cut into rectangles of ONE colour and each rectangle samples the centre of a
    #     flat colour tile: nothing to blur, sharp at any distance and any graphics quality.
    if args.palette:
        V = np.vstack(verts).astype(np.float64)
        newV, newVG, newF, newUV, newK = [], [], [], [], []

        def ckey(rgb, pb, ex):
            k = ("col", tuple(round(float(c), 4) for c in rgb[:3]), tuple(round(float(c), 4) for c in pb))
            if k not in keys:
                keys[k] = (np.tile(np.array([float(c) for c in rgb[:3]] + [1.0], np.float32), (2, 2, 1)), 2, 2)
                extras[k] = (np.tile(np.array([float(c) for c in pb], np.float32), (2, 2, 1)), ex)
            return k

        def greedy_rects(lab):
            hh, ww = lab.shape
            done = np.zeros((hh, ww), bool)
            out_r = []
            for y in range(hh):
                for x in range(ww):
                    if done[y, x]:
                        continue
                    c = lab[y, x]
                    x2 = x + 1
                    while x2 < ww and not done[y, x2] and lab[y, x2] == c:
                        x2 += 1
                    y2 = y + 1
                    while y2 < hh and (not done[y2, x:x2].any()) and (lab[y2, x:x2] == c).all():
                        y2 += 1
                    done[y:y2, x:x2] = True
                    out_r.append((x, y, x2, y2))
            return out_r

        groups = {}
        for fi, (vi, uvs, k) in enumerate(zip(faces, loop_uv, poly_keys)):
            if k[0] != "img":
                base_i = len(newV)
                newV += [V[i] for i in vi]; newVG += [vgroup[i] for i in vi]
                newF.append(list(range(base_i, base_i + len(vi)))); newUV.append(uvs); newK.append(k)
                continue
            w, h = keys[k][1], keys[k][2]
            us = [min(max(u, 0.0), 1.0) * w for u, v in uvs]
            vs = [min(max(v, 0.0), 1.0) * h for u, v in uvs]
            rect = (int(round(min(us))), int(round(min(vs))), int(round(max(us))), int(round(max(vs))))
            p = V[vi]
            nrm = np.cross(p[1] - p[0], p[2] - p[0])
            ln = np.linalg.norm(nrm)
            if ln < 1e-12:
                continue
            nrm = nrm / ln
            gk = (k, rect, tuple(np.round(nrm, 3)), round(float(nrm @ p[0]), 3), vgroup[vi[0]])
            groups.setdefault(gk, []).append(fi)
        for (k, (x0, y0, x1, y1), nt, _, vg), fis in groups.items():
            w, h = keys[k][1], keys[k][2]
            ex = extras[k][1]
            vi = faces[fis[0]]; uvs = loop_uv[fis[0]]
            M = np.array([[uvs[j][0] * w, uvs[j][1] * h, 1.0] for j in range(3)])
            if abs(np.linalg.det(M)) < 1e-9 or x1 <= x0 or y1 <= y0:
                # (rare) cannot map: keep the original faces with the colour of their centre texel
                cx = min(max((x0 + x1) // 2, 0), w - 1); cy = min(max((y0 + y1) // 2, 0), h - 1)
                kk = ckey(keys[k][0][cy, cx], extras[k][0][cy, cx], ex)
                for fi in fis:
                    base_i = len(newV)
                    newV += [V[i] for i in faces[fi]]; newVG += [vgroup[i] for i in faces[fi]]
                    newF.append(list(range(base_i, base_i + len(faces[fi])))); newUV.append([(0.5, 0.5)] * len(faces[fi])); newK.append(kk)
                continue
            Aff = np.linalg.solve(M, V[vi[:3]])  # (u_px, v_px, 1) -> position on the face plane
            reg = keys[k][0][y0:y1, x0:x1]
            preg = extras[k][0][y0:y1, x0:x1]
            hh, ww = reg.shape[:2]
            flat = np.concatenate([np.round(reg[..., :3], 4), np.round(preg, 4)], -1).reshape(-1, 6)
            uniq, lab = np.unique(flat, axis=0, return_inverse=True)
            lab = lab.reshape(hh, ww)
            nref = np.array(nt)
            for (tx0, ty0, tx1, ty1) in greedy_rects(lab):
                c = uniq[lab[ty0, tx0]]
                kk = ckey(c[:3], c[3:], ex)
                cs = [(x0 + tx0, y0 + ty0), (x0 + tx1, y0 + ty0), (x0 + tx1, y0 + ty1), (x0 + tx0, y0 + ty1)]
                P4 = [np.array([cx, cy, 1.0]) @ Aff for cx, cy in cs]
                if np.cross(P4[1] - P4[0], P4[2] - P4[0]) @ nref < 0:
                    P4 = P4[::-1]
                base_i = len(newV)
                newV += P4; newVG += [vg] * 4
                newF.append([base_i, base_i + 1, base_i + 2, base_i + 3]); newUV.append([(0.5, 0.5)] * 4); newK.append(kk)
        verts = [np.array(newV, np.float64)]
        vgroup = newVG; faces = newF; loop_uv = newUV; poly_keys = newK
        for k in [k for k in keys if k[0] == "img"]:
            del keys[k]; del extras[k]
        ntri = sum(len(f) - 2 for f in faces)
        log(f"Palette: {len(faces)} flat-colour faces ({ntri} triangles), {len(keys)} colours")
        if ntri > 20000:
            log("Warning: more than 20000 triangles (Roblox limit per MeshPart); drop --palette")

    # --- each VoxEdit texture is a 128x128 image where only a corner is used: crop it to the area the
    #     UVs really touch and merge identical crops. The atlas becomes much smaller, so it is enlarged
    #     xK without smoothing and the voxels look sharp in Roblox (1 px per voxel looked blurry).
    used = {}
    for k, uvs in zip(poly_keys, loop_uv):
        if k[0] != "img":
            continue
        w, h = keys[k][1], keys[k][2]
        b = used.setdefault(k, [1e9, 1e9, -1e9, -1e9])
        for u, v in uvs:
            u = min(max(u, 0.0), 1.0); v = min(max(v, 0.0), 1.0)
            b[0] = min(b[0], u * w); b[1] = min(b[1], v * h); b[2] = max(b[2], u * w); b[3] = max(b[3], v * h)
    crop = {}
    for k, (x0, y0, x1, y1) in used.items():
        px, w, h = keys[k]
        X0, Y0 = max(int(math.floor(x0 + 1e-4)), 0), max(int(math.floor(y0 + 1e-4)), 0)
        X1, Y1 = min(int(math.ceil(x1 - 1e-4)), w), min(int(math.ceil(y1 - 1e-4)), h)
        if X1 <= X0: X0, X1 = min(X0, w - 1), min(X0, w - 1) + 1
        if Y1 <= Y0: Y0, Y1 = min(Y0, h - 1), min(Y0, h - 1) + 1
        keys[k] = (px[Y0:Y1, X0:X1], X1 - X0, Y1 - Y0)
        extras[k] = (extras[k][0][Y0:Y1, X0:X1], extras[k][1])
        crop[k] = (X0, Y0, w, h)
    alias, seen = {}, {}
    for k in keys:
        hsh = hashlib.md5(np.ascontiguousarray(keys[k][0]).tobytes() + np.ascontiguousarray(extras[k][0]).tobytes()).hexdigest()
        if hsh in seen:
            alias[k] = seen[hsh]
        else:
            seen[hsh] = k

    def pack(A):
        x = y = sh = 0; pos = {}
        for k in sorted((k for k in keys if k not in alias), key=lambda k: (-keys[k][2], -keys[k][1])):
            w, h = keys[k][1] + 2, keys[k][2] + 2
            if w > A: return None
            if x + w > A: x = 0; y += sh; sh = 0
            if y + h > A: return None
            pos[k] = (x + 1, y + 1); x += w; sh = max(sh, h)
        return pos
    A = 16
    while True:
        pos = pack(A)
        if pos: break
        A += 16  # (not only powers of 2: a tighter atlas = bigger xK = sharper voxels)
    for k, a in alias.items():
        pos[k] = pos[a]
    atlas = np.zeros((A, A, 4), np.float32)
    patlas = np.zeros((A, A, 3), np.float32)
    patlas[..., 1] = 1.0
    for k, (x, y) in pos.items():
        px, w, h = keys[k]
        atlas[y - 1:y + h + 1, x - 1:x + w + 1] = np.pad(px, ((1, 1), (1, 1), (0, 0)), mode="edge")
        patlas[y - 1:y + h + 1, x - 1:x + w + 1] = np.pad(extras[k][0], ((1, 1), (1, 1), (0, 0)), mode="edge")
    atlas[..., 3] = 1
    if A > args.tex:
        log(f"Warning: the atlas needs {A}px, more than --tex {args.tex}")
    K = max(1, args.tex // A)
    big = np.repeat(np.repeat(atlas, K, 0), K, 1)
    T = A * K
    # Roblox rescales textures that are not a power of 2 (with smoothing): pixel art got blurry.
    # The atlas keeps its exact xK pixel grid inside a power-of-2 canvas (the rest stays empty).
    PT = 1 << (T - 1).bit_length()
    def padP(arr):
        if PT == T:
            return arr
        o = np.zeros((PT, PT) + arr.shape[2:], arr.dtype)
        o[:T, :T] = arr
        return o
    big = padP(big)
    img = bpy.data.images.new(base + "_Atlas", PT, PT, alpha=False)
    img.pixels.foreach_set(big.ravel())
    img.filepath_raw = os.path.join(out, base + "_Atlas.png"); img.file_format = "PNG"; img.save()

    # --- PBR maps (same UVs as the atlas)
    maps = {}
    pbr_note = "not generated (--no-pbr)"
    if not args.no_pbr:
        bar(0.45, "PBR maps")
        exs = [e for _, e in extras.values()]
        use_def = all(e["mimg"] is None and e["rimg"] is None and e["metal"] == 0 and e["rough"] >= 0.999 for e in exs)
        if T > args.max_size and T % args.max_size == 0:
            # Roblox downsizes images to 1024: compute them at that size so the relief survives the downsizing
            M, f = args.max_size, T // args.max_size
            bigp = np.repeat(np.repeat(patlas, K, 0), K, 1)
            cM = big.reshape(M, f, M, f, 4).mean((1, 3))
            pM = bigp.reshape(M, f, M, f, 3).mean((1, 3))
            nmap, rmap, mmap, emap = make_maps(cM, pM, 1, args, use_def)
        else:
            nmap, rmap, mmap, emap = make_maps(atlas, patlas, K, args, use_def)
        maps["normal"] = save_png(base + "_Normal", padP(nmap), out)
        maps["rough"] = save_png(base + "_Roughness", padP(rmap), out)
        maps["metal"] = save_png(base + "_Metalness", padP(mmap), out)
        if emap.max() > 0.004:
            if not args.emis_relative:
                emap = np.where(emap > 0.004, 1.0, 0.0).astype(np.float32)  # everything that glows, at 100%
            maps["emis"] = save_png(base + "_Emissive", padP(emap), out)
        pbr_note = (f"Normal, Roughness, Metalness{', Emissive' if 'emis' in maps else ''} "
                    f"({'default roughness/metal: the model has none' if use_def else 'roughness/metal from the model'})")
        log("PBR maps:", pbr_note)

    uv_flat = []
    for k, uvs in zip(poly_keys, loop_uv):
        x, y = pos[k]; w, h = keys[k][1], keys[k][2]
        cx = crop.get(k)
        for u, v in uvs:
            u = min(max(u, 0.0), 1.0); v = min(max(v, 0.0), 1.0)
            if cx:
                uu, vv = u * cx[2] - cx[0], v * cx[3] - cx[1]
            else:
                uu, vv = u * w, v * h
            uv_flat += [(x + uu) / A * T / PT, (y + vv) / A * T / PT]
    me = bpy.data.meshes.new(base + "_Body")
    me.from_pydata(np.vstack(verts).tolist(), [], faces)
    uvlay = me.uv_layers.new(name="UVMap")
    uvlay.data.foreach_set("uv", np.array(uv_flat, np.float32))
    body = bpy.data.objects.new(base + "_Body", me)
    bpy.context.scene.collection.objects.link(body)
    groups = {}
    for i, g in enumerate(vgroup):
        groups.setdefault(g, []).append(i)
    for g, ids in groups.items():
        body.vertex_groups.new(name=g).add(ids, 1.0, "REPLACE")
    bm = bmesh.new(); bm.from_mesh(me)
    dl = bm.verts.layers.deform.active
    byg = {}
    for v in bm.verts:
        d = v[dl]
        byg.setdefault(next(iter(d.keys())) if d else -1, []).append(v)
    for vs in byg.values():
        bmesh.ops.remove_doubles(bm, verts=vs, dist=voxel * 1e-3)
    bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = False
    mat = bpy.data.materials.new(base + "_Mat")
    if not mat.node_tree: mat.use_nodes = True
    nt = mat.node_tree; nt.nodes.clear()
    no = nt.nodes.new("ShaderNodeOutputMaterial"); bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tx = nt.nodes.new("ShaderNodeTexImage"); tx.image = img; tx.interpolation = "Closest"
    nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"]); nt.links.new(bs.outputs["BSDF"], no.inputs["Surface"])
    bs.inputs["Roughness"].default_value = 0.8
    if maps:
        def tex(im, y):
            t = nt.nodes.new("ShaderNodeTexImage"); t.image = im; t.interpolation = "Closest"
            t.location = (-600, y)
            return t
        tn = tex(maps["normal"], -300)
        nm = nt.nodes.new("ShaderNodeNormalMap"); nm.location = (-300, -300)
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
        nt.links.new(tex(maps["rough"], -600).outputs["Color"], bs.inputs["Roughness"])
        nt.links.new(tex(maps["metal"], -900).outputs["Color"], bs.inputs["Metallic"])
        if "emis" in maps:
            te = tex(maps["emis"], -1200)
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"; mix.location = (-300, -1100)
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(tx.outputs["Color"], mix.inputs[6]); nt.links.new(te.outputs["Color"], mix.inputs[7])
            em_in = bs.inputs.get("Emission Color") or bs.inputs.get("Emission")
            nt.links.new(mix.outputs[2], em_in)
            bs.inputs["Emission Strength"].default_value = 2.0
    me.materials.append(mat)
    if args.maps_only:
        log(f"OK {base}: maps only ({pbr_note}) -> {out}")
        return
    body.parent = arm
    body.modifiers.new("Armature", "ARMATURE").object = arm

    # --- animations
    arm.animation_data_create()
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    kl = sorted(kept)
    rri = {}
    for b in kl:
        p = kpar(b)
        rel = (np.linalg.inv(Brest[p]) if p >= 0 else I4) @ Brest[b]
        rri[b] = np.linalg.inv(rel)
    acts = []
    for ai, (an, (a0, a1)) in enumerate(ranges.items()):
        bar(0.55 + 0.10 * ai / len(ranges), "Building animations")
        act = bpy.data.actions.new(base + "_" + (re.sub(r"[^A-Za-z0-9]+", "_", an).strip("_") or "Anim"))
        act.use_fake_user = True
        arm.animation_data.action = act
        n = a1 - a0
        fr = np.arange(n, dtype=np.float32)
        for b in kl:
            p = kpar(b)
            Bp = B[a0:a1, p] if p >= 0 else np.broadcast_to(I4, (n, 4, 4))
            basis = rri[b][None] @ np.linalg.inv(Bp) @ B[a0:a1, b]
            lo = basis[:, :3, 3]
            q = np.array([Matrix(basis[i, :3, :3].tolist()).to_quaternion()[:] for i in range(n)])
            for i in range(1, n):
                if np.dot(q[i], q[i - 1]) < 0:
                    q[i] = -q[i]
            if np.abs(lo).max() < 1e-6 and np.abs(q - [1, 0, 0, 0]).max() < 1e-6:
                continue
            bn = bname[b]
            for pth, vals in (("location", lo), ("rotation_quaternion", q)):
                for c in range(vals.shape[1]):
                    fc = act.fcurve_ensure_for_datablock(arm, f'pose.bones["{bn}"].{pth}', index=c, group_name=bn)
                    fc.keyframe_points.add(n)
                    fc.keyframe_points.foreach_set("co", np.c_[fr, vals[:, c]].astype(np.float32).ravel())
                    fc.update()
        acts.append((act, n, an))

    # --- cleanup originals
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.orphans_purge(do_recursive=True)

    # --- export
    sc = bpy.context.scene
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bar(0.65, "Exporting FBX")
    export_fbx(os.path.join(out, base + "_Rig.fbx"), [arm, body], False, args.simplify)
    for ai, (act, n, an) in enumerate(acts):
        bar(0.67 + 0.20 * ai / len(acts), "Exporting animations")
        arm.animation_data.action = act
        sc.frame_start = 0; sc.frame_end = max(n - 1, 1)
        export_fbx(os.path.join(out, "Animations", act.name + ".fbx"),
                   [arm] if args.anim_skeleton_only else [arm, body], True, args.simplify)
    # single FBX with the rig and EVERY animation (Roblox's 3D Importer uploads them all at once)
    if not args.no_combined:
        bar(0.87, "Exporting Roblox FBX")
        arm.animation_data.action = acts[0][0]
        sc.frame_start = 0; sc.frame_end = max(max(n for _, n, _ in acts) - 1, 1)
        export_fbx(os.path.join(out, base + "_Roblox.fbx"), [arm, body], True, args.simplify, all_actions=True)
    arm.animation_data.action = None
    if not args.no_blend:
        bar(0.95, "Saving .blend")
        # leave an animation active when the .blend is opened (idle if there is one)
        pick = next((t for t in acts if re.search(r"idle", t[2], re.I) and not re.search(r"crawl|crouch|swim|sit|combat", t[2], re.I)), acts[0])
        arm.animation_data.action = pick[0]
        if hasattr(pick[0], "slots") and len(pick[0].slots):
            arm.animation_data.action_slot = pick[0].slots[0]
        sc.frame_start = 0; sc.frame_end = max(pick[1] - 1, 1); sc.frame_set(0)
        for o in sc.objects:
            o.select_set(o == arm)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, base + "_Rig.blend"))

    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    lines = [f"VoxToRoblox {VERSION} - {base}", f"Source: {path}",
             f"Height: {args.height} studs | voxel = {voxel:.4f} studs",
             f"Mesh: {tris} triangles, {len(me.vertices)} vertices",
             f"Bones: {len(kept) + 1} (Root + {len(kept)}; there were {len(animated)} animated nodes)",
             f"Texture: {PT}x{PT} (real atlas {A}px, upscaled x{K} without smoothing = {T}px, on a power-of-2 canvas)",
             f"PBR maps: {pbr_note}",
             f"Rest pose: {rest_key}", "", "Animations (max error against the original, in voxels):"]
    for act, n, an in acts:
        lines.append(f"  {act.name}: {n} frames, error {verr[an]:.2f}")
    if merged:
        lines += ["", "Merged bones (error in voxels):"] + [f"  {nm}: {e:.2f}" for nm, e in merged]
    with open(os.path.join(out, base + "_report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    log(f"OK {base}: {tris} tris, {len(kept) + 1} bones, {len(acts)} animations, {time.time() - t0:.1f}s -> {out}")

def render_thumb(src, dst, size):
    """small preview of a GLTF as VoxEdit exports it: Workbench render, 3/4 front view, transparent background."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    sc = bpy.context.scene
    for im in bpy.data.images:
        im.alpha_mode = "NONE"  # (VoxEdit palettes come with alpha 0)
    for m in bpy.data.materials:  # Workbench shows the ACTIVE image node: make it the base colour one, not the emission one
        if m.node_tree:
            for l in m.node_tree.links:
                if l.to_socket.name == "Base Color" and l.from_node.type == "TEX_IMAGE":
                    m.node_tree.nodes.active = l.from_node
    pts = [o.matrix_world @ Vector(c) for o in sc.objects if o.type == "MESH" for c in o.bound_box]
    if not pts:
        return
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    c, ext = (mn + mx) / 2, max(mx - mn)
    cam = bpy.data.objects.new("Thumb", bpy.data.cameras.new("Thumb"))
    sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = ext * 1.1
    d = Vector((-0.35, 1.0, 0.25)).normalized()  # (VoxEdit models face +Y)
    cam.location = c + d * ext * 3
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam.data.clip_end = ext * 10
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "TEXTURE"
    sc.view_settings.view_transform = "Standard"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
    tmp = dst + ".tmp.png"
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    os.replace(tmp, dst)  # (the window only sees finished files)

def make_thumbnails(args):
    with open(args.thumb_list, encoding="utf-8") as f:
        jobs = [l.rstrip("\r\n").split("\t") for l in f if "\t" in l]
    for src, dst in jobs:
        try:
            render_thumb(src, dst, args.thumb_size)
        except Exception:
            log("Thumbnail failed for", src); traceback.print_exc()

def main():
    global bar
    args = parse_args()
    if args.thumb_list:
        make_thumbnails(args); return
    if args.log_file:
        sys.stdout = sys.stderr = open(args.log_file, "a", encoding="utf-8", buffering=1)
    bar = Progress(args.progress_file)
    if bpy.app.version < (4, 4, 0):
        log("Blender 4.4 or newer is required."); bar.emit("FATAL", "Blender 4.4 or newer is required."); return
    files = expand(args.inputs)
    if not files:
        log("No .gltf/.glb files found"); bar.emit("END", 0, 0); return
    ok = 0
    for i, f in enumerate(files, 1):
        bar.emit("FILE", i, len(files), f)
        t0 = time.time()
        try:
            process(f, args); ok += 1
            bar.emit("DONE", f"{time.time() - t0:.1f}")
        except Exception as e:
            log("ERROR with", f); traceback.print_exc()
            bar.emit("ERROR", str(e)[:150] or type(e).__name__)
    log(f"Done: {ok}/{len(files)} converted.")
    bar.emit("END", ok, len(files))

if __name__ == "__main__":
    main()
