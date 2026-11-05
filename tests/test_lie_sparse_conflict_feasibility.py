"""A cheap owner/coverage conflict flag cannot detect same-owner depth error."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import unittest
import numpy as np
P=Path(__file__).resolve().parents[1]/'tools'/'lie_sparse_conflict_feasibility.py'
spec=importlib.util.spec_from_file_location('lie_sparse_conflict_feasibility',P)
probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)

class SparseConflictTest(unittest.TestCase):
    def test_owner_mismatch_is_flagged(self):
        r=np.zeros((probe.N,4),dtype='<f4')
        n=r.copy();r[4,3]=2.;n[4,3]=3.
        data=probe.evaluate(r,n,{'disagreement_pixels':[{'pixel_id':4}]})
        self.assertEqual(data['full_frame_owner_or_coverage_disagreements'],1)
        self.assertEqual(data['oracle_errors_flagged'],1)

    def test_same_owner_depth_error_escapes_flag(self):
        r=np.zeros((probe.N,4),dtype='<f4')
        n=r.copy();r[100,3]=3.;n[100,3]=3.
        n[100,2]=.15
        data=probe.evaluate(r,n,{'disagreement_pixels':[{'pixel_id':100}]})
        self.assertEqual(data['oracle_errors_unflagged'],1)
        self.assertEqual(data['unflagged_error_pixel_ids'],[100])

    def test_requires_matching_shapes(self):
        with self.assertRaises(ValueError):probe.flags(np.zeros((1,4)),np.zeros((2,4)))

if __name__=='__main__':unittest.main()
