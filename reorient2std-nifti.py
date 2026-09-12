#!/nix/store/fxlbzqvqshjdn2spl0v8i6wp9n6cq13d-python3-3.14.7-env/bin/python

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


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Reorient a NIfTI image to an FSL-reorient2std-like storage "
            "orientation without interpolation. Positive-handed images are "
            "stored RAS; negative-handed images LAS. Physical coordinates "
            "are preserved."
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

    nib.save(out, args.output)

    # Verify the file as actually written.
    check = nib.load(args.output)

    saved_qform, saved_qcode = check.get_qform(coded=True)
    saved_sform, saved_scode = check.get_sform(coded=True)

    expected_raw = np.asanyarray(out_data)
    saved_raw = raw_data(check)

    if not np.array_equal(expected_raw, saved_raw):
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
        with open(args.json, "w") as f:
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

