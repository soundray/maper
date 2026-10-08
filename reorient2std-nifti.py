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


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Reorient a NIfTI image to an FSL-reorient2std-like storage "
            "orientation without interpolation. Positive-handed images are "
            "stored RAS; negative-handed images LAS. Physical coordinates "
            "are preserved. The output (and the file given with --json) is "
            "written under a temporary name and moved into place only after "
            "it has been verified; if anything fails, nothing is left behind."
        )
    )
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument(
        "--json",
        metavar="FILE",
        help="write reorientation metadata to JSON",
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

    # After canonicalization qform and sform describe the same physical
    # voxel lattice. Use qform explicitly rather than relying on NiBabel's
    # sform/qform precedence.
    affine = qform

    determinant = np.linalg.det(affine[:3, :3])

    if not np.isfinite(determinant) or abs(determinant) < 1e-12:
        raise RuntimeError(
            f"Invalid or singular spatial affine: determinant={determinant}"
        )

    if determinant > 0:
        target_axcodes = ("R", "A", "S")
    else:
        target_axcodes = ("L", "A", "S")

    source_ornt = nib.orientations.io_orientation(affine)
    target_ornt = nib.orientations.axcodes2ornt(target_axcodes)

    transform = nib.orientations.ornt_transform(
        source_ornt,
        target_ornt,
    )

    data = raw_data(img)
    out_data = nib.orientations.apply_orientation(data, transform)

    # inv_ornt_aff maps output voxel indices back to input voxel indices.
    # Therefore:
    #
    #     output voxel -> input voxel -> physical coordinates
    #
    new_affine = (
        affine
        @ nib.orientations.inv_ornt_aff(
            transform,
            img.shape[:3],
        )
    )

    slope, inter = scaling(img)

    header = img.header.copy()

    out = img.__class__(
        out_data,
        new_affine,
        header=header,
    )

    # Be explicit about datatype and geometry.
    out.set_data_dtype(img.get_data_dtype())
    out.set_qform(new_affine, int(qcode))
    out.set_sform(new_affine, int(scode))

    # Preserve NIfTI value scaling rather than silently baking it into
    # the stored voxel values.
    out.header.set_slope_inter(slope, inter)

    with staged_outputs() as staged:
        written = staged.path_for(args.output)
        nib.save(out, written)

        # Verify the file as actually written.
        check = nib.load(written)

        saved_qform, saved_qcode = check.get_qform(coded=True)
        saved_sform, saved_scode = check.get_sform(coded=True)

        expected_raw = np.asanyarray(out_data)
        saved_raw = raw_data(check)

        if not same_values(expected_raw, saved_raw):
            raise RuntimeError(
                "Saved raw voxel values differ from the expected "
                "permuted/flipped input"
            )

        if not np.allclose(
            saved_qform, new_affine, rtol=0, atol=AFFINE_ATOL
        ):
            raise RuntimeError("Saved qform does not match expected affine")

        if not np.allclose(
            saved_sform, new_affine, rtol=0, atol=AFFINE_ATOL
        ):
            raise RuntimeError("Saved sform does not match expected affine")

        if int(saved_qcode) != int(qcode):
            raise RuntimeError("qform code changed unexpectedly")

        if int(saved_scode) != int(scode):
            raise RuntimeError("sform code changed unexpectedly")

        saved_axcodes = nib.aff2axcodes(check.affine)

        if saved_axcodes != target_axcodes:
            raise RuntimeError(
                f"Unexpected output orientation: {saved_axcodes}; "
                f"expected {target_axcodes}"
            )

        metadata = {
            "input": args.input,
            "output": args.output,
            "input_shape": list(img.shape),
            "output_shape": list(check.shape),
            "input_axcodes": list(nib.aff2axcodes(affine)),
            "output_axcodes": list(saved_axcodes),
            "determinant": float(determinant),
            "target_axcodes": list(target_axcodes),
            "orientation_transform": transform.tolist(),
            "qform_code": int(saved_qcode),
            "sform_code": int(saved_scode),
            "raw_voxels_preserved_exactly": True,
        }

        if args.json:
            with open(staged.path_for(args.json), "w") as f:
                json.dump(metadata, f, indent=2)
                f.write("\n")

    print(
        f"{''.join(metadata['input_axcodes'])}"
        f" -> "
        f"{''.join(metadata['output_axcodes'])}"
    )
    print(f"determinant: {determinant:g}")
    print(f"input shape:  {tuple(img.shape)}")
    print(f"output shape: {tuple(check.shape)}")
    print("raw voxel values preserved exactly: yes")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"{os.path.basename(sys.argv[0])}: {exc}", file=sys.stderr)
        sys.exit(1)
