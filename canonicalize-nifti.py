#!/usr/bin/env python3

import argparse
import contextlib
import json
import os
import shutil
import signal
import sys

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
    reorient2std-nifti.py and canonicalize-nifti.py.
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
    p = argparse.ArgumentParser(
        description=(
            "Make NIfTI qform and sform consistently use the input qform. "
            "The output (and the file given with --geometry-json) is written "
            "under a temporary name and moved into place only after it has "
            "been verified; if anything fails, nothing is left behind."
        )
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

    with staged_outputs() as staged:
        written = staged.path_for(args.output)
        nib.save(out, written)

        if args.geometry_json:
            with open(staged.path_for(args.geometry_json), "w") as f:
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
        chk = nib.load(written)

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
