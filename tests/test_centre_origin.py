"""Tests for centre-origin-nifti.py.

Needs nibabel, numpy and pytest. Images are built in the tests, so no data files
are required. The helpers are those of test_nifti.py.

Three groups of tests are marked "xfail, strict": they describe what the script should
do and does not yet. They are bugs found while writing these tests, not wishes:

* NaN: a float image with NaN in it (a masked statistics map, for instance) is
  refused with "Stored voxel values changed", because the verification compares with
  np.array_equal, for which NaN is different from NaN.
* All or nothing: the image is saved under its final name and verified afterwards,
  so a run that fails leaves a bad file there, destroys an earlier output, and
  destroys the input of a conversion in place. canonicalize-nifti.py and
  reorient2std-nifti.py write under a hidden temporary name and move the verified
  file into place.
* Large grids: the translation is stored as float32, and the verification allows the
  grid centre 1e-5 mm of error, less than float32 can hold above about 250 mm. About
  half of the grids of 500 to 2000 voxels with voxel sizes such as 0.7 or 1.1 mm are
  refused with "Grid centre is not at origin".

When one of them is fixed, its tests XPASS, which strict mode reports as a failure:
remove the marker then.
"""
import json
import math

import nibabel as nib
import numpy as np
import pytest

from test_nifti import (
    ALL_ORIENTATIONS,
    ROOT,
    change_a_value,
    corrupting_save,
    listing,
    make_affine,
    raw,
    run_in_process,
    run_script,
    volume,
    with_nans,
    write_nifti,
)

CENTRE = ROOT / "centre-origin-nifti.py"

NAN_BUG = pytest.mark.xfail(
    strict=True, raises=AssertionError,
    reason="compares voxels with np.array_equal: NaN differs from NaN, 'Stored voxel values changed'",
)
NOT_ALL_OR_NOTHING = pytest.mark.xfail(
    strict=True, raises=AssertionError,
    reason="saves under the final name before verifying: a failure leaves a bad file there",
)
FLOAT32_TOLERANCE = pytest.mark.xfail(
    strict=True, raises=AssertionError,
    reason="the translation is float32, the check allows 1e-5 mm: 'Grid centre is not at origin'",
)


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


def test_a_missing_input_is_reported_in_one_line(tmp_path):
    res = run_script(CENTRE, tmp_path / "nothing.nii.gz", tmp_path / "out.nii.gz")
    assert res.returncode != 0
    assert "Traceback" not in res.stderr
    assert res.stderr.startswith("centre-origin-nifti.py: ")
    assert "nothing.nii.gz" in res.stderr
    assert listing(tmp_path) == []


def test_a_missing_output_directory_is_reported_in_one_line(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    res = run_script(CENTRE, src, tmp_path / "no" / "such" / "out.nii.gz")
    assert res.returncode != 0
    assert "Traceback" not in res.stderr
    assert "out.nii.gz" in res.stderr
    assert listing(tmp_path) == ["in.nii.gz"]


# --- the verification catches real differences --------------------------------------


@pytest.mark.parametrize("dtype", [np.int16, np.float32])
def test_a_changed_voxel_value_is_detected(tmp_path, monkeypatch, dtype):
    src = write_nifti(tmp_path / "in.nii.gz", volume(dtype), make_affine())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, CENTRE, src, tmp_path / "out.nii.gz")


# --- known bugs: NaN -----------------------------------------------------------------


@NAN_BUG
@pytest.mark.parametrize("dtype", [np.float32, np.float64, np.complex64])
def test_an_image_with_nan_is_processed(tmp_path, dtype):
    data = with_nans(volume(dtype))
    src = write_nifti(tmp_path / "in.nii.gz", data, make_affine())
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    out = raw(tmp_path / "out.nii.gz")
    assert np.array_equal(np.isnan(out), np.isnan(data))
    assert np.array_equal(out[~np.isnan(data)], data[~np.isnan(data)])


@NAN_BUG
def test_an_image_of_only_nan_is_processed(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", np.full((4, 5, 6), np.nan, dtype=np.float32), make_affine())
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    assert np.isnan(raw(tmp_path / "out.nii.gz")).all()


@NAN_BUG
def test_an_image_with_nan_keeps_its_slope_and_intercept(tmp_path):
    src = write_nifti(tmp_path / "in.nii.gz", with_nans(volume(np.float32)), make_affine(), slope_inter=(2.0, 10.0))
    res = run_script(CENTRE, src, tmp_path / "out.nii.gz")
    assert res.returncode == 0, res.stderr
    out = nib.load(str(tmp_path / "out.nii.gz"))
    assert (out.dataobj.slope, out.dataobj.inter) == (2.0, 10.0)


# --- known bugs: all or nothing ------------------------------------------------------


@NOT_ALL_OR_NOTHING
def test_a_failed_verification_leaves_no_output(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, CENTRE, src, tmp_path / "out.nii.gz")
    assert listing(tmp_path) == ["in.nii.gz"]


@NOT_ALL_OR_NOTHING
def test_a_failed_verification_keeps_the_previous_output(tmp_path, monkeypatch):
    src = write_nifti(tmp_path / "in.nii.gz", volume(np.int16), make_affine())
    out = tmp_path / "out.nii.gz"
    out.write_bytes(b"an earlier output")
    monkeypatch.setattr(nib, "save", corrupting_save(nib.save, change_a_value))
    with pytest.raises(RuntimeError, match="(?i)voxel values"):
        run_in_process(monkeypatch, CENTRE, src, out, "--force")
    assert out.read_bytes() == b"an earlier output"


@NOT_ALL_OR_NOTHING
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


# --- known bugs: large grids ---------------------------------------------------------


def long_grid(n, zoom):
    aff = np.eye(4)
    aff[:3, :3] = np.diag([zoom, zoom, zoom])
    aff[:3, 3] = (10, 20, 30)
    return np.zeros((n, 3, 3), dtype=np.int8), aff


@pytest.mark.parametrize("n,zoom", [(600, 1.0), (512, 1.0), (300, 1.1)])
def test_large_grids_that_float32_holds_exactly_are_centred(tmp_path, n, zoom):
    out = centre(tmp_path, *long_grid(n, zoom))
    np.testing.assert_allclose(grid_centre(out), 0, atol=1e-3)


@FLOAT32_TOLERANCE
@pytest.mark.parametrize("n,zoom", [(512, 1.1), (512, 2.3), (777, 0.7), (1500, 0.7)])
def test_large_grids_with_voxel_sizes_that_float32_cannot_hold_are_centred(tmp_path, n, zoom):
    out = centre(tmp_path, *long_grid(n, zoom))
    # float32 has about seven digits: 1e-3 mm is generous at these sizes
    np.testing.assert_allclose(grid_centre(out), 0, atol=1e-3)
