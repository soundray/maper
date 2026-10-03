"""Tests for canonicalize-nifti.py and reorient2std-nifti.py.

Needs nibabel, numpy and pytest. Images are built in the tests, so no data
files are required.
"""
import importlib.util
import itertools
import json
import subprocess
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
import pytest

ROOT = Path(__file__).resolve().parent.parent
CANON = ROOT / "canonicalize-nifti.py"
REORIENT = ROOT / "reorient2std-nifti.py"
SCRIPTS = [pytest.param(CANON, id="canonicalize"), pytest.param(REORIENT, id="reorient")]


def load_module(path):
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_script(script, *args):
    return subprocess.run(
        [sys.executable, str(script), *map(str, args)], capture_output=True, text=True
    )


def run_in_process(monkeypatch, script, *args):
    monkeypatch.setattr(sys, "argv", [script.name, *map(str, args)])
    load_module(script).main()


def make_affine(zooms=(1.0, 2.0, 3.0), perm=(0, 1, 2), flips=(-1, -1, 1), origin=(10, 20, 30)):
    """Voxel axis i runs along world axis perm[i], in direction flips[i]."""
    rot = np.zeros((3, 3))
    for i in range(3):
        rot[perm[i], i] = flips[i]
    aff = np.eye(4)
    aff[:3, :3] = rot @ np.diag(zooms)
    aff[:3, 3] = origin
    return aff


def write_nifti(path, data, aff, qcode=1, scode=1, slope_inter=None):
    img = nib.Nifti1Image(data, aff)
    img.set_qform(aff, qcode)
    img.set_sform(aff, scode)
    if slope_inter is not None:
        img.header.set_slope_inter(*slope_inter)
    nib.save(img, str(path))
    return path


def raw(path):
    return np.asanyarray(nib.load(str(path)).dataobj.get_unscaled())


def volume(dtype, shape=(4, 5, 6)):
    n = int(np.prod(shape))
    return (np.arange(n) % 100 + 1).astype(dtype).reshape(shape)


def with_nans(data, positions=((0, 0, 0), (3, 4, 5))):
    data = data.copy()
    for p in positions:
        data[p] = np.nan
    return data


def assert_same_with_nans(actual, expected):
    assert actual.shape == expected.shape
    assert np.array_equal(np.isnan(actual), np.isnan(expected)), "NaN positions differ"
    ok = ~np.isnan(expected)
    assert np.array_equal(actual[ok], expected[ok]), "values differ"


# --- NaN in floating point images --------------------------------------------------


@pytest.mark.parametrize("script", SCRIPTS)
@pytest.mark.parametrize("dtype", [np.float32, np.float64, np.complex64])
def test_image_with_nan_is_processed(tmp_path, script, dtype):
    """A float image with NaNs (masked statistics maps, for instance) is valid input."""
    data = with_nans(volume(dtype))
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine())
    res = run_script(script, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    out = raw(tmp_path / "out.nii.gz")
    if script == CANON:
        assert_same_with_nans(out, data)
    else:  # reorient2std flips the first two axes of this LPS image
        assert_same_with_nans(out, data[::-1, ::-1, :])


@pytest.mark.parametrize("script", SCRIPTS)
def test_image_of_only_nan_is_processed(tmp_path, script):
    data = np.full((4, 5, 6), np.nan, dtype=np.float32)
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine())
    res = run_script(script, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    assert np.isnan(raw(tmp_path / "out.nii.gz")).all()


@pytest.mark.parametrize("script", SCRIPTS)
def test_infinities_are_processed(tmp_path, script):
    data = volume(np.float32)
    data[0, 0, 0], data[1, 1, 1] = np.inf, -np.inf
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine())
    res = run_script(script, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr


@pytest.mark.parametrize("script", SCRIPTS)
def test_nan_image_keeps_its_slope_and_intercept(tmp_path, script):
    data = with_nans(volume(np.float32))
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine(), slope_inter=(2.0, 10.0))
    res = run_script(script, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    out = nib.load(str(tmp_path / "out.nii.gz"))
    assert (out.dataobj.slope, out.dataobj.inter) == (2.0, 10.0)


# --- the verification must still catch real differences ------------------------------


def corrupting_save(original_save, damage):
    def save(img, fname, *args, **kwargs):
        original_save(img, fname, *args, **kwargs)
        data = np.asanyarray(img.dataobj).copy()
        damage(data)
        original_save(nib.Nifti1Image(data, img.affine, header=img.header), fname)

    return save


# The damage is aimed at positions found in the data itself: reorient2std moves
# voxels, so a fixed index would not always hit what the test name says.


def first_position(mask):
    return tuple(np.argwhere(mask)[0])


def change_a_value(data):
    data[first_position(~np.isnan(data))] += 1


def turn_a_value_into_nan(data):
    data[first_position(~np.isnan(data))] = np.nan


def drop_a_nan(data):
    data[first_position(np.isnan(data))] = 0.0


@pytest.mark.parametrize("script", SCRIPTS)
@pytest.mark.parametrize(
    "damage", [change_a_value, turn_a_value_into_nan, drop_a_nan],
    ids=["value-changed", "value-became-nan", "nan-became-value"],
)
def test_real_differences_are_still_detected(tmp_path, monkeypatch, script, damage):
    data = with_nans(volume(np.float32))
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, damage))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, script, src, tmp_path / "out.nii.gz")


@pytest.mark.parametrize("script", SCRIPTS)
def test_real_difference_in_an_integer_image_is_detected(tmp_path, monkeypatch, script):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, script, src, tmp_path / "out.nii.gz")


@pytest.mark.parametrize("script", SCRIPTS)
class TestSameValues:
    """same_values(a, b): equal arrays, with NaNs at equal positions counting as equal."""

    @pytest.fixture
    def same_values(self, script):
        return load_module(script).same_values

    def test_equal_arrays(self, same_values):
        assert same_values(volume(np.int16), volume(np.int16))

    def test_equal_arrays_with_nan(self, same_values):
        assert same_values(with_nans(volume(np.float32)), with_nans(volume(np.float32)))

    def test_different_values(self, same_values):
        a = with_nans(volume(np.float32))
        b = a.copy()
        b[2, 2, 2] += 1
        assert not same_values(a, b)

    def test_nan_at_different_positions(self, same_values):
        a = with_nans(volume(np.float32), [(0, 0, 0)])
        b = with_nans(volume(np.float32), [(0, 0, 1)])
        assert not same_values(a, b)

    def test_nan_against_number(self, same_values):
        a = with_nans(volume(np.float32), [(0, 0, 0)])
        b = volume(np.float32)
        assert not same_values(a, b)

    def test_different_shapes(self, same_values):
        assert not same_values(volume(np.float32, (4, 5, 6)), volume(np.float32, (4, 5, 7)))

    def test_infinities(self, same_values):
        a = volume(np.float32)
        a[0, 0, 0] = np.inf
        assert same_values(a, a.copy())
        b = a.copy()
        b[0, 0, 0] = -np.inf
        assert not same_values(a, b)

    def test_integer_arrays_are_compared_plainly(self, same_values):
        a = volume(np.uint8)
        b = a.copy()
        b[0, 0, 0] += 1
        assert not same_values(a, b)

    def test_structured_dtype(self, same_values):
        rgb = np.dtype([("R", "u1"), ("G", "u1"), ("B", "u1")])
        a = np.zeros((2, 2, 2), dtype=rgb)
        assert same_values(a, a.copy())
        b = a.copy()
        b["G"][0, 0, 0] = 7
        assert not same_values(a, b)


# --- canonicalize-nifti.py -------------------------------------------------------------


def test_canonicalize_scaled_integer_image_keeps_stored_values_and_scaling(tmp_path):
    data = volume(np.int16)
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine(), slope_inter=(2.0, 10.0))
    res = run_script(CANON, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    out = nib.load(str(tmp_path / "out.nii.gz"))
    assert (out.dataobj.slope, out.dataobj.inter) == (2.0, 10.0)
    assert np.array_equal(raw(tmp_path / "out.nii.gz"), data)
    assert np.allclose(np.asanyarray(out.dataobj), data * 2.0 + 10.0)


def test_canonicalize_makes_sform_follow_qform(tmp_path):
    qaff = make_affine(origin=(1, 2, 3))
    img = nib.Nifti1Image(volume(np.int16), qaff)
    img.set_qform(qaff, 1)
    img.set_sform(make_affine(zooms=(2, 2, 2), origin=(7, 8, 9)), 4)
    nib.save(img, str(tmp_path / "in.nii.gz"))
    geometry = tmp_path / "geometry.json"
    res = run_script(CANON, tmp_path / "in.nii.gz", tmp_path / "out.nii.gz", "--geometry-json", geometry)
    assert res.returncode == 0, res.stderr
    out = nib.load(str(tmp_path / "out.nii.gz"))
    q, qcode = out.get_qform(coded=True)
    s, scode = out.get_sform(coded=True)
    assert np.allclose(q, qaff) and np.allclose(s, qaff)
    assert int(qcode) == 1 and int(scode) == 1
    saved = json.loads(geometry.read_text())
    assert saved["sform_code"] == 4 and saved["qform_code"] == 1
    assert np.allclose(saved["sform"], make_affine(zooms=(2, 2, 2), origin=(7, 8, 9)))


def test_canonicalize_refuses_an_image_without_qform(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine(), qcode=0)
    res = run_script(CANON, src, tmp_path / "out.nii.gz")
    assert res.returncode != 0
    assert "no valid qform" in res.stderr


# --- reorient2std-nifti.py -------------------------------------------------------------


ALL_ORIENTATIONS = [
    pytest.param(perm, flips, id="perm%s-flips%s" % ("".join(map(str, perm)), "".join("+" if f > 0 else "-" for f in flips)))
    for perm in itertools.permutations(range(3))
    for flips in itertools.product((1, -1), repeat=3)
]


@pytest.mark.parametrize("perm,flips", ALL_ORIENTATIONS)
def test_reorient_preserves_the_value_at_every_world_position(tmp_path, monkeypatch, perm, flips):
    zooms = (1.0, 2.0, 3.0)
    aff = make_affine(zooms, perm, flips)
    data = np.arange(4 * 5 * 6, dtype=np.int32).reshape(4, 5, 6)
    src = write_nifti(tmp_path / "in.nii.gz", data, aff)
    run_in_process(monkeypatch, REORIENT, src, tmp_path / "out.nii.gz")
    out = nib.load(str(tmp_path / "out.nii.gz"))
    out_data = raw(tmp_path / "out.nii.gz")

    det = np.linalg.det(aff[:3, :3])
    assert nib.aff2axcodes(out.affine) == (("R", "A", "S") if det > 0 else ("L", "A", "S"))

    # every output voxel, mapped to world space and back into the input, holds the same value
    j = np.indices(out_data.shape).reshape(3, -1)
    world = out.affine[:3, :3] @ j + out.affine[:3, 3:4]
    i = np.rint(np.linalg.inv(aff[:3, :3]) @ (world - aff[:3, 3:4])).astype(int)
    assert (i >= 0).all() and (i < np.array(data.shape)[:, None]).all()
    assert np.array_equal(data[i[0], i[1], i[2]], out_data.reshape(-1))

    # voxel sizes follow their world axes: input axis a runs along world axis perm[a]
    expected = [zooms[perm.index(w)] for w in range(3)]
    assert np.allclose(out.header.get_zooms()[:3], expected)


def test_reorient_handles_a_four_dimensional_image(tmp_path):
    data = np.arange(4 * 5 * 6 * 3, dtype=np.int16).reshape(4, 5, 6, 3)
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine())
    res = run_script(REORIENT, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    assert np.array_equal(raw(tmp_path / "out.nii.gz"), data[::-1, ::-1, :, :])


@pytest.mark.parametrize("dtype", [np.uint8, np.int16, np.int32, np.float32, np.float64])
def test_reorient_keeps_the_data_type(tmp_path, dtype):
    src = write_nifti(tmp_path / "in.nii.gz", volume(dtype), make_affine())
    res = run_script(REORIENT, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    assert nib.load(str(tmp_path / "out.nii.gz")).get_data_dtype() == np.dtype(dtype)


def test_reorient_scaled_integer_image_keeps_stored_values_and_scaling(tmp_path):
    data = volume(np.int16)
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine(), slope_inter=(2.0, 10.0))
    res = run_script(REORIENT, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    out = nib.load(str(tmp_path / "out.nii.gz"))
    assert (out.dataobj.slope, out.dataobj.inter) == (2.0, 10.0)
    assert np.array_equal(raw(tmp_path / "out.nii.gz"), data[::-1, ::-1, :])


def test_reorient_writes_metadata_json(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    meta = tmp_path / "meta.json"
    res = run_script(REORIENT, src, tmp_path / "out.nii.gz", "--json", meta)
    assert res.returncode == 0, res.stderr
    info = json.loads(meta.read_text())
    assert info["input_axcodes"] == ["L", "P", "S"]
    assert info["output_axcodes"] == ["R", "A", "S"]
    assert info["raw_voxels_preserved_exactly"] is True


def test_reorient_does_not_overwrite_without_force(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / "out.nii.gz"
    out.write_text("existing")
    res = run_script(REORIENT, src, out)
    assert res.returncode != 0
    assert "--force" in res.stderr
    assert out.read_text() == "existing"
    res = run_script(REORIENT, src, out, "--force")
    assert res.returncode == 0, res.stderr


def test_reorient_refuses_differing_qform_and_sform(tmp_path):
    aff = make_affine()
    img = nib.Nifti1Image(volume(np.int16), aff)
    img.set_qform(aff, 1)
    img.set_sform(make_affine(origin=(99, 99, 99)), 1)
    nib.save(img, str(tmp_path / "in.nii.gz"))
    res = run_script(REORIENT, tmp_path / "in.nii.gz", tmp_path / "out.nii.gz")
    assert res.returncode != 0
    assert "qform and sform differ" in res.stderr


@pytest.mark.parametrize("which,message", [("qform_code", "qform is undefined"), ("sform_code", "sform is undefined")])
def test_reorient_refuses_an_undefined_form(tmp_path, which, message):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    img = nib.load(str(src))
    img.header[which] = 0
    nib.save(img, str(src))
    res = run_script(REORIENT, src, tmp_path / "out.nii.gz")
    assert res.returncode != 0
    assert message in res.stderr
