"""Tests for centre-origin-nifti.py.

Needs nibabel, numpy and pytest. Images are built in the tests, so no data files
are required. The helpers are those of test_nifti.py, whose tests of NaN, of the
all-or-nothing output and of the error messages are repeated here for this script:
it has the same guarantees as canonicalize-nifti.py and reorient2std-nifti.py.
"""
import json
import math
import subprocess
import sys
import time
from pathlib import Path

import nibabel as nib
import numpy as np
import pytest

from test_nifti import (
    ALL_ORIENTATIONS,
    REORIENT,
    ROOT,
    change_a_value,
    corrupting_save,
    drop_a_nan,
    half_written_then_fail,
    listing,
    make_affine,
    raw,
    run_in_process,
    run_script,
    turn_a_value_into_nan,
    volume,
    with_nans,
    write_nifti,
)

CENTRE = ROOT / "centre-origin-nifti.py"

def grid_centre(path):
    """World coordinate of the centre of the voxel grid, by the qform."""
    img = nib.load(str(path))
    qform = img.get_qform()
    index = (np.asarray(img.shape[:3], dtype=float) - 1.0) / 2.0
    return qform[:3, :3] @ index + qform[:3, 3]


def centre(tmp_path, data, aff, *args, name="in.nii.gz", **kwargs):
    """Write an image, centre it, check that this worked, and return the output path."""
    src = write_nifti(tmp_path / name, data, aff, **kwargs)
    out = tmp_path / "out.nii.gz"
    res = run_script(CENTRE, src, out, *args)
    assert res.returncode == 0, res.stderr
    return out


def rotation(z_degrees, x_degrees):
    z, x = math.radians(z_degrees), math.radians(x_degrees)
    rz = np.array([[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]])
    rx = np.array([[1, 0, 0], [0, math.cos(x), -math.sin(x)], [0, math.sin(x), math.cos(x)]])
    return rz @ rx


# --- the grid centre moves to the origin ---------------------------------------------


@pytest.mark.parametrize("perm,flips", ALL_ORIENTATIONS)
def test_the_grid_centre_ends_up_at_the_origin_in_every_orientation(tmp_path, monkeypatch, perm, flips):
    aff = make_affine(zooms=(1.0, 2.0, 3.0), perm=perm, flips=flips, origin=(10, -20, 33))
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), aff)
    run_in_process(monkeypatch, CENTRE, src, tmp_path / "out.nii.gz")
    np.testing.assert_allclose(grid_centre(tmp_path / "out.nii.gz"), 0, atol=1e-4)


def test_the_new_translation_is_half_the_extent_of_the_grid(tmp_path):
    # shape (4, 5, 6) has its centre at voxel (1.5, 2, 2.5); the axes run along -x, -y, +z
    # with voxel sizes 1, 2, 3 mm: the centre lies at (-1.5, -4, 7.5) from voxel (0, 0, 0)
    aff = make_affine(zooms=(1.0, 2.0, 3.0), flips=(-1, -1, 1), origin=(10, 20, 30))
    out = centre(tmp_path, volume(np.int16, (4, 5, 6)), aff)
    np.testing.assert_allclose(nib.load(str(out)).get_qform()[:3, 3], (1.5, 4.0, -7.5), atol=1e-6)
    np.testing.assert_allclose(nib.load(str(out)).get_sform()[:3, 3], (1.5, 4.0, -7.5), atol=1e-6)


def test_an_oblique_image_is_centred_and_not_turned(tmp_path):
    aff = np.eye(4)
    aff[:3, :3] = rotation(20, 10) @ np.diag([0.9, 1.1, 2.5])
    aff[:3, 3] = (-40, 25, 90)
    out = centre(tmp_path, volume(np.int16), aff)
    np.testing.assert_allclose(grid_centre(out), 0, atol=1e-4)
    img = nib.load(str(out))
    np.testing.assert_allclose(img.get_qform()[:3, :3], aff[:3, :3], atol=1e-5)
    np.testing.assert_allclose(img.get_sform()[:3, :3], aff[:3, :3], atol=1e-5)


@pytest.mark.parametrize("flips", [(1, 1, 1), (-1, 1, 1), (-1, -1, 1), (-1, -1, -1)])
def test_voxel_sizes_axes_and_handedness_are_kept(tmp_path, flips):
    aff = make_affine(zooms=(0.8, 1.25, 3.0), flips=flips)
    out = centre(tmp_path, volume(np.int16), aff)
    before, after = nib.load(str(tmp_path / "in.nii.gz")), nib.load(str(out))
    np.testing.assert_allclose(after.header.get_zooms()[:3], before.header.get_zooms()[:3], atol=1e-6)
    assert nib.aff2axcodes(after.get_qform()) == nib.aff2axcodes(aff)
    assert np.sign(np.linalg.det(after.get_qform()[:3, :3])) == np.sign(np.linalg.det(aff[:3, :3]))


@pytest.mark.parametrize("qcode,scode", [(1, 1), (2, 4), (4, 2), (3, 3)])
def test_the_form_codes_are_kept(tmp_path, qcode, scode):
    out = centre(tmp_path, volume(np.int16), make_affine(), qcode=qcode, scode=scode)
    img = nib.load(str(out))
    assert int(img.get_qform(coded=True)[1]) == qcode
    assert int(img.get_sform(coded=True)[1]) == scode


def test_an_image_that_is_centred_already_stays_as_it_is(tmp_path):
    shape = (4, 5, 6)
    aff = make_affine(zooms=(1.0, 2.0, 3.0), flips=(-1, -1, 1), origin=(1.5, 4.0, -7.5))
    out = centre(tmp_path, volume(np.int16, shape), aff, "--json", tmp_path / "meta.json")
    np.testing.assert_allclose(nib.load(str(out)).get_qform(), aff, atol=1e-6)
    np.testing.assert_allclose(json.loads((tmp_path / "meta.json").read_text())["translation_shift_mm"], 0, atol=1e-6)


def test_centring_twice_is_the_same_as_once(tmp_path):
    first = centre(tmp_path, volume(np.int16), make_affine())
    again = tmp_path / "again.nii.gz"
    res = run_script(CENTRE, first, again)
    assert res.returncode == 0, res.stderr
    np.testing.assert_allclose(nib.load(str(again)).get_qform(), nib.load(str(first)).get_qform(), atol=1e-6)
    assert np.array_equal(raw(again), raw(first))


@pytest.mark.parametrize("name", ["in.nii.gz", "in.nii"])
def test_compressed_and_uncompressed_images(tmp_path, name):
    out = centre(tmp_path, volume(np.int16), make_affine(), name=name)
    np.testing.assert_allclose(grid_centre(out), 0, atol=1e-4)


def test_the_input_file_is_not_touched(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    before = src.read_bytes()
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    assert src.read_bytes() == before


# --- what must not change --------------------------------------------------------------


@pytest.mark.parametrize("dtype", [np.uint8, np.int16, np.int32, np.float32, np.float64])
def test_stored_values_and_data_type_are_kept(tmp_path, dtype):
    data = volume(dtype)
    out = centre(tmp_path, data, make_affine())
    img = nib.load(str(out))
    assert img.get_data_dtype() == np.dtype(dtype)
    assert img.shape == data.shape
    assert np.array_equal(raw(out), data)


def test_a_scaled_integer_image_keeps_its_stored_values_and_scaling(tmp_path):
    data = volume(np.int16)
    out = centre(tmp_path, data, make_affine(), slope_inter=(2.0, 10.0))
    img = nib.load(str(out))
    assert (img.dataobj.slope, img.dataobj.inter) == (2.0, 10.0)
    assert np.array_equal(raw(out), data)


def test_a_four_dimensional_image_is_centred_by_its_first_three_dimensions(tmp_path):
    data = volume(np.float32, (4, 5, 6, 3))
    out = centre(tmp_path, data, make_affine())
    assert nib.load(str(out)).shape == (4, 5, 6, 3)
    assert np.array_equal(raw(out), data)
    np.testing.assert_allclose(grid_centre(out), 0, atol=1e-4)


def test_the_rest_of_the_header_is_kept(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    img = nib.load(str(src))
    img.header["descrip"] = b"a scan of someone"
    img.header.set_xyzt_units("mm", "sec")
    nib.save(img, str(src))
    out = tmp_path / "out.nii.gz"
    res = run_script(CENTRE, src, out)
    assert res.returncode == 0, res.stderr
    header = nib.load(str(out)).header
    assert bytes(header["descrip"]).rstrip(b"\0") == b"a scan of someone"
    assert header.get_xyzt_units() == ("mm", "sec")


def test_infinities_are_processed(tmp_path):
    data = volume(np.float32)
    data[0, 0, 0], data[1, 1, 1] = np.inf, -np.inf
    out = centre(tmp_path, data, make_affine())
    assert np.array_equal(raw(out), data)


# --- the report ----------------------------------------------------------------------


def test_the_metadata_file_says_what_was_done(tmp_path):
    aff = make_affine(zooms=(1.0, 2.0, 3.0), flips=(-1, -1, 1), origin=(10, 20, 30))
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16, (4, 5, 6)), aff, slope_inter=(2.0, 10.0))
    out, meta = tmp_path / "out.nii.gz", tmp_path / "meta.json"
    res = run_script(CENTRE, src, out, "--json", meta)
    assert res.returncode == 0, res.stderr
    info = json.loads(meta.read_text())
    assert info["input"] == str(src) and info["output"] == str(out)
    assert info["shape"] == [4, 5, 6]
    assert info["axcodes"] == ["L", "P", "S"]
    assert (info["qform_code"], info["sform_code"]) == (1, 1)
    # the centre of the grid is at (-1.5, -4, 7.5) from the translation (10, 20, 30)
    np.testing.assert_allclose(info["input_grid_centre_mm"], (8.5, 16.0, 37.5), atol=1e-6)
    np.testing.assert_allclose(info["output_grid_centre_mm"], 0, atol=1e-5)
    np.testing.assert_allclose(info["translation_shift_mm"], (-8.5, -16.0, -37.5), atol=1e-6)
    assert info["raw_voxels_preserved_exactly"] is True
    assert (info["slope"], info["intercept"]) == (2.0, 10.0)


def test_no_metadata_file_without_the_option(tmp_path):
    centre(tmp_path, volume(np.int16), make_affine())
    assert listing(tmp_path) == ["in.nii.gz", "out.nii.gz"]


def test_the_report_on_standard_output(tmp_path):
    aff = make_affine(zooms=(1.0, 2.0, 3.0), flips=(-1, -1, 1), origin=(10, 20, 30))
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16, (4, 5, 6)), aff, slope_inter=(2.0, 10.0))
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    lines = res.stdout.splitlines()
    assert len(lines) == 4
    assert lines[0].startswith("input grid centre:")
    np.testing.assert_allclose([float(x) for x in lines[0].split(":")[1].split()], (8.5, 16.0, 37.5), atol=1e-4)
    assert lines[1].startswith("output grid centre:")
    np.testing.assert_allclose([float(x) for x in lines[1].split(":")[1].split()], 0, atol=1e-4)
    assert lines[2] == "raw voxel values preserved exactly: yes"
    assert lines[3] == "scaling preserved: 2 10"


# --- inputs that are refused, and nothing is written ---------------------------------


def test_an_image_with_fewer_than_three_dimensions_is_refused(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", np.zeros((4, 5), dtype=np.int16), make_affine())
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode != 0
    assert "at least three dimensions" in res.stderr
    assert listing(tmp_path) == ["in.nii.gz"]


@pytest.mark.parametrize("which,message", [("qform_code", "qform is undefined"), ("sform_code", "sform is undefined")])
def test_an_undefined_form_is_refused(tmp_path, which, message):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    img = nib.load(str(src))
    img.header[which] = 0
    nib.save(img, str(src))
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode != 0
    assert message in res.stderr
    assert listing(tmp_path) == ["in.nii.gz"]


def test_differing_qform_and_sform_are_refused(tmp_path):
    aff = make_affine()
    img = nib.Nifti1Image(volume(np.int16), aff)
    img.set_qform(aff, 1)
    img.set_sform(make_affine(origin=(99, 99, 99)), 1)
    nib.save(img, str(tmp_path / "in.nii.gz"))
    res = run_script(CENTRE, tmp_path / "in.nii.gz", tmp_path / "out.nii.gz")
    assert res.returncode != 0
    assert "qform and sform differ" in res.stderr
    assert listing(tmp_path) == ["in.nii.gz"]


def test_an_existing_output_is_not_overwritten_without_force(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / "out.nii.gz"
    out.write_text("existing")
    res = run_script(CENTRE, src, out)
    assert res.returncode != 0
    assert "--force" in res.stderr
    assert out.read_text() == "existing"
    res = run_script(CENTRE, src, out, "--force")
    assert res.returncode == 0, res.stderr
    np.testing.assert_allclose(grid_centre(out), 0, atol=1e-4)


def reported_in_one_line(res):
    """The error output has one line of the script's own, and the script did not crash
    with a traceback of its own. (Python 3.14 prints a harmless "Exception ignored"
    traceback of gzip.py at exit when nibabel could not open a file, before or after
    the message; it belongs to neither the script nor the message.)"""
    own = [line for line in res.stderr.splitlines() if line.startswith("centre-origin-nifti.py: ")]
    assert len(own) == 1, res.stderr
    assert f'File "{CENTRE}"' not in res.stderr
    return own[0]


def test_a_missing_input_is_reported_in_one_line(tmp_path):
    res = run_script(CENTRE, tmp_path / "nothing.nii.gz", tmp_path / "out.nii.gz")
    assert res.returncode != 0
    assert "nothing.nii.gz" in reported_in_one_line(res)
    assert listing(tmp_path) == []


def test_a_missing_output_directory_is_reported_in_one_line(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    res = run_script(CENTRE, src, tmp_path / "no" / "such" / "out.nii.gz")
    assert res.returncode != 0
    assert "out.nii.gz" in reported_in_one_line(res)
    assert listing(tmp_path) == ["in.nii.gz"]


# --- the verification catches real differences --------------------------------------


@pytest.mark.parametrize("dtype", [np.int16, np.float32])
def test_a_changed_voxel_value_is_detected(tmp_path, monkeypatch, dtype):
    src = write_nifti(tmp_path / "in.nii.gz", volume(dtype), make_affine())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, CENTRE, src, tmp_path / "out.nii.gz")


# --- NaN in floating point images ----------------------------------------------------


@pytest.mark.parametrize("dtype", [np.float32, np.float64, np.complex64])
def test_an_image_with_nan_is_processed(tmp_path, dtype):
    data = with_nans(volume(dtype))
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine())
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    out = raw(tmp_path / "out.nii.gz")
    assert np.array_equal(np.isnan(out), np.isnan(data))
    assert np.array_equal(out[~np.isnan(data)], data[~np.isnan(data)])


def test_an_image_of_only_nan_is_processed(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", np.full((4, 5, 6), np.nan, dtype=np.float32), make_affine())
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    assert np.isnan(raw(tmp_path / "out.nii.gz")).all()


def test_an_image_with_nan_keeps_its_slope_and_intercept(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", with_nans(volume(np.float32)), make_affine(), slope_inter=(2.0, 10.0))
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    out = nib.load(str(tmp_path / "out.nii.gz"))
    assert (out.dataobj.slope, out.dataobj.inter) == (2.0, 10.0)


# --- the output is all or nothing ----------------------------------------------------


def test_a_failed_verification_leaves_no_output(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, CENTRE, src, tmp_path / "out.nii.gz")
    assert listing(tmp_path) == ["in.nii.gz"]


def test_a_failed_verification_keeps_the_previous_output(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / "out.nii.gz"
    out.write_bytes(b"an earlier output")
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, CENTRE, src, out, "--force")
    assert out.read_bytes() == b"an earlier output"


def test_a_failed_conversion_in_place_leaves_the_input_untouched(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "scan.nii.gz", volume(np.int16), make_affine())
    before = src.read_bytes()
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, CENTRE, src, src, "--force")
    assert src.read_bytes() == before


def test_converting_in_place_works(tmp_path):
    src = write_nifti(tmp_path / "scan.nii.gz", volume(np.int16), make_affine())
    res = run_script(CENTRE, src, src, "--force")
    assert res.returncode == 0, res.stderr
    np.testing.assert_allclose(grid_centre(src), 0, atol=1e-4)
    assert np.array_equal(raw(src), volume(np.int16))


# --- large grids: the translation is stored as float32 -------------------------------


def long_grid(n, zoom):
    aff = np.eye(4)
    aff[:3, :3] = np.diag([zoom, zoom, zoom])
    aff[:3, 3] = (10, 20, 30)
    return np.zeros((n, 3, 3), dtype=np.int8), aff


@pytest.mark.parametrize("n,zoom", [(600, 1.0), (512, 1.0), (300, 1.1)])
def test_large_grids_that_float32_holds_exactly_are_centred(tmp_path, n, zoom):
    out = centre(tmp_path, *long_grid(n, zoom))
    np.testing.assert_allclose(grid_centre(out), 0, atol=1e-3)


@pytest.mark.parametrize("n,zoom", [(512, 1.1), (512, 2.3), (777, 0.7), (1500, 0.7)])
def test_large_grids_with_voxel_sizes_that_float32_cannot_hold_are_centred(tmp_path, n, zoom):
    out = centre(tmp_path, *long_grid(n, zoom))
    # float32 has about seven digits: 1e-3 mm is generous at these sizes
    np.testing.assert_allclose(grid_centre(out), 0, atol=1e-3)


# --- the output is all or nothing: the rest of it ------------------------------------
#
# The image (and the metadata file) is written under a hidden temporary name next to its
# destination, verified there, and only then moved into place. A run that fails, is
# interrupted or runs out of disk space leaves nothing at the destination and nothing
# else behind; an earlier output stays as it was.


def test_a_failed_verification_leaves_no_metadata_file(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError):
        run_in_process(monkeypatch, CENTRE, src, tmp_path / "out.nii.gz", "--json", tmp_path / "side.json")
    assert listing(tmp_path) == ["in.nii.gz"]


def test_a_failed_verification_keeps_the_previous_output_and_metadata(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = write_nifti(tmp_path / "out.nii.gz", volume(np.uint8), make_affine(zooms=(2, 2, 2)))
    side = tmp_path / "side.json"
    side.write_text("previous")
    before = (out.read_bytes(), side.read_text())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError):
        run_in_process(monkeypatch, CENTRE, src, out, "--json", side, "--force")
    assert (out.read_bytes(), side.read_text()) == before
    assert listing(tmp_path) == ["in.nii.gz", "out.nii.gz", "side.json"]


def test_running_out_of_disk_space_leaves_nothing(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    monkeypatch.setattr(nib, "save", half_written_then_fail(nib.save))
    with pytest.raises(OSError, match="No space left"):
        run_in_process(monkeypatch, CENTRE, src, tmp_path / "out.nii.gz")
    assert listing(tmp_path) == ["in.nii.gz"]


def test_a_failed_conversion_in_place_leaves_nothing_else_behind(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "scan.nii.gz", volume(np.int16), make_affine())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError):
        run_in_process(monkeypatch, CENTRE, src, src, "--force")
    assert listing(tmp_path) == ["scan.nii.gz"]


def test_converting_in_place_leaves_only_the_image(tmp_path):
    src = write_nifti(tmp_path / "scan.nii.gz", volume(np.int16), make_affine())
    res = run_script(CENTRE, src, src, "--force")
    assert res.returncode == 0, res.stderr
    assert listing(tmp_path) == ["scan.nii.gz"]


def test_only_the_requested_files_remain_after_success(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz", "--json", tmp_path / "side.json")
    assert res.returncode == 0, res.stderr
    assert listing(tmp_path) == ["in.nii.gz", "out.nii.gz", "side.json"]
    assert json.loads((tmp_path / "side.json").read_text())


def test_bare_file_names_in_the_current_directory(tmp_path):
    write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    res = run_script(CENTRE, "in.nii.gz", "out.nii.gz", "--json", "side.json", cwd=tmp_path)
    assert res.returncode == 0, res.stderr
    assert listing(tmp_path) == ["in.nii.gz", "out.nii.gz", "side.json"]


@pytest.mark.parametrize("name", ["out.nii.gz", "out.nii", "scan.v2.nii.gz"])
def test_the_image_is_first_written_to_a_hidden_file_of_the_same_kind(tmp_path, monkeypatch, name):
    """The temporary name keeps the extension (nibabel chooses the format by it) and is
    hidden, so that a glob such as *.nii.gz does not pick up an unfinished file."""
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / name
    names = []
    original_save = nib.save

    def spy(img, fname, *args, **kwargs):
        names.append(Path(fname))
        return original_save(img, fname, *args, **kwargs)

    monkeypatch.setattr(nib, "save", spy)
    run_in_process(monkeypatch, CENTRE, src, out)
    assert len(names) == 1
    written = names[0]
    assert written != out
    assert written.parent == out.parent
    assert written.name.startswith(".")
    assert written.name.endswith("".join(out.suffixes))
    assert listing(tmp_path) == sorted(["in.nii.gz", name])


def test_being_terminated_leaves_nothing(tmp_path):
    """A cluster stops a job that overruns with SIGTERM before it kills it."""
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / "out.nii.gz"
    ready = tmp_path / "ready"
    driver = f"""
import importlib.util, sys, time
import nibabel as nib
spec = importlib.util.spec_from_file_location("script", {str(CENTRE)!r})
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original_save = nib.save
def slow_save(img, fname, *args, **kwargs):
    original_save(img, fname, *args, **kwargs)   # the whole file is on disk ...
    open({str(ready)!r}, "w").close()
    time.sleep(60)                               # ... but the job is not finished
nib.save = slow_save
sys.argv = [{CENTRE.name!r}, {str(src)!r}, {str(out)!r}]
module.main()
"""
    proc = subprocess.Popen([sys.executable, "-c", driver], stderr=subprocess.DEVNULL)
    try:
        for _ in range(200):
            if ready.exists() or proc.poll() is not None:
                break
            time.sleep(0.05)
        assert ready.exists(), "the script never got as far as saving"
        proc.terminate()
        proc.wait(timeout=20)
    finally:
        if proc.poll() is None:
            proc.kill()
    assert proc.returncode != 0
    assert not out.exists()
    assert listing(tmp_path) == ["in.nii.gz", "ready"]


def test_refusing_to_overwrite_changes_nothing(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / "out.nii.gz"
    out.write_text("existing")
    res = run_script(CENTRE, src, out, "--json", tmp_path / "side.json")
    assert res.returncode != 0
    assert listing(tmp_path) == ["in.nii.gz", "out.nii.gz"]
    assert out.read_text() == "existing"


# --- errors name the file the user asked for, not the temporary one ------------------


def test_a_missing_output_directory_names_the_requested_path(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / "no" / "such" / "out.nii.gz"
    res = run_script(CENTRE, src, out)
    assert res.returncode != 0
    assert str(out) in res.stderr
    assert ".tmp" not in res.stderr
    assert listing(tmp_path) == ["in.nii.gz"]


def test_a_write_error_names_the_requested_path(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / "out.nii.gz"

    def failing_save(img, fname, *args, **kwargs):
        raise OSError(13, "Permission denied", str(fname))

    monkeypatch.setattr(nib, "save", failing_save)
    with pytest.raises(OSError) as info:
        run_in_process(monkeypatch, CENTRE, src, out)
    assert str(out) in str(info.value)
    assert ".tmp" not in str(info.value)
    assert listing(tmp_path) == ["in.nii.gz"]


def test_failing_to_move_the_output_into_place_names_only_the_requested_path(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / "out.nii.gz"
    out.mkdir()                              # a directory in the way: the final rename fails
    res = run_script(CENTRE, src, out, "--force")
    assert res.returncode != 0
    assert str(out) in res.stderr
    assert ".tmp" not in res.stderr
    assert " -> " not in res.stderr
    assert listing(tmp_path) == ["in.nii.gz", "out.nii.gz"]


# --- overwriting --------------------------------------------------------------------


def test_an_output_that_is_a_symlink_is_written_through(tmp_path):
    data = volume(np.int16)
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine())
    real = tmp_path / "real.nii.gz"
    real.write_text("placeholder")
    link = tmp_path / "link.nii.gz"
    link.symlink_to(real.name)
    res = run_script(CENTRE, src, link, "--force")
    assert res.returncode == 0, res.stderr
    assert link.is_symlink()
    assert np.array_equal(raw(real), data)
    assert listing(tmp_path) == ["in.nii.gz", "link.nii.gz", "real.nii.gz"]


def test_overwriting_keeps_the_permissions_of_the_file(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = write_nifti(tmp_path / "out.nii.gz", volume(np.int16), make_affine())
    side = tmp_path / "side.json"
    side.write_text("{}")
    out.chmod(0o664)
    side.chmod(0o660)
    res = run_script(CENTRE, src, out, "--json", side, "--force")
    assert res.returncode == 0, res.stderr
    assert out.stat().st_mode & 0o777 == 0o664
    assert side.stat().st_mode & 0o777 == 0o660


# --- the verification still catches real differences ---------------------------------


@pytest.mark.parametrize(
    "damage", [change_a_value, turn_a_value_into_nan, drop_a_nan],
    ids=["value-changed", "value-became-nan", "nan-became-value"],
)
def test_real_differences_are_detected_in_an_image_with_nan(tmp_path, monkeypatch, damage):
    src = write_nifti(tmp_path / "in.nii.gz", with_nans(volume(np.float32)), make_affine())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, damage))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, CENTRE, src, tmp_path / "out.nii.gz")


def shifting_save(original_save, shift_mm):
    """A save that puts the grid centre somewhere else than the origin."""

    def save(img, fname, *args, **kwargs):
        aff = img.get_qform().copy()
        aff[:3, 3] += shift_mm
        moved = nib.Nifti1Image(np.asanyarray(img.dataobj), aff, header=img.header)
        moved.set_qform(aff, 1)
        moved.set_sform(aff, 1)
        original_save(moved, fname, *args, **kwargs)

    return save


@pytest.mark.parametrize("n,zoom,shift", [(6, 2.0, 1.0), (6, 2.0, 0.001), (1500, 0.7, 0.01)])
def test_a_grid_centre_that_is_not_at_the_origin_is_detected(tmp_path, monkeypatch, n, zoom, shift):
    """The tolerance follows the precision of float32 at the size of the grid, and no more:
    a real shift of 1 micrometre on a small grid and of 10 micrometre on a large one is caught."""
    data, aff = long_grid(n, zoom)
    src = write_nifti(tmp_path / "in.nii.gz", data, aff)
    monkeypatch.setattr(nib, "save", shifting_save(nib.save, shift))
    with pytest.raises(RuntimeError, match="Grid centre is not at origin"):
        run_in_process(monkeypatch, CENTRE, src, tmp_path / "out.nii.gz")
    assert listing(tmp_path) == ["in.nii.gz"]


# --- the helpers are copies of those of the other scripts ----------------------------


def test_the_helpers_shared_with_the_other_scripts_are_identical():
    """The scripts are installed one by one, so the helpers are copied, not imported."""
    import ast

    def definitions(script):
        text = script.read_text()
        return {
            node.name: ast.get_source_segment(text, node)
            for node in ast.parse(text).body
            if isinstance(node, (ast.FunctionDef, ast.ClassDef))
        }

    centre_helpers, reorient = definitions(CENTRE), definitions(REORIENT)
    for name in ("temporary_name", "Staged", "staged_outputs", "same_values", "raw_data", "scaling"):
        assert name in centre_helpers and name in reorient, name
        assert centre_helpers[name] == reorient[name], name
