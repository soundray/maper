#!/usr/bin/env python3

import argparse
import json
import os
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


def grid_centre_world(affine, shape):
    centre_index = (np.asarray(shape[:3], dtype=float) - 1.0) / 2.0
    return affine[:3, :3] @ centre_index + affine[:3, 3]


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Set the physical coordinate of the NIfTI voxel-grid centre "
            "to (0,0,0) without changing voxel data, scaling, orientation, "
            "voxel sizes, or the affine linear component."
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

    nib.save(out, args.output)

    # Verify the file as actually written.
    check = nib.load(args.output)

    saved_qform, saved_qcode = check.get_qform(coded=True)
    saved_sform, saved_scode = check.get_sform(coded=True)

    if check.shape != img.shape:
        raise RuntimeError("Image dimensions changed")

    if check.get_data_dtype() != img.get_data_dtype():
        raise RuntimeError("Datatype changed")

    if not np.array_equal(data, raw_data(check)):
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
        atol=AFFINE_ATOL,
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
        with open(args.json, "w") as f:
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
