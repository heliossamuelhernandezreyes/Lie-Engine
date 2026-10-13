"""Offline contract checks for the CC0 LIE material source catalog."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("lie_material_masters", ROOT / "tools" / "lie_material_masters.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MaterialMastersTest(unittest.TestCase):
    def test_catalog_has_ten_unique_cc0_sources(self):
        catalog, items = MODULE.load_catalog()
        self.assertEqual(catalog["schema"], "lie-material-catalog/1.0")
        self.assertEqual(len(items), 10)
        self.assertEqual(len({entry["id"] for entry, _, _ in items}), 10)
        self.assertEqual(len({item["provenance"]["asset_id"] for _, item, _ in items}), 10)
        self.assertEqual(len([entry for entry, _, _ in items if entry["category"] == "brick"]), 3)
        for entry, item, directory in items:
            source = item["provenance"]
            self.assertEqual(source["license"], "CC0-1.0")
            self.assertEqual(source["provider"], "Poly Haven")
            self.assertEqual(source["api"], MODULE.BASE_API + source["asset_id"])
            self.assertEqual(source["page"], "https://polyhaven.com/a/" + source["asset_id"])
            self.assertFalse(item["physical_scale"]["provider_metadata_verified"])
            self.assertFalse(item["lie_contract"]["hero_visual_quality_accepted"])
            self.assertIn("NOT", source["source_type"])
            self.assertEqual(entry["preferred_master_resolution"] in MODULE.RESOLUTIONS, True)
            self.assertTrue(directory.is_dir())

    def test_map_resolver_without_network(self):
        mock = {}
        for key in ("Diffuse", "nor_gl", "Displacement", "Rough"):
            mock[key] = {"8k": {"png": {"url": "https://dl.polyhaven.org/file/texture.png"}}}
        maps = MODULE.select_maps(mock, "8k")
        self.assertEqual(set(maps), set(MODULE.REQUIRED))
        self.assertEqual(maps["normal_gl"]["api_key"], "nor_gl")
        self.assertRaises(KeyError, MODULE.select_maps, mock, "16k")
        mock["AO"] = {"8k": {"png": {"url": "http://evil.example/test.png"}}}
        self.assertRaises(ValueError, MODULE.select_maps, mock, "8k")


if __name__ == "__main__":
    unittest.main()
