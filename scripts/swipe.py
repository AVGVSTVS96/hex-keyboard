"""FUTO Swipe's encoder and decoder, converted for iikb, and what checks them against ExecuTorch's own runtime.

The weights are in ExecuTorch programs (.pte) whose XNNPACK delegates hold the constants by name. `extract` reads those
and writes `weights.txt` (a name and shape per tensor) and `weights.f32` (their float32 data in that order), which
Tools/SwipeBuilder packs into Resources/en.swipe. `data` turns the swipe.futo.org splits into compact `.swipes` files
for the scorer, and `reference` runs the ExecuTorch programs on some of those swipes for the parity test.

Usage: uv run --no-project --python 3.12 --with executorch --with numpy --with torch python3 scripts/swipe.py <command> <dir> ...
  extract <dir>                       download the .pte files into <dir>, write <dir>/weights.{txt,f32}
  data <dir> <split> [limit]          download <split> (test, dev) and write <dir>/<split>.swipes
  reference <dir> <split> <count> [out]  ExecuTorch's emissions for <count> swipes of <split>, to [out] (<dir>/<split>.reference)
"""

import json
import os
import re
import struct
import sys
import urllib.request

import numpy as np

MODELS = "https://huggingface.co/futo-org/futo-swipe/resolve/main"
DATASET = "https://huggingface.co/datasets/futo-org/swipe.futo.org/resolve/main"
ENCODER = "honorable_sturgeon"
DECODER = "magic_macaw"
FILES = [f"{ENCODER}/model_fp32.pte", f"{DECODER}/model_fp32.pte", "scoring.json", "LICENSE.md"]
LETTERS = "abcdefghijklmnopqrstuvwxyz"
QWERTY = {
    "a": (0.10, 0.500), "b": (0.60, 0.833), "c": (0.40, 0.833), "d": (0.30, 0.500), "e": (0.25, 0.167),
    "f": (0.40, 0.500), "g": (0.50, 0.500), "h": (0.60, 0.500), "i": (0.75, 0.167), "j": (0.70, 0.500),
    "k": (0.80, 0.500), "l": (0.90, 0.500), "m": (0.80, 0.833), "n": (0.70, 0.833), "o": (0.85, 0.167),
    "p": (0.95, 0.167), "q": (0.05, 0.167), "r": (0.35, 0.167), "s": (0.20, 0.500), "t": (0.45, 0.167),
    "u": (0.65, 0.167), "v": (0.50, 0.833), "w": (0.15, 0.167), "x": (0.30, 0.833), "y": (0.55, 0.167),
    "z": (0.20, 0.833),
}
KEYS = np.array([QWERTY[c] for c in LETTERS], np.float32)


def fetch(base, name, out):
    path = os.path.join(out, name)
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        urllib.request.urlretrieve(f"{base}/{name}", path + ".part")
        os.rename(path + ".part", path)
    return path


def program(path):
    from executorch.exir._serialize._program import deserialize_pte_binary

    return deserialize_pte_binary(open(path, "rb").read())


class Flatbuffer:
    """Just enough of flatbuffers to read the XNNPACK graph's constant table (executorch's schema.fbs)."""

    def __init__(self, buffer):
        self.b = buffer

    def u32(self, at):
        return struct.unpack_from("<I", self.b, at)[0]

    def field(self, table, slot):
        vtable = table - struct.unpack_from("<i", self.b, table)[0]
        offset = 4 + 2 * slot
        if offset >= struct.unpack_from("<H", self.b, vtable)[0]:
            return None
        relative = struct.unpack_from("<H", self.b, vtable + offset)[0]
        return table + relative if relative else None

    def vector(self, table, slot):
        at = self.field(table, slot)
        if at is None:
            return []
        start = at + self.u32(at)
        return [start + 4 + 4 * i for i in range(self.u32(start))]

    def table_at(self, at):
        return at + self.u32(at)

    def string(self, table, slot):
        at = self.field(table, slot)
        start = at + self.u32(at)
        return self.b[start + 4 : start + 4 + self.u32(start)].decode()

    def scalars(self, table, slot, fmt):
        at = self.field(table, slot)
        if at is None:
            return []
        start = at + self.u32(at)
        size = struct.calcsize(fmt)
        return [struct.unpack_from(fmt, self.b, start + 4 + size * i)[0] for i in range(self.u32(start))]

    def number(self, table, slot, fmt):
        at = self.field(table, slot)
        return 0 if at is None else struct.unpack_from(fmt, self.b, at)[0]


def delegate_constants(blob):
    """(name, dims) of every constant in an XNNPACK delegate blob, by constant buffer index."""
    assert blob[4:8] == b"XH00"
    offset, size = struct.unpack_from("<II", blob, 10)
    graph = blob[offset : offset + size]
    fb = Flatbuffer(graph)
    root = fb.u32(0)
    names = [fb.string(fb.table_at(at), 2) if fb.field(fb.table_at(at), 2) else "" for at in fb.vector(root, 8)]
    found = {}
    for value in fb.vector(root, 2):
        value = fb.table_at(value)
        union_table = fb.field(value, 1)
        if union_table is None:
            continue
        tensor = fb.table_at(union_table)
        index = fb.number(tensor, 3, "<I")
        if index:
            found[names[index]] = fb.scalars(tensor, 2, "<I")
    return found


def tensors(path):
    """Every named constant of a program: delegates' by their names (without the hash), and the program's own."""
    pte = program(path)
    plan = pte.program.execution_plan[0]
    store = pte.named_data
    out = {}
    for delegate in plan.delegates:
        for key, dims in delegate_constants(pte.program.backend_delegate_data[delegate.processed.index].data).items():
            if key in store.pte_data:
                raw = store.buffers[store.pte_data[key].buffer_index]
                out[re.sub(r"_[0-9a-f]{64}$", "", key)] = np.frombuffer(raw, np.float32).reshape(dims)
    return pte, plan, out


def program_constants(pte, plan, operator, arguments):
    """Constants the program passes to `operator`'s calls (or to delegates when operator is None), in call order."""
    from executorch.exir.schema import DelegateCall, KernelCall

    found = []
    for instruction in plan.chains[0].instructions:
        call = instruction.instr_args
        if operator is None and isinstance(call, DelegateCall):
            ids = call.args
        elif operator and isinstance(call, KernelCall) and plan.operators[call.op_index].name == operator:
            ids = [call.args[i] for i in arguments]
        else:
            continue
        for i in ids:
            value = plan.values[i].val
            if type(value).__name__ == "Tensor" and value.data_buffer_idx and value.scalar_type.name == "FLOAT":
                raw = pte.program.constant_buffer[value.data_buffer_idx].storage
                shape = list(value.sizes)
                found.append(np.frombuffer(raw, np.float32, int(np.prod(shape))).reshape(shape))
    return found


def weights(directory):
    """The encoder's and the decoder's tensors under the names Swipe(tensors:) reads."""
    pte, plan, encoder = tensors(os.path.join(directory, ENCODER, "model_fp32.pte"))
    reshaped = lambda name, a: a.reshape(a.shape[0], a.shape[1], a.shape[3]) if a.ndim == 4 else a
    out = {"encoder." + k.removeprefix("p_encoder_"): reshaped(k, v) for k, v in encoder.items()}
    pairs = [c for c in program_constants(pte, plan, None, None) if c.shape == (1, 256, 1)]
    assert len(pairs) == 10
    for block in range(5):
        out[f"encoder.backbone_blocks_{block}_grn_gamma"] = pairs[2 * block].reshape(256)
        out[f"encoder.backbone_blocks_{block}_grn_beta"] = pairs[2 * block + 1].reshape(256)
    pte, plan, decoder = tensors(os.path.join(directory, DECODER, "model_fp32.pte"))
    out.update({"decoder." + k.removeprefix("p_decoder_"): reshaped(k, v) for k, v in decoder.items()})
    norms = program_constants(pte, plan, "aten::native_layer_norm", [2, 3])
    assert len(norms) == 4
    for name, value in zip(["input_norm_weight", "input_norm_bias", "output_norm_weight", "output_norm_bias"], norms):
        out["decoder." + name] = value
    return out


def extract(directory):
    for name in FILES:
        fetch(MODELS, name, directory)
    named = weights(directory)
    with open(os.path.join(directory, "weights.txt"), "w") as manifest, open(os.path.join(directory, "weights.f32"), "wb") as data:
        for name, array in named.items():
            manifest.write(f"{name} {' '.join(map(str, array.shape))}\n")
            data.write(np.ascontiguousarray(array, np.float32).tobytes())
    print(f"{len(named)} tensors, {sum(a.size for a in named.values())} weights")


def read(path, limit=None):
    """A split's swipes as (word, points[n, 3]) with x, y in [0, 1] and t in ms from the first point."""
    swipes = []
    with open(path) as lines:
        for line in lines:
            record = json.loads(line)
            data = record["data"]
            if len(data) < 2:
                continue
            points = np.array([[p["x"], p["y"], p["t"]] for p in data], np.float64)
            points[:, 2] -= points[0, 2]
            swipes.append((record["word"], points))
            if limit and len(swipes) >= limit:
                break
    return swipes


def data(directory, split, limit=None):
    names = {"test": "test.jsonl", "dev": "dev.jsonl"}
    source = fetch(DATASET, names[split], directory)
    swipes = read(source, int(limit) if limit else None)
    with open(os.path.join(directory, f"{split}.swipes"), "wb") as out:
        out.write(b"SWP1" + struct.pack("<I", len(swipes)))
        for word, points in swipes:
            raw = word.encode()
            out.write(struct.pack("<HH", len(raw), len(points)) + raw)
            out.write(points.astype("<f4").tobytes())
    print(f"{len(swipes)} swipes")


def resample(points, size=64):
    """The model card's input: a uniform 60 Hz resampling, then `size` evenly spaced points, as [2, size]."""
    x, y, t = points[:, 0], points[:, 1], points[:, 2]
    if t[-1] > 1e-3:
        count = max(2, round(t[-1] / (1000.0 / 60.0)) + 1)
        grid = np.linspace(0.0, t[-1], count)
        x, y = np.interp(grid, t, x), np.interp(grid, t, y)
    index = np.linspace(0, len(x) - 1, size)
    at = np.arange(len(x))
    return np.stack([np.interp(index, at, x), np.interp(index, at, y)]).astype(np.float32)


def reference(directory, split, count, path=None):
    """ExecuTorch's outputs for `count` swipes spread over the split: the model's input features, the encoder's
    log-emissions (the 26 letters and the blank) and the decoder's, after each swipe's word and points."""
    from executorch.runtime import Runtime
    import torch

    runtime = Runtime.get()
    encoder = runtime.load_program(os.path.join(directory, ENCODER, "model_fp32.pte")).load_method("forward")
    decoder = runtime.load_program(os.path.join(directory, DECODER, "model_fp32.pte")).load_method("forward")
    swipes = read(os.path.join(directory, f"{split}.jsonl"))
    chosen = np.linspace(0, len(swipes) - 1, int(count)).astype(int)
    keys = torch.zeros(1, 64, 2)
    keys[0, :26] = torch.from_numpy(KEYS)
    mask = torch.zeros(1, 64, dtype=torch.bool)
    mask[0, :26] = True
    with open(path or os.path.join(directory, f"{split}.reference"), "wb") as out:
        out.write(b"SWR1" + struct.pack("<I", len(chosen)) + KEYS.astype("<f4").tobytes())
        for i in chosen:
            word, points = swipes[i]
            points = points.astype("<f4").astype(np.float64)
            features = resample(points)
            log_emissions, coefficients, gate = encoder.execute((torch.from_numpy(features)[None], keys, mask))
            log_emissions = log_emissions.numpy()[0]
            letters = np.concatenate([log_emissions[:, :26], log_emissions[:, 64:]], 1)
            joint = np.concatenate([letters, coefficients.numpy()[0], gate.numpy()[0]], 1)
            refined = decoder.execute((torch.from_numpy(joint)[None],))[0].numpy()[0]
            raw = word.encode()
            out.write(struct.pack("<HH", len(raw), len(points)) + raw + points.astype("<f4").tobytes())
            for array in (features, letters, refined):
                out.write(np.ascontiguousarray(array, "<f4").tobytes())
    print(f"{len(chosen)} swipes")


if __name__ == "__main__":
    command, directory, *rest = sys.argv[1:]
    {"extract": extract, "data": data, "reference": reference}[command](directory, *rest)
