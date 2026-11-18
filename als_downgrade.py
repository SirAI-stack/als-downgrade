#!/usr/bin/env python3
"""ALS Downgrade - open newer Ableton Live projects in an older Live version.

By Carni. Converts a .als to the exact format understood by the Live version
installed on this Mac, using the schemas and templates shipped inside Live.

    python3 als_downgrade.py "Song.als"
    python3 als_downgrade.py "Song Project/"            # whole project folder
    python3 als_downgrade.py "Song.als" --check         # report only
    python3 als_downgrade.py "Song.als" --app "/Applications/Ableton Live 12 Standard.app"

The original is never modified: "Song (Live X.Y.Z).als" is created next to it.
"""
import argparse
import collections
import copy
import glob
import gzip
import os
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

# Renames between versions the schema cannot infer: new -> old.
RENAMES = {
    "ViewStateSessionTrackWidth": "ViewStateSesstionTrackWidth",
    "ViewStateSessionMixerVolumeSectionHeight": "ViewStateSessionMixerHeight",
    "MainTrack": "MasterTrack",
}
RENAMES_IN_CLASS = {("ScaleInformation", "Root"): "RootNote"}

# Since 12.x the scale is stored as an index; before, as text.
SCALES = ["Major", "Minor", "Dorian", "Mixolydian", "Lydian", "Phrygian", "Locrian",
          "Whole Tone", "Half-whole Dim.", "Whole-half Dim.", "Minor Blues",
          "Minor Pentatonic", "Major Pentatonic", "Harmonic Minor", "Harmonic Major",
          "Dorian #4", "Phrygian Dominant", "Melodic Minor", "Lydian Augmented",
          "Lydian Dominant", "Super Locrian", "8-Tone Spanish", "Bhairav",
          "Hungarian Minor", "Hirajoshi", "In-Sen", "Iwato", "Kumoi", "Pelog Selisir",
          "Pelog Tembung", "Messiaen 3", "Messiaen 4", "Messiaen 5", "Messiaen 6",
          "Messiaen 7"]
SCALES_CERTAIN = 2  # only Major/Minor verified against real files

# Pure screen state (zoom, scroll, open panels, selections). It carries no music,
# so it is always replaced by the target Live's own defaults: leftovers from a
# newer version here crash Live while you edit (clip detail view).
UI_STATE = {
    "LiveSet": {"SessionScrollPos", "TimeSelection", "SequencerNavigator", "IsContentSplitterOpen",
                "IsExpressionSplitterOpen", "ExpressionLanes", "ContentLanes", "ViewStateFxSlotCount",
                "ViewStateSessionMixerHeight", "ViewStateArrangerMixerVolumeSectionHeight",
                "WaveformVerticalZoomFactor", "IsWaveformVerticalZoomActive", "ChooserBar", "ViewData",
                "MidiFoldIn", "MidiFoldMode", "MultiClipLoopBarHeight", "TrackHeaderWidth",
                "ViewStateMainWindowClipDetailOpen", "ViewStateMainWindowHiddenOtherDocViewTypeClipDetailOpen",
                "ViewStateMainWindowHiddenOtherDocViewTypeDeviceDetailOpen", "ViewStateMainWindowDeviceDetailOpen",
                "ViewStateSecondWindowClipDetailOpen", "ViewStateSecondWindowDeviceDetailOpen", "ViewStates",
                "NoteAlgorithms", "SelectedDocumentViewInMainWindow"},
    "AudioClip": {"ScrollerTimePreserver", "TimeSelection"},
    "MidiClip": {"ScrollerTimePreserver", "TimeSelection", "NoteEditorFoldInZoom", "NoteEditorFoldInScroll",
                 "NoteEditorFoldOutZoom", "NoteEditorFoldOutScroll", "NoteEditorFoldScaleZoom",
                 "NoteEditorFoldScaleScroll"},
}
for _t in ("AudioTrack", "MidiTrack", "ReturnTrack", "GroupTrack", "MainTrack", "MasterTrack", "PreHearTrack"):
    UI_STATE[_t] = {"IsContentSelectedInDocument", "PreferredContentViewMode", "ViewData"}
FIXED_ORDER_LISTS = ()
PRIMITIVES = {"Int", "Int64", "Bool", "Float", "Double", "String"}
NUM = re.compile(r"^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$|^-?inf$|^nan$", re.I)


def version_key(name):
    m = re.match(r"(\d+)\.(\d+)_(\d+)", name)
    return (int(m[1]), int(m[2]), int(m[3])) if m else (0, 0, 0)


def find_apps():
    apps = []
    for root in ("/Applications", os.path.expanduser("~/Applications")):
        apps += glob.glob(os.path.join(root, "Ableton Live*.app"))
    found = []
    for app in apps:
        try:
            with open(os.path.join(app, "Contents/Info.plist"), "rb") as f:
                ver = plistlib.load(f)["CFBundleShortVersionString"].split()[0]
            found.append((tuple(int(x) for x in ver.split(".")[:3]), ver, app))
        except (OSError, KeyError, ValueError):
            pass
    return sorted(found)


def app_version(app):
    with open(os.path.join(app, "Contents/Info.plist"), "rb") as f:
        return plistlib.load(f)["CFBundleShortVersionString"].split()[0]


FORMATS = os.path.expanduser("~/Library/Application Support/ALS Downgrade/formats")


def default_schema():
    """Output format chosen for this Mac (formats/default.txt), e.g. a format that is
    verified to open, which the installed Live then upgrades by itself."""
    try:
        return open(os.path.join(FORMATS, "default.txt")).read().strip() or None
    except OSError:
        return None


class Target:
    """What the target version understands: schema + native examples."""

    def __init__(self, app, schema_name=None):
        self.app, self.version = app, app_version(app)
        res = os.path.join(app, "Contents/App-Resources")
        files = glob.glob(os.path.join(res, "Schema", "*.txt"))
        if not files:
            sys.exit("This Live app has no schemas: " + app)
        by_name = {os.path.basename(f)[:-4]: f for f in files}
        self.minor = schema_name or max(by_name, key=version_key)
        if self.minor not in by_name:
            sys.exit("Schema not available: %s" % self.minor)
        self.exact_app = schema_name is None or schema_name == max(by_name, key=version_key)
        root = ET.parse(by_name[self.minor]).getroot()
        self.major = root.get("Version", "5")
        self.change_count = root.get("ChangeCount", "0")
        self.classes = {k.tag: collections.OrderedDict((m.tag, m.attrib) for m in k)
                        for k in root}
        self.samples, self.attrs = {}, collections.defaultdict(set)
        self.instances, self.present = collections.Counter(), collections.Counter()
        self.seen_tags = set()
        # Sets really saved by a Live that writes this format (kept in the format library)
        # teach the same defaults as Live's own templates, even after Live was updated.
        lib = os.path.join(FORMATS, self.minor + "-live")
        self.from_library = not self.exact_app and os.path.isdir(lib)
        if self.exact_app:
            self._harvest(res)
        elif self.from_library:
            self.exact_app = True
            self._harvest(lib)

    def _harvest(self, res):
        """Learn default values from the .als files shipped with Live."""
        for path in sorted(glob.glob(os.path.join(res, "**", "*.als"), recursive=True)):
            try:
                with gzip.open(path) as f:
                    doc = ET.fromstring(f.read())
            except (OSError, ET.ParseError):
                continue
            if doc.get("MinorVersion", "").split("_")[0] != self.minor.split("_")[0]:
                continue
            # header of a set saved by exactly this Live: the converted file copies it
            if doc.get("MinorVersion") == self.minor and not hasattr(self, "native_root"):
                self.native_root = dict(doc.attrib)
                self.native_overwrite = doc[0].find("OverwriteProtectionNumber")
            for e in doc.iter():
                self.seen_tags.add(e.tag)
                self.attrs[e.tag].update(e.attrib)
            self._harvest_members(doc[0], "LiveSet")

    def required(self, cls, tag):
        """Required only if Live almost always writes it (never MIDI mappings)."""
        if "KeyMidi" in tag or tag.endswith("Mapping"):
            return False
        return self.present[(cls, tag)] * 2 > self.instances[cls]

    def _harvest_members(self, e, cls):
        mem = self.classes.get(cls)
        self.instances[cls] += 1
        for c in e:
            if mem is not None and c.tag in mem:
                sub = mem[c.tag]["Class"]
                self.samples.setdefault((cls, c.tag), c)
                self.present[(cls, c.tag)] += 1
            elif c.tag in self.classes:
                sub = c.tag
            else:
                sub = None
            if sub == cls and mem is None:
                sub = None
            self._harvest_members(c, sub)


class Converter:
    def __init__(self, doc, target):
        self.doc, self.t = doc, target
        self.live = doc[0]
        self.next_id = int(self.live.find("NextPointeeId").get("Value", "0"))
        self.removed = collections.Counter()
        self.added = collections.Counter()
        self.renamed = collections.Counter()
        self.reordered = 0
        self.warnings, self.lost_devices = [], collections.Counter()
        self.unknown = collections.Counter()
        self.bad_values = collections.Counter()

    def fresh_ids(self, e):
        for x in e.iter():
            if "Id" in x.attrib and (x.tag.endswith("Target") or x.tag == "Pointee"
                                     or x.tag.endswith("ModulationTarget")):
                x.set("Id", str(self.next_id))
                self.next_id += 1

    def default_for(self, cls, tag, info):
        sample = self.t.samples.get((cls, tag))
        if sample is not None:
            c = copy.deepcopy(sample)
            self.fresh_ids(c)
            return c
        return None

    def fix_scale(self, e):
        """Live 12.0 stores the scale as text ("Major"); 12.1+ as an index. Follow the target."""
        name = e.find("Name")
        if name is None:
            return
        v = name.get("Value", "")
        target_is_text = "String" in self.t.classes.get("ScaleInformation", {}).get("Name", {}).get("Class", "String")
        if target_is_text and v.isdigit():
            i = int(v)
            name.set("Value", SCALES[i] if i < len(SCALES) else "Major")
            if i >= SCALES_CERTAIN:
                msg = "Scale index %d converted to '%s': please check it." % (i, name.get("Value"))
                if msg not in self.warnings:
                    self.warnings.append(msg)
        elif not target_is_text and not v.isdigit():
            name.set("Value", str(SCALES.index(v)) if v in SCALES else "0")

    def check_value(self, holder, attr, prim):
        v = holder.get(attr)
        if v is None or prim == "String":
            return True
        if prim == "Bool":
            return v in ("true", "false")
        if prim in ("Int", "Int64"):
            return re.match(r"^-?\d+$", v) is not None
        return NUM.match(v) is not None

    def walk(self, e, cls):
        if cls == "ScaleInformation":
            self.fix_scale(e)
        mem = self.t.classes.get(cls)
        if mem is None:
            self.walk_container(e)
            return
        # A parameter changed kind between versions: automatable (<Manual>)
        # in the source, plain Remoteable (Value="...") in the target, or back.
        vinfo = mem.get("Value")
        if vinfo is not None and vinfo["Type"] == "-4" and "Value" not in e.attrib:
            man = e.find("Manual")
            if man is not None and man.get("Value") is not None:
                e.set("Value", man.get("Value"))
                for c in list(e):
                    e.remove(c)
                self.renamed["%s (automatable -> plain)" % e.tag] += 1
        elif "Manual" in mem and "Value" in e.attrib and e.find("Manual") is None:
            parent = getattr(self, "_parent_cls", None)
            d = self.default_for(parent, e.tag, {"Class": cls}) if parent else None
            v = e.get("Value")
            if d is not None and d.find("Manual") is not None:
                e.attrib.clear()
                e.extend(list(d))
                e.find("Manual").set("Value", v)
                self.renamed["%s (plain -> automatable)" % e.tag] += 1
        # attributes the target version never writes
        known = self.t.attrs.get(e.tag)
        if known is not None and self.t.exact_app:
            for a in [a for a in e.attrib if a not in known and a not in mem]:
                del e.attrib[a]
                self.removed["@%s.%s" % (cls, a)] += 1
        for tag, info in mem.items():
            if info["Type"] == "-4" and tag in e.attrib:
                if not self.check_value(e, tag, info["Class"]):
                    self.bad_values["%s.%s" % (cls, tag)] += 1
                    v, p = e.get(tag), info["Class"]
                    # a member changed type between versions (e.g. Saturator
                    # Oversampling: Bool in 12.4, Enum in 12.0)
                    if p in ("Int", "Int64") and v in ("true", "false"):
                        e.set(tag, "1" if v == "true" else "0")
                    elif p == "Bool" and re.match(r"^-?\d+$", v or ""):
                        e.set(tag, "false" if int(v) == 0 else "true")
        for c in list(e):
            new = RENAMES_IN_CLASS.get((cls, c.tag)) or RENAMES.get(c.tag)
            if c.tag not in mem and new in mem:
                self.renamed["%s -> %s" % (c.tag, new)] += 1
                c.tag = new
            if c.tag not in mem:
                e.remove(c)
                self.removed["%s.%s" % (cls, c.tag)] += 1
                if cls == "Delay" and c.tag == "ShowLfo" and c.get("Value") == "true":
                    self.warnings.append("The Delay LFO (new in 12.x) was visible "
                                         "and does not exist in this version.")
                continue
            info = mem[c.tag]
            if info["Type"] == "-4":
                if not self.check_value(c, "Value", info["Class"]):
                    self.bad_values["%s.%s" % (cls, c.tag)] += 1
                    d = self.default_for(cls, c.tag, info)
                    if d is not None:
                        c.set("Value", d.get("Value", ""))
            elif info["Class"] in PRIMITIVES:
                pass
            else:
                self._parent_cls = cls
                self.walk(c, info["Class"])
        present = {c.tag for c in e}
        for tag, info in mem.items():
            if tag not in present and tag not in e.attrib and self.t.required(cls, tag):
                d = self.default_for(cls, tag, info)
                if d is not None:
                    e.append(d)
                    self.added["%s.%s" % (cls, tag)] += 1
        order = {t: i for i, t in enumerate(mem)}
        kids = list(e)
        ranked = sorted(kids, key=lambda c: order.get(c.tag, len(order)))
        if ranked != kids:
            self.reordered += 1
            for c in kids:
                e.remove(c)
            e.extend(ranked)

    def walk_container(self, e):
        for c in list(e):
            if c.tag in self.t.classes:
                self.walk(c, c.tag)
            elif e.tag == "Devices":
                e.remove(c)
                self.lost_devices[c.tag] += 1
            elif "Id" in c.attrib and RENAMES.get(c.tag) not in self.t.classes:
                # list item of an unknown class: Live aborts loading if it sees one
                e.remove(c)
                self.removed["clase %s (en %s)" % (c.tag, e.tag)] += 1
            else:
                new = RENAMES.get(c.tag)
                if new in self.t.classes:
                    self.renamed["%s -> %s" % (c.tag, new)] += 1
                    c.tag = new
                    self.walk(c, new)
                else:
                    if c.tag != "Value" and len(c):
                        self.unknown[c.tag] += 1
                    self.walk_container(c)

    def prune_dangling(self):
        """Remove automation pointing to parameters that no longer exist."""
        ids = {x.get("Id") for x in self.doc.iter()
               if x.tag.endswith("Target") and "Id" in x.attrib}
        ids |= {x.get("Id") for x in self.doc.iter() if x.tag == "Pointee"}
        n = 0
        for parent in self.doc.iter():
            for c in list(parent):
                if c.tag in ("AutomationEnvelope", "ClipEnvelope"):
                    p = c.find("EnvelopeTarget/PointeeId")
                    if p is not None and p.get("Value") not in ids:
                        parent.remove(c)
                        n += 1
        if n:
            self.warnings.append("%d automations removed: their parameter does not exist "
                                 "in the target version." % n)

    def fix_samples(self, als_dir):
        """Point each audio file to its real location; collected samples win."""
        root = project_root(als_dir)
        index = {}
        for d, _, names in os.walk(root):
            for n in names:
                if not n.endswith(".asd"):
                    index.setdefault(n, os.path.join(d, n))
        fixed, missing = 0, set()
        for ref in self.doc.iter("SampleRef"):
            f = ref.find("FileRef")
            rel = f.find("RelativePath") if f is not None else None
            path = f.find("Path") if f is not None else None
            if path is None:
                continue
            old = path.get("Value", "")
            r = rel.get("Value", "") if rel is not None else ""
            local = os.path.normpath(os.path.join(root, r)) if r else ""
            if local and os.path.exists(local):
                real = local
            else:
                real = index.get(os.path.basename(r or old))
            if real:
                if real != old:
                    path.set("Value", disk_form(real))
                    fixed += 1
                if rel is not None:
                    rel.set("Value", os.path.relpath(disk_form(real), disk_form(root)))
            elif not os.path.exists(old):
                missing.add(os.path.basename(r or old))
        print("  Audio: %d linked to your project, %d missing" % (fixed, len(missing)))
        for m in sorted(missing):
            print("  ! Missing audio: " + m)

    def fix_main_track(self):
        """Tracks without clips of their own (Main, groups, returns) cannot be frozen
        in Live 12.0: freeze clip slots on them make Live crash while loading."""
        if not self.t.minor.startswith("12.0_120"):
            return
        n = 0
        for tag in ("MainTrack", "MasterTrack", "PreHearTrack"):
            for s in self.live.findall(tag + "/DeviceChain/FreezeSequencer/AudioSequencer/ClipSlotList"):
                n += len(s); s[:] = []
        for t in self.live.find("Tracks"):
            if t.tag in ("GroupTrack", "ReturnTrack"):
                for s in t.findall("DeviceChain/FreezeSequencer/ClipSlotList"):
                    n += len(s); s[:] = []
        return n

    def reset_ui_state(self, e=None, cls="LiveSet"):
        """Replace every screen-state field with the target Live's own default."""
        if e is None:
            self.ui_reset = 0
            e = self.live
        mem = self.t.classes.get(cls)
        names = UI_STATE.get(cls, ())
        for i, c in enumerate(list(e)):
            if c.tag in names:
                ref = self.t.samples.get((cls, c.tag))
                if ref is not None:
                    new = copy.deepcopy(ref)
                    self.fresh_ids(new)
                    e.remove(c)
                    e.insert(i, new)
                    self.ui_reset += 1
                continue
            sub = None
            if mem is not None and c.tag in mem:
                sub = mem[c.tag]["Class"]
            elif c.tag in self.t.classes:
                sub = c.tag
            self.reset_ui_state(c, sub if sub in self.t.classes else None)
        return getattr(self, "ui_reset", 0)

    def fix_fixed_order_lists(self):
        """Live indexes some lists by position (MIDI Tools). Use the target's own
        list when the order differs: a wrong order crashes Live while editing."""
        n = 0
        for tag in FIXED_ORDER_LISTS:
            cur = self.live.find(tag)
            ref = self.t.samples.get(("LiveSet", tag))
            if cur is None or ref is None:
                continue
            if [c.tag for c in cur] == [c.tag for c in ref]:
                continue
            new = copy.deepcopy(ref)
            self.fresh_ids(new)
            kids = list(self.live)
            self.live.remove(cur)
            self.live.insert(kids.index(cur), new)
            n += 1
        if n:
            self.warnings.append("MIDI Tools settings reset to defaults (their order "
                                 "differs in this Live version and caused crashes).")
        return n

    def run(self):
        self.walk(self.live, "LiveSet")
        self.fix_main_track()
        self.reset_ui_state()
        self.prune_dangling()
        top = max([int(x.get("Id")) for x in self.doc.iter()
                   if x.get("Id", "").isdigit() and (x.tag.endswith("Target") or x.tag == "Pointee")]
                  + [self.next_id - 1])
        self.live.find("NextPointeeId").set("Value", str(top + 1))
        self.native_header()

    def native_header(self):
        """Make the file look exactly like one saved by the target Live: its root
        attributes, its overwrite protection number and Live Object Model ids at 0.
        Leftover header values from a newer Live crash Live 12.2 a second after loading."""
        nat = getattr(self.t, "native_root", None)
        for k in list(self.doc.attrib):
            del self.doc.attrib[k]
        if nat:
            self.doc.attrib.update(nat)
        else:
            self.doc.attrib.update({"MajorVersion": self.t.major, "MinorVersion": self.t.minor,
                                    "SchemaChangeCount": self.t.change_count,
                                    "Creator": "Ableton Live " + self.t.version, "Revision": ""})
        opn = getattr(self.t, "native_overwrite", None)
        if opn is not None and self.live.find("OverwriteProtectionNumber") is not None:
            self.live.find("OverwriteProtectionNumber").set("Value", opn.get("Value"))
        for e in self.doc.iter():
            if e.tag in ("LomId", "LomIdView"):
                e.set("Value", "0")
            if "LomId" in e.attrib:
                e.set("LomId", "0")


def disk_form(path):
    """The path exactly as the file system stores it (e.g. "i" + accent vs "\u00ed").
    macOS treats both spellings as equal, but Live only finds audio by the stored one."""
    import unicodedata
    path = os.path.abspath(path)
    out = "/"
    for part in path.strip("/").split("/"):
        try:
            names = os.listdir(out)
        except OSError:
            names = []
        want = unicodedata.normalize("NFC", part)
        match = next((n for n in names if unicodedata.normalize("NFC", n) == want), part)
        out = os.path.join(out, match)
    return out


def project_root(folder):
    """Walk up from the .als to the project folder (e.g. from Backup/)."""
    d = os.path.abspath(folder)
    for _ in range(4):
        if os.path.isdir(os.path.join(d, "Ableton Project Info")) or os.path.isdir(os.path.join(d, "Samples")):
            return d
        d = os.path.dirname(d)
    return os.path.abspath(folder)


def expand(paths):
    """A project folder means its main .als files."""
    out = []
    for p in paths:
        if os.path.isdir(p):
            found = sorted(f for f in glob.glob(os.path.join(glob.escape(p), "*.als")) if not os.path.basename(f).startswith("._"))
            found = [f for f in found if not re.search(r" \((Live [\d.]+|repaired)\)\.als$", f)]
            if not found:
                print("No .als projects in " + p)
            out += found
        else:
            out.append(p)
    # "._name.als" are macOS metadata files on exFAT/FAT disks, not Live Sets
    return [x for x in out if not os.path.basename(x).startswith("._")]


def file_md5(path):
    import hashlib
    h = hashlib.md5()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def new_project_als(path, label, reuse=None):
    import shutil
    """Copy the whole project to "<Project> (<label>) Project" and return the new .als path.
    Never overwrites work: a copy made from this exact source is reused (reuse[0] = True);
    a different source gets a new numbered folder."""
    import shutil
    src_root = project_root(os.path.dirname(os.path.abspath(path)))
    name = os.path.splitext(os.path.basename(path))[0]
    # ":" in a file name (e.g. a time "12:11:26") is a path separator for Live:
    # it shows the set as "26" and resolves its project wrongly. Never write one.
    name = re.sub(r"[:/]", "-", name)
    if re.search(r" \((Live [\d.]+|repaired)\)( \d+)? Project$", os.path.basename(src_root)):
        # the file is inside a project that is already a converted copy: convert next to it
        digest = file_md5(path)
        n = 1
        while True:
            out = os.path.join(os.path.dirname(os.path.abspath(path)),
                               "%s (%s)%s.als" % (name, label, "" if n == 1 else " %d" % n))
            mark = os.path.join(src_root, "Ableton Project Info", "converted from %s.txt" % name)
            if not os.path.exists(out):
                os.makedirs(os.path.dirname(mark), exist_ok=True)
                with open(mark, "w") as f:
                    f.write(digest + "\n" + os.path.abspath(path) + "\n")
                return out
            try:
                if open(mark).read().split()[0] == digest:
                    if reuse is not None:
                        reuse[0] = True
                    return out
            except (OSError, IndexError):
                pass
            n += 1
    base = re.sub(r" Project$", "", os.path.basename(src_root)) or name
    base = re.sub(r" \((Live [\d.]+|repaired)\)( \d+)?$", "", base)
    base = re.sub(r"[:/]", "-", base)
    digest = file_md5(path)
    # Keep every version of a project together: "<base> (versiones)/" holds the
    # original project and its converted copies. Only real Live projects are moved.
    if os.path.isdir(os.path.join(src_root, "Ableton Project Info")) and not os.path.basename(
            os.path.dirname(src_root)).endswith(" (versiones)"):
        box = os.path.join(os.path.dirname(src_root), "%s (versiones)" % base)
        os.makedirs(box, exist_ok=True)
        moved = os.path.join(box, os.path.basename(src_root))
        if not os.path.exists(moved):
            shutil.move(src_root, moved)
            print("  Folder: " + box)
            path = os.path.join(moved, os.path.relpath(os.path.abspath(path), src_root))
            src_root = moved
    n = 1
    while True:
        suffix = "" if n == 1 else " %d" % n
        dst = os.path.join(os.path.dirname(src_root), "%s (%s)%s Project" % (base, label, suffix))
        out = os.path.join(dst, "%s.als" % name)
        mark = os.path.join(dst, "Ableton Project Info", "converted from %s.txt" % name)
        if not os.path.exists(out):
            break
        try:
            if open(mark).read().split()[0] == digest:
                if reuse is not None:
                    reuse[0] = True
                return out
        except (OSError, IndexError):
            pass
        n += 1
    if not os.path.isdir(dst):
        def skip(d, names):
            return [x for x in names if x in ("Backup", ".DS_Store") or x.endswith(".als")]
        shutil.copytree(src_root, dst, ignore=skip)
    os.makedirs(os.path.dirname(mark), exist_ok=True)
    with open(mark, "w") as f:
        f.write(digest + "\n" + os.path.abspath(path) + "\n")
    return out


def archive_original(path, creator):
    """Sync mode: move the newer .als into "<project>/Historial/" with its date and Live
    version, so the converted Set can take its place under the same name."""
    import shutil, time
    root = project_root(os.path.dirname(os.path.abspath(path)))
    hist = os.path.join(root, "Historial")
    os.makedirs(hist, exist_ok=True)
    name = os.path.splitext(os.path.basename(path))[0]
    ver = (re.search(r"Live ([\d.]+)", creator or "") or [None, "?"])[1]
    stamp = time.strftime("%Y-%m-%d %H.%M", time.localtime(os.path.getmtime(path)))
    dst = os.path.join(hist, "%s [%s, Live %s].als" % (name, stamp, ver))
    n = 2
    while os.path.exists(dst):
        dst = os.path.join(hist, "%s [%s, Live %s] %d.als" % (name, stamp, ver, n)); n += 1
    shutil.move(path, dst)
    return dst


def song_key(name):
    """Base name of a song, ignoring what Live or people add when saving copies."""
    n = os.path.splitext(name)[0].lower()
    for pat in (r"\[[^\]]*\]", r"\((live [\d.]+|repaired|copia|copy)\)", r"\b(copia|copy)\b",
                r"\d{1,2}[-:.]\d{1,2}[-:.]\d{2,4}", r"\s\d+$"):
        n = re.sub(pat, " ", n).strip()
    return re.sub(r"[^a-z0-9]+", "", n)


def older_siblings(path):
    """Other Sets of the same song in the same folder, older than this one."""
    d, me = os.path.dirname(os.path.abspath(path)), os.path.basename(path)
    key, t = song_key(me), os.path.getmtime(path)
    out = []
    for f in os.listdir(d):
        p = os.path.join(d, f)
        if f != me and f.endswith(".als") and song_key(f) == key and os.path.getmtime(p) < t:
            out.append(p)
    return sorted(out, key=os.path.getmtime)


PLUGIN_DIRS = ["/Library/Audio/Plug-Ins/Components", "/Library/Audio/Plug-Ins/VST3", "/Library/Audio/Plug-Ins/VST",
               os.path.expanduser("~/Library/Audio/Plug-Ins/Components"),
               os.path.expanduser("~/Library/Audio/Plug-Ins/VST3"), os.path.expanduser("~/Library/Audio/Plug-Ins/VST")]


def norm(name):
    return re.sub(r"[^a-z0-9]", "", (name or "").lower())


def installed_plugins():
    names = set()
    for d in PLUGIN_DIRS:
        for f in (os.listdir(d) if os.path.isdir(d) else []):
            names.add(norm(os.path.splitext(f)[0]))
    return names


def plugin_report(doc):
    """List third-party plugins used by the Set that are not installed on this Mac,
    with the tracks that use them. Matches by name across AU, VST and VST3."""
    have = installed_plugins()
    used = collections.OrderedDict()
    for track in doc.iter():
        if track.tag not in ("AudioTrack", "MidiTrack", "GroupTrack", "ReturnTrack", "MainTrack", "MasterTrack"):
            continue
        tname = (track.find("Name/EffectiveName") if track.find("Name/EffectiveName") is not None
                 else track.find("Name/UserName"))
        tname = tname.get("Value") if tname is not None else track.tag
        for dev in track.iter():
            if dev.tag not in ("AuPluginDevice", "PluginDevice", "Vst3PluginDevice"):
                continue
            pname = None
            for path in ("PluginDesc/AuPluginInfo/Name", "PluginDesc/VstPluginInfo/PlugName", "PluginDesc/Vst3PluginInfo/Name"):
                e = dev.find(path)
                if e is not None and e.get("Value"):
                    pname = e.get("Value"); break
            if pname:
                used.setdefault(pname, [])
                if tname not in used[pname]:
                    used[pname].append(tname)
    missing = collections.OrderedDict()
    for pname, tracks in used.items():
        key = norm(pname)
        base = re.sub(r"\d+$", "", key)
        if key in have or any(h.startswith(key) or key.startswith(h) for h in have if len(h) > 3):
            continue
        alt = [h for h in have if base and h.startswith(base)]
        missing[pname] = (tracks, alt)
    return missing


def print_plugins(doc):
    for pname, (tracks, alt) in plugin_report(doc).items():
        extra = " (installed: another version)" if alt else ""
        print("  ! Missing plugin: %s%s -- tracks: %s" % (pname, extra, ", ".join(tracks[:6])))


def load(path):
    with open(path, "rb") as f:
        raw = f.read()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    return ET.fromstring(raw)


def save(doc, path):
    body = ET.tostring(doc, encoding="unicode", short_empty_elements=True)
    data = ('<?xml version="1.0" encoding="UTF-8"?>\n' + body + "\n").encode("utf-8")
    tmp = path + ".tmp"
    with gzip.GzipFile(tmp, "wb", mtime=0) as f:
        f.write(data)
    os.replace(tmp, path)
    park_dotfile(path)


def park_dotfile(path):
    """On exFAT/FAT disks macOS keeps metadata in a hidden "._name" file next to it, and
    Live opens that one instead of the set ("corrupt"). Move it aside; it holds no music."""
    d = os.path.join(os.path.expanduser("~/Library/Application Support/ALS Downgrade"), "ocultos")
    dot = os.path.join(os.path.dirname(os.path.abspath(path)), "._" + os.path.basename(path))
    if os.path.isfile(dot):
        os.makedirs(d, exist_ok=True)
        import time
        import shutil
        try:
            shutil.move(dot, os.path.join(d, "%d %s" % (int(time.time()), os.path.basename(dot))))
        except OSError:
            pass


def report(cv, verbose):
    print("  Renamed: %d   Added: %d   Removed: %d   Reordered: %d" % (
        sum(cv.renamed.values()), sum(cv.added.values()),
        sum(cv.removed.values()), cv.reordered))
    if verbose:
        for title, c in (("Renamed", cv.renamed), ("Added", cv.added),
                         ("Removed", cv.removed), ("Invalid value", cv.bad_values),
                         ("Unknown (kept)", cv.unknown)):
            for k, v in sorted(c.items()):
                print("    %s: %s x%d" % (title, k, v))
    if cv.lost_devices:
        print("  !! DEVICES NOT AVAILABLE IN THIS VERSION (removed):")
        for k, v in cv.lost_devices.most_common():
            print("     - %s x%d" % (k, v))
    for w in cv.warnings:
        print("  ! " + w)


def main():
    p = argparse.ArgumentParser(description="Open a newer .als in an older Live version.")
    p.add_argument("als", nargs="+", help=".als file or project folder")
    p.add_argument("--app", help="path to the target Live app")
    p.add_argument("--schema", help="target schema, e.g. 11.0_11300 (experimental)")
    p.add_argument("-o", "--output", help="output file")
    p.add_argument("--check", action="store_true", help="report only, write nothing")
    p.add_argument("--repair", action="store_true", help="also clean files already in this Live's format")
    p.add_argument("--in-place", action="store_true", help="write next to the original instead of a new project copy")
    p.add_argument("--sync", action="store_true",
                   help="one file per project: archive the newer .als in Historial/ and replace it")
    p.add_argument("--plugins", action="store_true", help="only report missing plugins (fast)")
    p.add_argument("-v", "--verbose", action="store_true")
    a = p.parse_args()
    if a.plugins:
        for path in expand(a.als):
            d = os.path.dirname(os.path.abspath(path)); key = song_key(os.path.basename(path))
            for f in sorted(os.listdir(d)):
                q = os.path.join(d, f)
                if (f.endswith(".als") and q != os.path.abspath(path) and song_key(f) == key
                        and os.path.getmtime(q) > os.path.getmtime(path) + 60):
                    print("  ! Newer copy: " + q)
            try:
                print_plugins(load(path))
            except (OSError, ET.ParseError, EOFError) as ex:
                print("  ERROR: cannot read file (%s)" % ex)
        return
    app = a.app
    if not app:
        apps = find_apps()
        if not apps:
            sys.exit("Ableton Live not found in /Applications; use --app.")
        app = apps[-1][2]
    t = Target(app, a.schema or default_schema())
    print("Target: Live %s, format %s" % (t.version, t.minor))
    if version_key(t.minor) < (10, 0, 0):
        sys.exit("Target formats older than Live 10 are not supported.")
    if not t.exact_app:
        print("! EXPERIMENTAL: this target was not verified in Live and may not open.")
    failed = 0
    for path in expand(a.als):
        print("\n" + os.path.basename(path))
        try:
            doc = load(path)
        except (OSError, ET.ParseError, EOFError) as ex:
            print("  ERROR: cannot read file (%s)" % ex)
            failed += 1
            continue
        if a.plugins:
            print_plugins(doc)
            continue
        src = doc.get("MinorVersion", "?")
        creator = doc.get("Creator", "")
        print("  Saved with %s, format %s" % (doc.get("Creator", "?"), src))
        same = version_key(src) <= version_key(t.minor)
        if same and not a.repair:
            print("  Already compatible: open it directly in Live.")
            continue
        cv = Converter(doc, t)
        if same:
            cv.fix_main_track()
            cv.native_header()
            n = cv.reset_ui_state()
            print("  Repaired: %d screen-state fields reset to this Live's defaults." % n)
        else:
            if src.split(".")[0] != t.minor.split(".")[0]:
                print("  ! EXPERIMENTAL: converting across major Live versions.")
            cv.run()
        label = "repaired" if same else "Live " + t.version
        if a.check:
            cv.fix_samples(os.path.dirname(os.path.abspath(path)))
            report(cv, a.verbose)
            continue
        if a.output:
            out = a.output
        elif a.sync and not same:
            # Live's "Save As" in the studio may have left the song under a new name:
            # the oldest copy of the same song gives the name to keep.
            sibs = older_siblings(path)
            canonical = sibs[0] if sibs else path
            for sp in sibs:
                print("  Older copy kept in: " + archive_original(sp, load(sp).get("Creator", "")))
            hist = archive_original(path, creator)
            print("  Original kept in: " + hist)
            out = canonical
        elif a.in_place:
            out = "%s (%s).als" % (os.path.splitext(path)[0], label)
        else:
            reused = [False]
            out = new_project_als(path, label, reused)
            if reused[0]:
                print("  Existing copy kept (your work in it is not touched).")
                print("  Created: " + out)
                continue
        # link audio to the copy inside the new project (falls back to the original)
        cv.fix_samples(os.path.dirname(os.path.abspath(out)))
        report(cv, a.verbose)
        print_plugins(doc)
        save(doc, out)
        print("  Created: " + out)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
