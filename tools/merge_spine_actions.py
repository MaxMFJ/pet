#!/usr/bin/env python3
import argparse
import copy
import json
import statistics
import shutil
from pathlib import Path


def load_json(path):
    text = path.read_text(encoding="utf-8")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        fixed = text.replace('"images":"images":', '"images":')
        if fixed != text:
            return json.loads(fixed)
        raise


def dump_json(path, data):
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))


def default_skin(data):
    skins = data.get("skins") or []
    if isinstance(skins, list):
        return skins[0] if skins else {"name": "default", "attachments": {}}
    if isinstance(skins, dict):
        skin_name = "default" if "default" in skins else next(iter(skins), "default")
        return {"name": skin_name, "attachments": skins.get(skin_name, {})}
    return {"name": "default", "attachments": {}}


def scoped_name(scope, name):
    return f"{scope}__{name}"


def unique_name(name, used):
    if name not in used:
        used.add(name)
        return name
    index = 2
    while f"{name}_{index}" in used:
        index += 1
    result = f"{name}_{index}"
    used.add(result)
    return result


def remap_weighted_vertices(attachment, bone_index_map):
    vertices = attachment.get("vertices")
    uvs = attachment.get("uvs")
    if not isinstance(vertices, list) or not isinstance(uvs, list):
        return
    if len(vertices) == len(uvs):
        return

    remapped = []
    i = 0
    try:
        while i < len(vertices):
            bone_count = int(vertices[i])
            remapped.append(vertices[i])
            i += 1
            for _ in range(bone_count):
                bone_index = int(vertices[i])
                remapped.append(bone_index_map.get(bone_index, bone_index))
                remapped.extend(vertices[i + 1:i + 4])
                i += 4
    except (IndexError, ValueError, TypeError):
        return
    attachment["vertices"] = remapped


def attachment_name_maps_for_skin(skin, scope):
    maps = {}
    for slot_name, attachments in skin.get("attachments", {}).items():
        maps[slot_name] = {
            attachment_name: scoped_name(scope, attachment_name)
            for attachment_name in attachments.keys()
        }
    return maps


def remap_skin(skin, scope, slot_name_map, bone_index_map, attachment_name_maps):
    remapped = {"name": "default", "attachments": {}}
    for slot_name, attachments in skin.get("attachments", {}).items():
        target_slot = slot_name_map.get(slot_name, scoped_name(scope, slot_name))
        remapped["attachments"][target_slot] = {}
        for attachment_name, attachment in attachments.items():
            target_attachment_name = attachment_name_maps.get(slot_name, {}).get(
                attachment_name,
                scoped_name(scope, attachment_name),
            )
            cloned = copy.deepcopy(attachment)
            if isinstance(cloned, dict):
                texture_name = cloned.get("path") or attachment_name
                cloned["path"] = scoped_name(scope, texture_name)
                if cloned.get("parent"):
                    cloned["parent"] = scoped_name(scope, cloned["parent"])
                remap_weighted_vertices(cloned, bone_index_map)
            remapped["attachments"][target_slot][target_attachment_name] = cloned
        for attachment in remapped["attachments"][target_slot].values():
            if isinstance(attachment, dict):
                remap_weighted_vertices(attachment, bone_index_map)
    return remapped


def remap_animation(animation, scope, bone_name_map, slot_name_map, constraint_name_map, attachment_name_maps):
    remapped = copy.deepcopy(animation)
    for key, name_map in (
        ("bones", bone_name_map),
        ("slots", slot_name_map),
        ("ik", constraint_name_map),
        ("transform", constraint_name_map),
        ("path", constraint_name_map),
    ):
        if key in remapped and isinstance(remapped[key], dict):
            remapped[key] = {
                name_map.get(name, name): value
                for name, value in remapped[key].items()
            }
    if isinstance(remapped.get("slots"), dict):
        for original_slot, target_slot in slot_name_map.items():
            timelines = remapped["slots"].get(target_slot)
            if not isinstance(timelines, dict):
                continue
            attachment_frames = timelines.get("attachment")
            if not isinstance(attachment_frames, list):
                continue
            name_map = attachment_name_maps.get(original_slot, {})
            for frame in attachment_frames:
                if not isinstance(frame, dict):
                    continue
                attachment_name = frame.get("name")
                if attachment_name is not None:
                    frame["name"] = name_map.get(attachment_name, scoped_name(scope, attachment_name))
    if isinstance(remapped.get("drawOrder"), list):
        for frame in remapped["drawOrder"]:
            offsets = frame.get("offsets") if isinstance(frame, dict) else None
            if not isinstance(offsets, list):
                continue
            for offset in offsets:
                if isinstance(offset, dict) and "slot" in offset:
                    offset["slot"] = slot_name_map.get(offset["slot"], offset["slot"])
    for deform_key in ("deform", "ffd"):
        if not isinstance(remapped.get(deform_key), dict):
            continue
        remapped_deform = {}
        for skin_name, skin_timelines in remapped[deform_key].items():
            if not isinstance(skin_timelines, dict):
                remapped_deform[skin_name] = skin_timelines
                continue
            remapped_skin_timelines = {}
            for original_slot, attachment_timelines in skin_timelines.items():
                target_slot = slot_name_map.get(original_slot, scoped_name(scope, original_slot))
                if not isinstance(attachment_timelines, dict):
                    remapped_skin_timelines[target_slot] = attachment_timelines
                    continue
                name_map = attachment_name_maps.get(original_slot, {})
                remapped_attachments = {}
                for attachment_name, frames in attachment_timelines.items():
                    target_attachment = name_map.get(attachment_name, scoped_name(scope, attachment_name))
                    remapped_attachments[target_attachment] = frames
                remapped_skin_timelines[target_slot] = remapped_attachments
            remapped_deform[skin_name] = remapped_skin_timelines
        remapped[deform_key] = remapped_deform
    return remapped


def remap_atlas_text(atlas_text, scope):
    output = []
    lines = atlas_text.strip().splitlines()
    in_page_header = False
    for line in lines:
        stripped = line.strip()
        if not stripped:
            output.append(line)
            continue
        if stripped.endswith(".png"):
            in_page_header = True
            output.append(line)
            continue
        if in_page_header and ":" in stripped:
            output.append(line)
            continue
        in_page_header = False
        if ":" not in stripped:
            indent = line[:len(line) - len(line.lstrip())]
            output.append(f"{indent}{scoped_name(scope, stripped)}")
        else:
            output.append(line)
    return "\n".join(output)


def union_bounds(json_datas):
    boxes = []
    for data in json_datas:
        skel = data.get("skeleton", {})
        x = skel.get("x", 0)
        y = skel.get("y", 0)
        width = skel.get("width", 0)
        height = skel.get("height", 0)
        boxes.append((x, y, x + width, y + height))
    min_x = min(x1 for x1, _, _, _ in boxes)
    min_y = min(y1 for _, y1, _, _ in boxes)
    max_x = max(x2 for _, _, x2, _ in boxes)
    max_y = max(y2 for _, _, _, y2 in boxes)
    return min_x, min_y, max_x - min_x, max_y - min_y


def skeleton_box(data):
    skel = data.get("skeleton", {})
    x = skel.get("x", 0) or 0
    y = skel.get("y", 0) or 0
    width = skel.get("width", 0) or 0
    height = skel.get("height", 0) or 0
    if width <= 0 or height <= 0:
        skin = default_skin(data)
        fallback_width = 0
        fallback_height = 0
        fallback_x_values = []
        fallback_y_values = []
        for attachments in skin.get("attachments", {}).values():
            for attachment in attachments.values():
                if not isinstance(attachment, dict):
                    continue
                attachment_width = attachment.get("width", 0) or 0
                attachment_height = attachment.get("height", 0) or 0
                fallback_width = max(fallback_width, attachment_width)
                fallback_height = max(fallback_height, attachment_height)
                fallback_x_values.append(attachment.get("x", 0) or 0)
                fallback_y_values.append(attachment.get("y", 0) or 0)
        if width <= 0:
            width = fallback_width
        if height <= 0:
            height = fallback_height
        if fallback_x_values:
            x = statistics.median(fallback_x_values) - (width * 0.5)
        if fallback_y_values:
            y = statistics.median(fallback_y_values) - (height * 0.5)
    return {
        "x": x,
        "y": y,
        "width": width,
        "height": height,
        "center_x": x + (width * 0.5),
        "center_y": y + (height * 0.5),
    }


def show_normalization(loaded):
    stable_action_names = {"stand2", "run", "hurt", "action1"}
    peer_boxes = [
        skeleton_box(data)
        for path, data in loaded
        if path.parent.name in stable_action_names and skeleton_box(data)["height"] > 0
    ]
    if len(peer_boxes) < 2:
        peer_boxes = [
            skeleton_box(data)
            for path, data in loaded
            if path.parent.name != "show" and skeleton_box(data)["height"] > 0
        ]
    if not peer_boxes:
        return None

    target_height = statistics.median(box["height"] for box in peer_boxes)
    target_center_x = statistics.median(box["center_x"] for box in peer_boxes)
    target_center_y = statistics.median(box["center_y"] for box in peer_boxes)
    show_entries = [
        (path, data, skeleton_box(data))
        for path, data in loaded
        if path.parent.name == "show" and skeleton_box(data)["height"] > 0
    ]
    if not show_entries:
        return None

    path, data, box = show_entries[0]
    if target_height <= 0 or box["height"] <= target_height * 1.25:
        return None
    scale = target_height / box["height"]
    return {
        "scope": path.parent.name,
        "scale": scale,
        "source_center_x": box["center_x"],
        "source_center_y": box["center_y"],
        "target_center_x": target_center_x,
        "target_center_y": target_center_y,
    }


def merge_character(character_dir, output_dir):
    json_paths = sorted(
        p for p in character_dir.glob("*/*.json")
        if p.parent.name != output_dir.name and not p.name.startswith(".")
    )
    if not json_paths:
        return None

    loaded = [(path, load_json(path)) for path in json_paths]
    datas = [data for _, data in loaded]
    normalize_show = show_normalization(loaded)
    out_dir = output_dir / character_dir.name
    out_dir.mkdir(parents=True, exist_ok=True)

    base = copy.deepcopy(datas[0])
    base["skeleton"] = copy.deepcopy(base.get("skeleton", {}))
    base["skeleton"]["hash"] = ""
    base["skeleton"]["images"] = "./"
    x, y, width, height = union_bounds(datas)
    base["skeleton"]["x"] = x
    base["skeleton"]["y"] = y
    base["skeleton"]["width"] = width
    base["skeleton"]["height"] = height

    base["bones"] = [{"name": "root"}]
    slots = []
    skin_attachments = {}
    animations = {}
    animation_slots = {}
    events = {}
    ik_constraints = []
    transform_constraints = []
    path_constraints = []
    atlas_chunks = []
    copied_pages = set()
    used_animation_names = set()

    for path, data in loaded:
        scope = path.parent.name
        skin = default_skin(data)
        attachment_name_maps = attachment_name_maps_for_skin(skin, scope)
        bone_name_map = {}
        bone_index_map = {}
        for index, bone in enumerate(data.get("bones", [])):
            original_name = bone["name"]
            target_name = scoped_name(scope, original_name)
            bone_name_map[original_name] = target_name
            bone_index_map[index] = len(base["bones"])
            cloned = copy.deepcopy(bone)
            cloned["name"] = target_name
            if "parent" in cloned:
                cloned["parent"] = bone_name_map.get(cloned["parent"], scoped_name(scope, cloned["parent"]))
            else:
                cloned["parent"] = "root"
            if (
                normalize_show
                and scope == normalize_show["scope"]
                and index == 0
            ):
                scale = normalize_show["scale"]
                old_scale_x = cloned.get("scaleX", 1) or 1
                old_scale_y = cloned.get("scaleY", 1) or 1
                old_x = cloned.get("x", 0) or 0
                old_y = cloned.get("y", 0) or 0
                cloned["scaleX"] = old_scale_x * scale
                cloned["scaleY"] = old_scale_y * scale
                cloned["x"] = normalize_show["target_center_x"] - ((normalize_show["source_center_x"] - old_x) * scale)
                cloned["y"] = normalize_show["target_center_y"] - ((normalize_show["source_center_y"] - old_y) * scale)
            base["bones"].append(cloned)

        slot_name_map = {}
        source_slots = []
        for slot in data.get("slots", []):
            original_name = slot["name"]
            target_name = scoped_name(scope, original_name)
            slot_name_map[original_name] = target_name
            source_slots.append(target_name)
            cloned = copy.deepcopy(slot)
            cloned["name"] = target_name
            cloned["bone"] = bone_name_map.get(cloned.get("bone", "root"), cloned.get("bone", "root"))
            if cloned.get("attachment") is not None:
                cloned["attachment"] = attachment_name_maps.get(original_name, {}).get(
                    cloned["attachment"],
                    scoped_name(scope, cloned["attachment"]),
                )
            slots.append(cloned)

        constraint_name_map = {}
        for key, target in (("ik", ik_constraints), ("transform", transform_constraints), ("path", path_constraints)):
            for constraint in data.get(key, []) or []:
                cloned = copy.deepcopy(constraint)
                original_name = cloned.get("name", key)
                cloned["name"] = scoped_name(scope, original_name)
                constraint_name_map[original_name] = cloned["name"]
                if "bones" in cloned:
                    cloned["bones"] = [bone_name_map.get(name, name) for name in cloned["bones"]]
                if "target" in cloned:
                    if key == "path":
                        cloned["target"] = slot_name_map.get(cloned["target"], cloned["target"])
                    else:
                        cloned["target"] = bone_name_map.get(cloned["target"], cloned["target"])
                target.append(cloned)

        remapped_skin = remap_skin(skin, scope, slot_name_map, bone_index_map, attachment_name_maps)
        for slot_name, attachments in remapped_skin.get("attachments", {}).items():
            skin_attachments.setdefault(slot_name, {}).update(attachments)

        for animation_name, animation in data.get("animations", {}).items():
            if animation_name in used_animation_names:
                target_name = unique_name(f"{path.parent.name}_{animation_name}", used_animation_names)
            else:
                target_name = unique_name(animation_name, used_animation_names)
            animations[target_name] = remap_animation(animation, scope, bone_name_map, slot_name_map, constraint_name_map, attachment_name_maps)
            animation_slots[target_name] = set(source_slots)

        events.update(copy.deepcopy(data.get("events", {})))

        atlas_path = path.with_suffix(".atlas")
        if atlas_path.exists():
            atlas_chunks.append(remap_atlas_text(atlas_path.read_text(encoding="utf-8"), scope))
            for line in atlas_path.read_text(encoding="utf-8").splitlines():
                page = line.strip()
                if page.endswith(".png"):
                    png_path = atlas_path.parent / page
                    if png_path.exists() and page not in copied_pages:
                        shutil.copy2(png_path, out_dir / page)
                        copied_pages.add(page)

    base["slots"] = slots
    base["skins"] = [{"name": "default", "attachments": skin_attachments}]
    if events:
        base["events"] = events
    for key, value in (("ik", ik_constraints), ("transform", transform_constraints), ("path", path_constraints)):
        if value:
            base[key] = value

    all_slot_names = [slot["name"] for slot in slots]
    for animation_name, animation in animations.items():
        slot_timelines = animation.setdefault("slots", {})
        active_slots = animation_slots.get(animation_name, set())
        for slot_name in all_slot_names:
            if slot_name not in active_slots:
                slot_timelines[slot_name] = {"attachment": [{"name": None}]}

    base["animations"] = animations

    stem = character_dir.name
    json_out = out_dir / f"{stem}.json"
    atlas_out = out_dir / f"{stem}.atlas"
    dump_json(json_out, base)
    atlas_out.write_text("\n\n".join(atlas_chunks) + "\n", encoding="utf-8")

    return {
        "character": character_dir.name,
        "json": str(json_out),
        "atlas": str(atlas_out),
        "png_pages": len(copied_pages),
        "animations": sorted(animations),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Merge split frame-based Spine action exports into one JSON/atlas per character."
    )
    parser.add_argument("root", type=Path, help="Folder containing character folders.")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output folder.")
    parser.add_argument("--character", help="Only merge one character folder, e.g. 001.")
    args = parser.parse_args()

    root = args.root.expanduser()
    output = args.output.expanduser()
    output.mkdir(parents=True, exist_ok=True)

    character_dirs = [root / args.character] if args.character else sorted(
        p for p in root.iterdir() if p.is_dir() and not p.name.startswith(".")
    )

    results = []
    for character_dir in character_dirs:
        result = merge_character(character_dir, output)
        if result:
            results.append(result)

    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
