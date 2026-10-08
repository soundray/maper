#!/usr/bin/env python3

import argparse
import contextlib
import json
import os
import shutil
import signal
import sys

import nibabel as nib
import numpy as np


AFFINE_ATOL = 1e-5
FLOAT32_EPS = float(np.finfo(np.float32).eps)


def raw_data(img):
    """Return stored voxel values without applying NIfTI scaling."""
    obj = img.dataobj
    if hasattr(obj, "get_unscaled"):
        return np.asanyarray(obj.get_unscaled())
    return np.asanyarray(obj)


def scaling(img):
    """Return NIfTI slope/intercept as represented by the array proxy."""
    obj = img.dataobj
    slope = getattr(obj, "slope", 1.0)
    inter = getattr(obj, "inter", 0.0)

    if slope is None:
        slope = 1.0
    if inter is None:
        inter = 0.0

    return float(slope), float(inter)


def same_values(a, b):
    """True if the arrays hold the same values.

    NaNs at the same positions count as equal. np.array_equal says that NaN
    differs from NaN, so every floating point image containing a NaN failed
    the verification of the written file. (np.array_equal(..., equal_nan=True)
    would do, but it needs numpy 1.19.) The same function is in
    canonicalize-nifti.py, centre-origin-nifti.py and reorient2std-nifti.py.
    """
    a = np.asanyarray(a)
    b = np.asanyarray(b)
    if np.array_equal(a, b):
        return True
    # Unequal. That can still be only the NaNs, which need a closer look.
    if a.shape != b.shape:
        return False
    if not (np.issubdtype(a.dtype, np.inexact) and np.issubdtype(b.dtype, np.inexact)):
        return False
    a_nan = np.isnan(a)
    if not (a_nan.any() and np.array_equal(a_nan, np.isnan(b))):
        return False
    keep = ~a_nan
    return bool(np.array_equal(a[keep], b[keep]))


def temporary_name(final):
    """A hidden name next to <final>, with the same extension.

    nibabel chooses the file format by the extension, and a pattern such as
    *.nii.gz does not match a hidden file, so an unfinished file is not
    mistaken for a result.
    """
    directory, name = os.path.split(final)
    dot = name.find(".", 1)
    stem, suffix = (name, "") if dot < 0 else (name[:dot], name[dot:])
    return os.path.join(directory, ".%s.tmp%d%s" % (stem, os.getpid(), suffix))


class Staged:
    """Output files written under temporary names, moved into place together."""

    def __init__(self):
        self.pairs = []

    def path_for(self, final):
        """The temporary path to write what is meant for <final>."""
        if os.path.islink(final):  # a symlink is written through, as it always was
            final = os.path.realpath(final)
        temporary = temporary_name(final)
        self.pairs.append((temporary, final))
        return temporary

    def commit(self):
        for temporary, final in self.pairs:
            if os.path.isfile(final):  # overwriting keeps the permissions of the file
                shutil.copymode(final, temporary)
            os.replace(temporary, final)
        self.pairs = []

    def discard(self):
        for temporary, _ in self.pairs:
            with contextlib.suppress(FileNotFoundError):
                os.remove(temporary)
        self.pairs = []


@contextlib.contextmanager
def staged_outputs():
    """Leave either all outputs or none, and an earlier output as it was.

    What is written through the yielded Staged object goes to temporary files
    next to the destinations; they are renamed (atomically) when the block
    ends without an error, and removed when it ends with one -- also when it
    ends with an interrupt or with SIGTERM, which is what a cluster sends to
    a job that overruns before it kills it. The same code is in
    canonicalize-nifti.py, centre-origin-nifti.py and reorient2std-nifti.py.
    """

    def terminated(signum, frame):
        sys.exit(128 + signum)

    try:
        previous = signal.signal(signal.SIGTERM, terminated)
    except ValueError:  # not the main thread
        previous = None
    staged = Staged()
    try:
        yield staged
        staged.commit()
    except BaseException as error:
        pairs = list(staged.pairs)
        staged.discard()
        if isinstance(error, OSError) and error.errno is not None:
            # name the file that was asked for, not its temporary stand-in
            for temporary, final in pairs:
                if temporary in (error.filename, error.filename2):
                    raise type(error)(error.errno, error.strerror, final) from None
        raise
    finally:
        if previous is not None:
            signal.signal(signal.SIGTERM, previous)


def grid_centre_world(affine, shape):
    centre_index = (np.asarray(shape[:3], dtype=float) - 1.0) / 2.0
    return affine[:3, :3] @ centre_index + affine[:3, 3]


def centre_tolerance(affine, shape):
    """How far from the origin the centre of the grid may be in the written file.

    The header holds the affine as float32, so the centre of a large grid cannot
    be put at the origin more exactly than a few units in the last place of the
    coordinates that add up to it: the translation and the half extent of the
    grid. AFFINE_ATOL alone, 1e-5 mm, is less than float32 can hold above
    about 250 mm, and refused grids such as 512 voxels of 1.1 mm.
    """
    index = (np.asarray(shape[:3], dtype=float) - 1.0) / 2.0
    half_extent = np.abs(affine[:3, :3]) @ index
    return AFFINE_ATOL + 4.0 * FLOAT32_EPS * float(np.max(half_extent))


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Set the physical coordinate of the NIfTI voxel-grid centre "
            "to (0,0,0) without changing voxel data, scaling, orientation, "
            "voxel sizes, or the affine linear component. The output (and "
            "the file given with --json) is written under a temporary name "
            "and moved into place only after it has been verified; if "
            "anything fails, nothing is left behind."
        )
    )
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument(
        "--json",
        metavar="FILE",
        help="write centring metadata to JSON",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite output if it exists",
    )
    args = parser.parse_args()

    if os.path.exists(args.output) and not args.force:
        raise SystemExit(
            f"Output exists: {args.output} (use --force to overwrite)"
        )

    img = nib.load(args.input)

    if len(img.shape) < 3:
        raise RuntimeError("Input must have at least three dimensions")

    qform, qcode = img.get_qform(coded=True)
    sform, scode = img.get_sform(coded=True)

    if qcode == 0:
        raise RuntimeError(
            "qform is undefined; canonicalize image geometry first"
        )

    if scode == 0:
        raise RuntimeError(
            "sform is undefined; canonicalize image geometry first"
        )

    if not np.allclose(qform, sform, rtol=0, atol=AFFINE_ATOL):
        raise RuntimeError(
            "qform and sform differ; run maper-canonicalize-nifti first"
        )

    affine = qform
    input_centre = grid_centre_world(affine, img.shape)

    centre_index = (
        np.asarray(img.shape[:3], dtype=float) - 1.0
    ) / 2.0

    new_affine = affine.copy()
    new_affine[:3, 3] = -(
        affine[:3, :3] @ centre_index
    )

    data = raw_data(img)
    slope, inter = scaling(img)

    header = img.header.copy()

    out = img.__class__(
        data,
        new_affine,
        header=header,
    )

    out.set_data_dtype(img.get_data_dtype())
    out.set_qform(new_affine, int(qcode))
    out.set_sform(new_affine, int(scode))
    out.header.set_slope_inter(slope, inter)

    with staged_outputs() as staged:
        written = staged.path_for(args.output)
        nib.save(out, written)

        # Verify the file as actually written.
        check = nib.load(written)

        saved_qform, saved_qcode = check.get_qform(coded=True)
        saved_sform, saved_scode = check.get_sform(coded=True)

        if check.shape != img.shape:
            raise RuntimeError("Image dimensions changed")

        if check.get_data_dtype() != img.get_data_dtype():
            raise RuntimeError("Datatype changed")

        if not same_values(data, raw_data(check)):
            raise RuntimeError("Stored voxel values changed")

        saved_slope, saved_inter = scaling(check)

        if saved_slope != slope or saved_inter != inter:
            raise RuntimeError("NIfTI intensity scaling changed")

        if int(saved_qcode) != int(qcode):
            raise RuntimeError("qform code changed unexpectedly")

        if int(saved_scode) != int(scode):
            raise RuntimeError("sform code changed unexpectedly")

        if not np.allclose(
            saved_qform[:3, :3],
            affine[:3, :3],
            rtol=0,
            atol=AFFINE_ATOL,
        ):
            raise RuntimeError("qform linear component changed")

        if not np.allclose(
            saved_sform[:3, :3],
            affine[:3, :3],
            rtol=0,
            atol=AFFINE_ATOL,
        ):
            raise RuntimeError("sform linear component changed")

        if not np.allclose(
            saved_qform,
            saved_sform,
            rtol=0,
            atol=AFFINE_ATOL,
        ):
            raise RuntimeError("Output qform and sform differ")

        output_centre = grid_centre_world(
            saved_qform,
            check.shape,
        )

        if not np.allclose(
            output_centre,
            np.zeros(3),
            rtol=0,
            atol=centre_tolerance(saved_qform, check.shape),
        ):
            raise RuntimeError(
                f"Grid centre is not at origin: {output_centre}"
            )

        # Centring must not change handedness/storage orientation.
        if nib.aff2axcodes(saved_qform) != nib.aff2axcodes(affine):
            raise RuntimeError("Storage orientation changed unexpectedly")

        input_det = np.linalg.det(affine[:3, :3])
        output_det = np.linalg.det(saved_qform[:3, :3])

        if not np.isclose(
            input_det, output_det, rtol=0, atol=1e-10
        ):
            raise RuntimeError("Affine determinant changed unexpectedly")

        metadata = {
            "input": args.input,
            "output": args.output,
            "shape": list(check.shape),
            "axcodes": list(nib.aff2axcodes(saved_qform)),
            "qform_code": int(saved_qcode),
            "sform_code": int(saved_scode),
            "input_grid_centre_mm": input_centre.tolist(),
            "output_grid_centre_mm": output_centre.tolist(),
            "translation_shift_mm": (
                saved_qform[:3, 3] - affine[:3, 3]
            ).tolist(),
            "raw_voxels_preserved_exactly": True,
            "slope": saved_slope,
            "intercept": saved_inter,
        }

        if args.json:
            with open(staged.path_for(args.json), "w") as f:
                json.dump(metadata, f, indent=2)
                f.write("\n")

    print(
        "input grid centre:  "
        + " ".join(f"{x:g}" for x in input_centre)
    )
    print(
        "output grid centre: "
        + " ".join(f"{x:g}" for x in output_centre)
    )
    print("raw voxel values preserved exactly: yes")
    print(f"scaling preserved: {saved_slope:g} {saved_inter:g}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(
            f"{os.path.basename(sys.argv[0])}: {exc}",
            file=sys.stderr,
        )
        sys.exit(1)
