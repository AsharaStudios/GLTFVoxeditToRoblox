# VoxEdit KIT -> Roblox: one body + equipment sets (helmet, chest, arms, legs...) + weapons
# that share the SAME VoxEdit body (Equip_<bone> nodes). Everything comes out at the same scale:
#   <Kit>_Body.fbx          rigid rig: one mesh per bone (each weighted 100% to its bone) -> Motor6D in Roblox
#   <Set>.fbx               per set: one mesh per bone, no rig, in the body's rest pose
#   <Weapon>.fbx            loose weapons (glTF without a body): one "Handle" mesh
#   + atlas and PBR maps (Normal, Roughness, Metalness, Emissive) for each FBX
#   <Kit>_Kit.blend         everything together for review
# Usage: blender -b --factory-startup --python voxedit_kit_to_roblox.py -- GLTFS... [--name Kit] [--out FOLDER]
import bpy, bmesh, sys, os, re, argparse, importlib.util, json, time, traceback
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("v2r", os.path.join(HERE, "voxedit_to_roblox.py"))
v2r = importlib.util.module_from_spec(spec)
v2r.__name__ = "v2r"
spec.loader.exec_module(v2r)  # (functions only: its main() runs only as the main script)

VERSION = "1.5"
BODY_BONES = ["Hip", "Belly", "Chest", "Head",
              "Left_Arm", "Left_Forearm", "Left_Hand", "Right_Arm", "Right_Forearm", "Right_Hand",
              "Left_Thigh", "Left_Leg", "Left_Foot", "Right_Thigh", "Right_Leg", "Right_Foot"]

def log(*a):
    print("[VoxKit]", *a, flush=True)

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(prog="voxedit_kit_to_roblox")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--name", default=None, help="kit name (default: from the first glTF with a body)")
    ap.add_argument("--out", default=None, help="output folder (default: <first glTF folder>/Roblox/<Kit>_Kit)")
    ap.add_argument("--height", type=float, default=5.5, help="BODY height in studs (default 5.5)")
    ap.add_argument("--tex", type=int, default=1024)
    ap.add_argument("--rest", default=None, help="rest pose (default: the T)")
    ap.add_argument("--no-rotate", action="store_true")
    # maps (same as voxedit_to_roblox)
    ap.add_argument("--no-pbr", action="store_true")
    ap.add_argument("--emis-relative", action="store_true",
                    help="emissive mask with VoxEdit's intensity (default: pure white; the intensity is set by EmissiveStrength in Roblox)")
    ap.add_argument("--normal-strength", type=float, default=1.0)
    ap.add_argument("--bevel", type=float, default=0.25)
    ap.add_argument("--voxel-bevel", type=float, default=0.35)
    ap.add_argument("--roughness", type=float, default=0.6)
    ap.add_argument("--rough-var", type=float, default=0.35)
    ap.add_argument("--metal", type=float, default=0.0)
    ap.add_argument("--max-size", type=int, default=1024)
    ap.add_argument("--equip-pose", default=None,
                    help="pose the equipment SHAPE is taken from (default: Idle; in the VoxEdit T-pose the equipment collapses)")
    ap.add_argument("--inflate", type=float, default=0.2,
                    help="pushes the armour N voxels out from the body to avoid z-fighting (default 0.2; 0 = none)")
    ap.add_argument("--anim-fbx", action="store_true",
                    help="besides the .json, one FBX per animation (slow if there are many)")
    ap.add_argument("--drop-loose", action="store_true",
                    help="removes equipment pieces that float apart from everything")
    ap.add_argument("--progress-file", help="writes progress lines here (used by the Convert window)")
    ap.add_argument("--log-file", help="writes the full log here instead of the console")
    a = ap.parse_args(argv)
    a.maps_only = False
    return a

def safe(n):
    n = n.replace("ñ", "n").replace("Ñ", "N")
    return re.sub(r"[^A-Za-z0-9_]+", "_", n).strip("_") or "X"

def pick_pose(actions, want):
    if not actions:
        return None
    if want:
        for a in actions:
            if a.name.lower() == want.lower():
                return a
    for pat in (r"^tpose\d*$", r"^t\d*$", r"tpose", r"^apose\d*$", r"bind|rest"):
        for a in actions:
            if re.search(pat, re.sub(r"[^a-z0-9]", "", a.name.lower())):
                return a
    return actions[0]

def bone_of(o):
    """('body'|'equip', bone) for a mesh imported from the VoxEdit glTF."""
    p, equip = o.parent, None
    while p is not None:
        m = re.match(r"Equip_(.+?)-Global", p.name)
        if m and equip is None:
            equip = m.group(1)
        p = p.parent
    if equip:
        return "equip", equip
    m = re.match(r"(.+?)-Local", o.name)
    b = m.group(1) if m else None
    if b in BODY_BONES:
        return "body", b
    return "equip", None

def reset_scene():
    """empties the file WITHOUT restarting Blender (read_factory_settings would turn off add-ons, e.g. the MCP one)."""
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.actions,
                 bpy.data.armatures, bpy.data.cameras, bpy.data.lights, bpy.data.textures, bpy.data.node_groups,
                 bpy.data.collections):
        for x in list(coll):
            try:
                coll.remove(x)
            except Exception:
                pass
    bpy.data.orphans_purge(do_recursive=True)

def set_action(act, frame=None):
    sc = bpy.context.scene
    for o in bpy.data.objects:
        if o.animation_data:
            for t in o.animation_data.nla_tracks:
                t.mute = True
            if act is not None:
                o.animation_data.action = act
                if hasattr(act, "slots"):
                    sl = act.slots.get("OB" + o.name)
                    if sl:
                        o.animation_data.action_slot = sl
    sc.frame_set(int(frame if frame is not None else (act.frame_range[0] if act else 0)))
    bpy.context.view_layer.update()

def bone_mats():
    """world matrix of each body bone (<Bone>-Global node) at the current frame."""
    r = {}
    for o in bpy.data.objects:
        m = re.match(r"(.+?)-Global$", o.name)
        if m and m.group(1) in BODY_BONES:
            r[m.group(1)] = np.array(o.matrix_world)
    return r

def pick_equip_pose(actions, want, rest):
    if want:
        for a in actions:
            if a.name.lower() == want.lower():
                return a
    for a in actions:
        if "idle" in a.name.lower() and a != rest:
            return a
    others = [a for a in actions if a != rest]
    return others[0] if others else rest

def load(path, rest, equip_pose=None):
    """imports a glTF. The BODY is taken in the rest pose (T); the equipment SHAPE in the equipment pose
    (Idle: in the VoxEdit T-pose the inner equipment pieces collapse onto each other) and is then carried
    to the T bone by bone. Returns meshes (world coords), bone pivots and body animations."""
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    sc = bpy.context.scene
    acts = list(bpy.data.actions)
    act = pick_pose(acts, rest)
    eact = pick_equip_pose(acts, equip_pose, act)
    # bone matrices in the equipment pose and the equipment shape in that pose
    set_action(eact)
    We = bone_mats()
    eq_world = {}
    for o in bpy.data.objects:
        if o.type == "MESH" and len(o.data.vertices) and bone_of(o)[0] == "equip":
            eq_world[o.name] = np.array(o.matrix_world)
    set_action(act)
    Wr = bone_mats()
    # body animations (actions with more than 1 frame): matrices of each bone per frame
    anims = []
    if Wr:
        for a in acts:
            f0, f1 = int(round(a.frame_range[0])), int(round(a.frame_range[1]))
            if f1 - f0 < 1:
                continue
            frames = []
            set_action(a, f0)
            bones = [o for o in bpy.data.objects if re.match(r"(.+?)-Global$", o.name) and o.name[:-7] in BODY_BONES]
            for fr in range(f0, f1 + 1):
                sc.frame_set(fr)
                frames.append({o.name[:-7]: np.array(o.matrix_world) for o in bones})
            anims.append({"name": a.name, "frames": frames, "fps": sc.render.fps / sc.render.fps_base, "rest": Wr})
        set_action(act)
    meshes = []
    for o in bpy.data.objects:
        if o.type != "MESH" or not len(o.data.vertices):
            continue
        kind, bone = bone_of(o)
        me = o.data
        Wm = np.array(o.matrix_world)
        if kind == "equip" and o.name in eq_world and Wr:  # (loose weapons: as they are in their pose)
            Wm = eq_world[o.name]
            if bone in Wr and bone in We:
                Wm = Wr[bone] @ np.linalg.inv(We[bone]) @ Wm
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        P = (Wm @ np.c_[co.reshape(-1, 3), np.ones(len(me.vertices))].T).T[:, :3]
        uvl = me.uv_layers.active.data if me.uv_layers.active else None
        mats = [ms.material for ms in o.material_slots] or [None]
        polys = []
        for poly in me.polygons:
            mat = mats[poly.material_index] if poly.material_index < len(mats) else None
            uvs = [tuple(uvl[l].uv) for l in poly.loop_indices] if uvl else None
            polys.append((list(poly.vertices), uvs, mat))
        meshes.append({"kind": kind, "bone": bone, "name": o.name, "P": P, "polys": polys,
                       "flip": np.linalg.det(Wm[:3, :3]) < 0})
    pivots = {}
    for o in bpy.data.objects:
        m = re.match(r"(.+?)-Global$", o.name)
        if m and m.group(1) in BODY_BONES:
            pivots[m.group(1)] = np.array(o.matrix_world.translation)
    # images/materials must survive the next read_factory_settings: copy their pixels now
    cache = {}
    def mat_data(mat):
        if mat in cache:
            return cache[mat]
        img, col, ex = v2r.find_mat(mat)
        def px(im):
            if im is None:
                return None
            w, h = im.size
            a = np.empty(w * h * 4, np.float32)
            im.pixels.foreach_get(a)
            return a.reshape(h, w, 4)
        d = {"key": ("img", path + "|" + img.name) if img is not None else ("col", tuple(round(c, 4) for c in (col or (0.8, 0.8, 0.8, 1)))),
             "px": px(img), "col": col or (0.8, 0.8, 0.8, 1.0),
             "metal": ex["metal"], "rough": ex["rough"], "estr": ex["estr"], "ecol": ex["ecol"],
             "mpx": px(ex["mimg"]), "mch": ex["mch"], "rpx": px(ex["rimg"]), "rch": ex["rch"], "epx": px(ex["eimg"])}
        cache[mat] = d
        return d
    for m in meshes:
        m["polys"] = [(vi, uvs, mat_data(mat)) for vi, uvs, mat in m["polys"]]
    log(f"{os.path.basename(path)}: body in '{act.name if act else '-'}', equipment in '{eact.name if eact else '-'}', "
        f"{len(meshes)} meshes, animations: {', '.join(a['name'] + ' (' + str(len(a['frames'])) + ' frames)' for a in anims) or 'none'}")
    return meshes, pivots, anims, Wr

# ------------------------------------------------------------------ atlas + maps for a group of meshes
def build_textures(groups, base, out, args):
    """groups: list of meshes (dicts) that share a texture. Returns per-polygon uv and images."""
    keys = {}
    def layer(a, ch, const, h, w):
        if a is None:
            return np.full((h, w), const, np.float32)
        a = v2r._fit(a, h, w)
        return a[..., ch] if ch is not None else a[..., :3].max(-1)
    for m in groups:
        for vi, uvs, d in m["polys"]:
            k = d["key"]
            if k in keys:
                continue
            if d["px"] is not None and uvs is not None:
                px = d["px"]
                h, w = px.shape[:2]
            else:
                px = np.tile(np.array(d["col"], np.float32), (2, 2, 1))
                h, w = 2, 2
            pbr = np.stack([layer(d["mpx"], d["mch"], d["metal"], h, w),
                            layer(d["rpx"], d["rch"], d["rough"], h, w),
                            layer(d["epx"], None, d["ecol"], h, w) * d["estr"]], -1).astype(np.float32)
            keys[k] = (px, w, h, pbr, d)
    def pack(A):
        x = y = sh = 0
        pos = {}
        for k in sorted(keys, key=lambda k: (-keys[k][2], -keys[k][1], str(k))):
            w, h = keys[k][1] + 2, keys[k][2] + 2
            if w > A:
                return None
            if x + w > A:
                x = 0; y += sh; sh = 0
            if y + h > A:
                return None
            pos[k] = (x + 1, y + 1); x += w; sh = max(sh, h)
        return pos
    A = 16
    while True:
        pos = pack(A)
        if pos:
            break
        A *= 2
    atlas = np.zeros((A, A, 4), np.float32)
    patlas = np.zeros((A, A, 3), np.float32); patlas[..., 1] = 1
    for k, (x, y) in pos.items():
        px, w, h, pbr, d = keys[k]
        atlas[y - 1:y + h + 1, x - 1:x + w + 1] = np.pad(px, ((1, 1), (1, 1), (0, 0)), mode="edge")
        patlas[y - 1:y + h + 1, x - 1:x + w + 1] = np.pad(pbr, ((1, 1), (1, 1), (0, 0)), mode="edge")
    atlas[..., 3] = 1
    K = max(1, args.tex // A)
    big = np.repeat(np.repeat(atlas, K, 0), K, 1)
    T = A * K
    img = bpy.data.images.new(base + "_Atlas", T, T, alpha=False)
    img.pixels.foreach_set(big.ravel())
    img.filepath_raw = os.path.join(out, base + "_Atlas.png"); img.file_format = "PNG"; img.save()
    maps = {}
    if not args.no_pbr:
        exs = [keys[k][4] for k in keys]
        use_def = all(e["mpx"] is None and e["rpx"] is None and e["metal"] == 0 and e["rough"] >= 0.999 for e in exs)
        if T > args.max_size and T % args.max_size == 0:
            M, f = args.max_size, T // args.max_size
            bigp = np.repeat(np.repeat(patlas, K, 0), K, 1)
            nmap, rmap, mmap, emap = v2r.make_maps(big.reshape(M, f, M, f, 4).mean((1, 3)), bigp.reshape(M, f, M, f, 3).mean((1, 3)), 1, args, use_def)
        else:
            nmap, rmap, mmap, emap = v2r.make_maps(atlas, patlas, K, args, use_def)
        maps["normal"] = v2r.save_png(base + "_Normal", nmap, out)
        maps["rough"] = v2r.save_png(base + "_Roughness", rmap, out)
        maps["metal"] = v2r.save_png(base + "_Metalness", mmap, out)
        if emap.max() > 0.004:
            if not args.emis_relative:
                emap = np.where(emap > 0.004, 1.0, 0.0).astype(np.float32)  # everything that glows, at 100%
            maps["emis"] = v2r.save_png(base + "_Emissive", emap, out)
    def uv_of(d, uvs, n):
        x, y = pos[d["key"]]
        w, h = keys[d["key"]][1], keys[d["key"]][2]
        if d["px"] is None or uvs is None:
            uvs = [(0.5, 0.5)] * n
        return [((x + min(max(u, 0), 1) * w) / A, (y + min(max(v, 0), 1) * h) / A) for u, v in uvs]
    return uv_of, img, maps, f"{T}px (atlas {A} x{K})"

def make_material(name, img, maps):
    mat = bpy.data.materials.new(name)
    if not mat.node_tree:
        mat.use_nodes = True
    nt = mat.node_tree; nt.nodes.clear()
    no = nt.nodes.new("ShaderNodeOutputMaterial"); bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tx = nt.nodes.new("ShaderNodeTexImage"); tx.image = img; tx.interpolation = "Closest"
    nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"]); nt.links.new(bs.outputs["BSDF"], no.inputs["Surface"])
    def tex(im):
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = im; t.interpolation = "Closest"
        return t
    if maps:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tex(maps["normal"]).outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
        nt.links.new(tex(maps["rough"]).outputs["Color"], bs.inputs["Roughness"])
        nt.links.new(tex(maps["metal"]).outputs["Color"], bs.inputs["Metallic"])
        if "emis" in maps:
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(tx.outputs["Color"], mix.inputs[6]); nt.links.new(tex(maps["emis"]).outputs["Color"], mix.inputs[7])
            nt.links.new(mix.outputs[2], bs.inputs.get("Emission Color") or bs.inputs.get("Emission"))
            bs.inputs["Emission Strength"].default_value = 2.0
    return mat

def make_mesh(name, items, S, uv_of, mat, voxel, inflate=0.0):
    """items: [(mesh, polygons)] -> one Blender object in studs."""
    bm = bmesh.new(); uvlay = bm.loops.layers.uv.new("UVMap")
    for m in items:
        P = (S @ np.c_[m["P"], np.ones(len(m["P"]))].T).T[:, :3]
        flip = m["flip"] ^ (np.linalg.det(S[:3, :3]) < 0)
        vmap = {}
        for vi, uvs, d in m["polys"]:
            uv = uv_of(d, uvs, len(vi))
            if flip:
                vi, uv = vi[::-1], uv[::-1]
            vs = []
            for i in vi:
                if i not in vmap:
                    vmap[i] = bm.verts.new(P[i].tolist())
                vs.append(vmap[i])
            try:
                f = bm.faces.new(vs)
            except ValueError:
                continue
            for l, (u, v) in zip(f.loops, uv):
                l[uvlay].uv = (u, v)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=voxel * 1e-3)
    if inflate > 0:  # (armour pushed out a little: no faces coplanar with the body -> no z-fighting)
        bm.normal_update()
        for v in bm.verts:
            v.co += v.normal * inflate
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o

def export(path, objects, armature=None):
    for o in bpy.context.scene.objects:
        o.select_set(o in objects or o == armature)
    bpy.context.view_layer.objects.active = armature or objects[0]
    types_ = {"MESH"} | ({"ARMATURE"} if armature else set())
    anim = bool(armature and armature.animation_data and armature.animation_data.action)
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types=types_,
                             apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
                             mesh_smooth_type="FACE", add_leaf_bones=False, path_mode="COPY", embed_textures=True,
                             use_armature_deform_only=False, bake_anim=anim, bake_anim_use_all_actions=anim,
                             bake_anim_use_nla_strips=False, bake_anim_force_startend_keying=True,
                             bake_anim_simplify_factor=0.0)

def drop_loose(meshes, tol=1.01):
    """removes equipment meshes that float apart from everything (in VoxEdit they are usually animated effects,
    e.g. falling leaves): as fixed armour they would look like mistakes. Returns the removed names."""
    box = lambda m: (m["P"].min(0) - tol, m["P"].max(0) + tol)
    hits = lambda a, b: bool(np.all(a[0] <= b[1]) and np.all(b[0] <= a[1]))
    anchored = [box(m) for m in meshes if m["kind"] == "body"]
    eq = [m for m in meshes if m["kind"] == "equip"]
    if not anchored:  # (loose weapon: anchored to its biggest piece)
        if not eq:
            return []
        big = max(eq, key=lambda m: len(m["P"]))
        anchored = [box(big)]
    keep, rest = set(), list(eq)
    changed = True
    while changed:
        changed = False
        for m in list(rest):
            b = box(m)
            if any(hits(b, a) for a in anchored):
                anchored.append(b); keep.add(id(m)); rest.remove(m); changed = True
    for m in rest:
        meshes.remove(m)
    return [m["name"] for m in rest]

bar = v2r.Progress()

def main():
    global bar
    args = parse_args()
    if args.log_file:
        sys.stdout = sys.stderr = open(args.log_file, "a", encoding="utf-8", buffering=1)
    bar = v2r.Progress(args.progress_file)
    name = args.name or "Kit"
    bar.emit("FILE", 1, 1, name)
    t0 = time.time()
    try:
        build(args)
        bar.emit("DONE", f"{time.time() - t0:.1f}")
        bar.emit("END", 1, 1)
    except Exception as e:
        log("ERROR with kit", name); traceback.print_exc()
        bar.emit("ERROR", str(e)[:150] or type(e).__name__)
        bar.emit("END", 0, 1)

def build(args):
    files = [os.path.abspath(p.strip('"')) for p in args.inputs if p.lower().endswith((".gltf", ".glb"))]
    if not files:
        raise ValueError("no .gltf/.glb files given")
    data = []
    for i, f in enumerate(files):
        bar(0.5 * i / len(files), "Reading " + os.path.basename(f))
        meshes, piv, anims, Wr = load(f, args.rest, args.equip_pose)
        if args.drop_loose:
            gone = drop_loose(meshes)
            if gone:
                log(f"{os.path.basename(f)}: removed {len(gone)} loose piece(s): " + ", ".join(gone))
        data.append((f, meshes, piv, anims, Wr))
    bodies = [d for d in data if any(m["kind"] == "body" for m in d[1])]
    if not bodies:
        raise ValueError("none of the files has the VoxEdit body: a kit needs at least one equipment piece exported on the avatar")
    # body and animations: from the glTF with the most animations (e.g. the AvatarBase); they all share the same body
    fbody, bmeshes, pivots, body_anims, body_Wr = max(bodies, key=lambda d: len(d[3]))
    # each glTF's equipment is carried to the chosen body's bones (in case that glTF came in another pose)
    for d in data:
        if d[0] == fbody or not d[4]:
            continue
        for m in d[1]:
            b = m["bone"]
            if m["kind"] == "equip" and b in d[4] and b in body_Wr:
                M = body_Wr[b] @ np.linalg.inv(d[4][b])
                m["P"] = (M @ np.c_[m["P"], np.ones(len(m["P"]))].T).T[:, :3]
    named = next((d for d in bodies if any(m["kind"] == "equip" for m in d[1])), bodies[0])
    kit = safe(args.name) if args.name else safe(re.sub(r"(?i)(legs|arms|chest|helmet|head)", "", os.path.splitext(os.path.basename(named[0]))[0])) or "Kit"
    out = args.out or os.path.join(os.path.dirname(files[0]), "Roblox", kit + "_Kit")
    os.makedirs(out, exist_ok=True)

    # ---- scale from the BODY only (the same for every piece)
    body = [m for m in bmeshes if m["kind"] == "body"]
    allp = np.vstack([m["P"] for m in body])
    mn, mx = allp.min(0), allp.max(0)
    s = args.height / (mx[2] - mn[2])
    S = np.diag([s, s, s, 1.0])
    S[:3, 3] = [-(mn[0] + mx[0]) / 2 * s, -(mn[1] + mx[1]) / 2 * s, -mn[2] * s]
    if not args.no_rotate:
        S = np.diag([-1.0, -1.0, 1.0, 1.0]) @ S
    voxel = s  # (VoxEdit: 1 unit = 1 voxel)
    log(f"scale: 1 voxel = {voxel:.4f} studs")

    reset_scene()
    lines = [f"VoxEdit KIT -> Roblox {VERSION} - {kit}", f"1 voxel = {voxel:.4f} studs | body {args.height} studs", ""]

    # ---- BODY: armature + one mesh per bone (100% to its bone)
    bar(0.55, "Building body")
    piv ={b: (S @ np.r_[p, 1])[:3] for b, p in pivots.items()}
    arm_data = bpy.data.armatures.new(kit + "_Rig")
    arm = bpy.data.objects.new(kit, arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    parent_of = {"Hip": "HumanoidRootPart", "Belly": "Hip", "Chest": "Belly", "Head": "Chest",
                 "Left_Arm": "Chest", "Left_Forearm": "Left_Arm", "Left_Hand": "Left_Forearm",
                 "Right_Arm": "Chest", "Right_Forearm": "Right_Arm", "Right_Hand": "Right_Forearm",
                 "Left_Thigh": "Hip", "Left_Leg": "Left_Thigh", "Left_Foot": "Left_Leg",
                 "Right_Thigh": "Hip", "Right_Leg": "Right_Thigh", "Right_Foot": "Right_Leg"}
    hip = piv.get("Hip", np.array([0, 0, args.height * 0.5]))
    root = eb.new("HumanoidRootPart"); root.head = (0, 0, float(hip[2])); root.tail = (0, 0, float(hip[2]) + args.height * 0.1)
    L = args.height * 0.06
    for b in BODY_BONES:
        e = eb.new(b)
        h = piv.get(b, hip)
        e.head = tuple(float(x) for x in h); e.tail = (float(h[0]), float(h[1]), float(h[2]) + L)
    for b in BODY_BONES:
        eb[b].parent = eb[parent_of[b]]
    bpy.ops.object.mode_set(mode="OBJECT")

    uv_of, img, maps, texinfo = build_textures(body, kit + "_Body", out, args)
    mat = make_material(kit + "_Body_Mat", img, maps)
    body_objs = []
    for b in BODY_BONES:
        items = [m for m in body if m["bone"] == b]
        if not items:
            log("Warning: the body has no mesh for", b)
            continue
        o = make_mesh(b, items, S, uv_of, mat, voxel)
        o.parent = arm
        o.modifiers.new("Armature", "ARMATURE").object = arm
        o.vertex_groups.new(name=b).add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        body_objs.append(o)
    # HumanoidRootPart (Roblox needs it): a 2x2x1 box at the hip, weighted to the root bone
    hrp_me = bpy.data.meshes.new("HumanoidRootPart")
    bmh = bmesh.new(); bmesh.ops.create_cube(bmh, size=1.0)
    bmesh.ops.scale(bmh, vec=(2.0, 1.0, 2.0), verts=bmh.verts)
    bmesh.ops.translate(bmh, vec=(0, 0, float(hip[2])), verts=bmh.verts)
    bmh.to_mesh(hrp_me); bmh.free()
    hrp = bpy.data.objects.new("HumanoidRootPart", hrp_me)
    bpy.context.scene.collection.objects.link(hrp)
    hrp.parent = arm; hrp.modifiers.new("Armature", "ARMATURE").object = arm
    hrp.vertex_groups.new(name="HumanoidRootPart").add(list(range(len(hrp_me.vertices))), 1.0, "REPLACE")
    hrp_me.materials.append(mat)
    # ---- body animations: baked into the rig (bone by bone, per frame)
    anim_files = []
    if body_anims:
        bar(0.62, "Saving animations")
        arm.animation_data_create()
        Sinv = np.linalg.inv(S)
        rest = {b.name: np.array(b.matrix_local) for b in arm_data.bones}
        par = {b.name: (b.parent.name if b.parent else None) for b in arm_data.bones}
        bpy.context.scene.render.fps = max(1, int(round(body_anims[0]["fps"]))); bpy.context.scene.render.fps_base = 1
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
        acts = []
        for an in (body_anims if args.anim_fbx else []):  # (baking in Blender is only needed for the FBX files)
            act = bpy.data.actions.new(safe(an["name"]))
            act.use_fake_user = True
            arm.animation_data.action = act
            R0 = an["rest"]
            prevq = {}
            for fi, mats in enumerate(an["frames"]):
                pose = {"HumanoidRootPart": rest["HumanoidRootPart"]}
                for b in BODY_BONES:
                    pa = par[b]
                    if b in mats and b in R0:
                        pose[b] = S @ mats[b] @ np.linalg.inv(R0[b]) @ Sinv @ rest[b]
                    else:
                        pose[b] = pose[pa] @ np.linalg.inv(rest[pa]) @ rest[b]
                    basis = np.linalg.inv(rest[b]) @ rest[pa] @ np.linalg.inv(pose[pa]) @ pose[b]
                    loc, rot, _sc = Matrix(basis.tolist()).decompose()
                    if b in prevq and prevq[b].dot(rot) < 0:
                        rot.negate()
                    prevq[b] = rot.copy()
                    pb = arm.pose.bones[b]
                    pb.location = loc; pb.rotation_quaternion = rot
                    pb.keyframe_insert("location", frame=fi)
                    pb.keyframe_insert("rotation_quaternion", frame=fi)
            acts.append((an["name"], act, len(an["frames"])))
        # JSON for Roblox Studio: per animation, per frame, each bone's motion in Roblox coords
        # (world delta from the rest pose: CFrame = pos + quaternion; Roblox = Blender's (x, z, -y))
        C = np.array([[1, 0, 0, 0], [0, 0, 1, 0], [0, -1, 0, 0], [0, 0, 0, 1]], float)
        Ci = np.linalg.inv(C)
        jan = []
        for an in body_anims:
            R0 = an["rest"]
            fr_out = []
            for mats in an["frames"]:
                fo = {}
                for b in BODY_BONES:
                    if b in mats and b in R0:
                        D = C @ S @ mats[b] @ np.linalg.inv(R0[b]) @ Sinv @ Ci
                        loc, rot, _sc = Matrix(D.tolist()).decompose()
                        fo[b] = [round(loc.x, 4), round(loc.y, 4), round(loc.z, 4),
                                 round(rot.x, 5), round(rot.y, 5), round(rot.z, 5), round(rot.w, 5)]
                fr_out.append(fo)
            jan.append({"name": an["name"], "fps": an["fps"], "frames": fr_out})
        rest_cf = {}
        for b in ["HumanoidRootPart"] + BODY_BONES:
            if b in arm_data.bones:
                h = C @ np.r_[np.array(arm_data.bones[b].head_local), 1]
                rest_cf[b] = [round(float(x), 4) for x in h[:3]]
        jpath = os.path.join(out, kit + "_Animations.json")
        with open(jpath, "w", encoding="utf-8") as fh:
            json.dump({"kit": kit, "version": VERSION, "space": "roblox-world-delta", "pivots": rest_cf, "anims": jan}, fh, separators=(",", ":"))
        anim_files.append(f"{kit}_Animations.json: {len(jan)} animations ({sum(len(a['frames']) for a in jan)} frames)")
        # one FBX per animation (optional: the Roblox importer takes one per file)
        for nm, act, nf in (acts if args.anim_fbx else []):
            arm.animation_data.action = act
            bpy.context.scene.frame_start, bpy.context.scene.frame_end = 0, nf - 1
            fn = f"{kit}_Anim_{safe(nm)}.fbx"
            export(os.path.join(out, fn), body_objs + [hrp], arm)
            anim_files.append(f"{fn}: {nf} frames at {bpy.context.scene.render.fps} fps")
        arm.animation_data.action = None
        for pb in arm.pose.bones:
            pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
        log(f"animations saved to {kit}_Animations.json:", ", ".join(a["name"] for a in body_anims))
    export(os.path.join(out, kit + "_Body.fbx"), body_objs + [hrp], arm)
    for o in body_objs + [hrp]:
        o.name = "Body__" + o.name  # (the sets reuse the bone names)
    lines.append(f"{kit}_Body.fbx: {len(body_objs)} pieces + HumanoidRootPart, texture {texinfo}")
    lines += anim_files or ["(the glTF files have no body animations: only 1-frame poses)"]
    log("body done")

    # ---- EQUIPMENT sets (one per glTF that has Equip_ nodes) and WEAPONS (glTF without body)
    coll_sets = []
    for set_idx, (f, meshes, _, _, _) in enumerate(data):
        name = safe(os.path.splitext(os.path.basename(f))[0])
        bar(0.7 + 0.25 * set_idx / len(data), "Exporting " + name)
        equip = [m for m in meshes if m["kind"] == "equip"]
        if not equip:
            continue
        has_body = any(m["kind"] == "body" for m in meshes)
        if has_body:
            uv_of, img, maps, texinfo = build_textures(equip, name, out, args)
            mat = make_material(name + "_Mat", img, maps)
            objs = []
            for b in BODY_BONES + [None]:
                items = [m for m in equip if m["bone"] == b]
                if not items:
                    continue
                o = make_mesh(b or "Extra", items, S, uv_of, mat, voxel,
                              inflate=args.inflate * voxel * (1 + 0.5 * set_idx))
                objs.append(o)
            export(os.path.join(out, name + ".fbx"), objs)
            for o in objs:
                o.name = name + "__" + o.name
            coll_sets.append((name, objs))
            lines.append(f"{name}.fbx: {len(objs)} pieces ({', '.join(o.name.split('__')[1] for o in objs)}), texture {texinfo}")
        else:
            # weapon: same scale as the body, centred, standing up, origin at the bottom of the grip
            uv_of, img, maps, texinfo = build_textures(equip, name, out, args)
            mat = make_material(name + "_Mat", img, maps)
            Sw = np.diag([s, s, s, 1.0])
            allw = np.vstack([(Sw @ np.c_[m["P"], np.ones(len(m["P"]))].T).T[:, :3] for m in equip])
            wmn, wmx = allw.min(0), allw.max(0)
            Sw[:3, 3] = [-(wmn[0] + wmx[0]) / 2, -(wmn[1] + wmx[1]) / 2, -wmn[2]]
            if not args.no_rotate:
                Sw = np.diag([-1.0, -1.0, 1.0, 1.0]) @ Sw
            o = make_mesh("Handle", equip, Sw, uv_of, mat, voxel)
            export(os.path.join(out, name + ".fbx"), [o])
            o.name = name + "__Handle"
            coll_sets.append((name, [o]))
            dims = wmx - wmn
            lines.append(f"{name}.fbx: weapon 'Handle' {dims[0]:.2f} x {dims[1]:.2f} x {dims[2]:.2f} studs, texture {texinfo}")
        log(name, "done")

    # ---- offsets RELATIVE TO THE BONE (Roblox axes, studs): Studio places each piece at
    #      boneRest.Position + delta  -> exactly as in the .blend, independent of the global origin
    offs = {}
    for name, objs in coll_sets:
        for o in objs:
            bn = o.name.split("__", 1)[1]
            b = arm.data.bones.get(bn)
            if b is None:
                continue
            vs = [o.matrix_world @ v.co for v in o.data.vertices]
            c = Vector([(min(v[i] for v in vs) + max(v[i] for v in vs)) / 2 for i in range(3)])
            d = c - arm.matrix_world @ b.head_local
            offs.setdefault(name, {})[bn] = [round(-d.x, 5), round(d.z, 5), round(d.y, 5)]
    with open(os.path.join(out, kit + "_Offsets.json"), "w", encoding="utf-8") as fh:
        json.dump({"kit": kit, "version": VERSION, "space": "roblox-bone-delta", "sets": offs}, fh, indent=1)
    lines.append(f"{kit}_Offsets.json: position of each piece relative to its bone (for Studio)")

    # ---- preview .blend: body + every set on it (weapons beside it)
    bar(0.97, "Saving .blend")
    x = 3.0
    for name, objs in coll_sets:
        c = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(c)
        for o in objs:
            for uc in o.users_collection:
                uc.objects.unlink(o)
            c.objects.link(o)
            if o.name.endswith("__Handle"):
                o.location.x = x; x += 1.5
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, kit + "_Kit.blend"))
    with open(os.path.join(out, kit + "_report.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    log("DONE ->", out)

if __name__ == "__main__":
    main()
