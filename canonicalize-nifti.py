#!/usr/bin/env python3

import argparse
import json
import numpy as np
import nibabel as nib


def same_values(a, b):
    """True if the arrays hold the same values.

    NaNs at the same positions count as equal. np.array_equal says that NaN
    differs from NaN, so every floating point image containing a NaN failed
    the verification of the written file. (np.array_equal(..., equal_nan=True)
    would do, but it needs numpy 1.19.) The same function is in
    reorient2std-nifti.py and canonicalize-nifti.py.
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


def main():
    p = argparse.ArgumentParser(
        description="Make NIfTI qform and sform consistently use the input qform."
    )
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument(
        "--geometry-json",
        help="Save original qform/sform matrices and codes as JSON",
    )
    args = p.parse_args()

    img = nib.load(args.input)
    qform, qcode = img.get_qform(coded=True)
    sform, scode = img.get_sform(coded=True)

    if qform is None or int(qcode) == 0:
        raise SystemExit("Input has no valid qform; refusing to canonicalize")

    proxy = img.dataobj
    raw = proxy.get_unscaled()

    slope = getattr(proxy, "slope", 1.0)
    inter = getattr(proxy, "inter", 0.0)
    slope = 1.0 if slope is None else float(slope)
    inter = 0.0 if inter is None else float(inter)

    hdr = img.header.copy()
    out = img.__class__(raw, qform, header=hdr)

    out.set_qform(qform, code=int(qcode))
    out.set_sform(qform, code=int(qcode))
    out.header.set_slope_inter(slope, inter)

    nib.save(out, args.output)

    if args.geometry_json:
        with open(args.geometry_json, "w") as f:
            json.dump(
                {
                    "shape": list(img.shape),
                    "qform_code": int(qcode),
                    "qform": qform.tolist(),
                    "sform_code": int(scode),
                    "sform": None if sform is None else sform.tolist(),
                },
                f,
                indent=2,
            )

    # Verify what was written.
    chk = nib.load(args.output)

    if not same_values(raw, chk.dataobj.get_unscaled()):
        raise RuntimeError("Stored voxel values changed")

    cq, cqc = chk.get_qform(coded=True)
    cs, csc = chk.get_sform(coded=True)

    if int(cqc) != int(qcode) or int(csc) != int(qcode):
        raise RuntimeError("Unexpected qform/sform codes")

    if not np.allclose(cq, qform) or not np.allclose(cs, qform):
        raise RuntimeError("Output geometry does not match input qform")


if __name__ == "__main__":
    main()
