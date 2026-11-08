#pragma once
#include "visibility_planner.hpp"
#include <chrono>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

class LieVisibilityPlanner : public godot::RefCounted {
  GDCLASS(LieVisibilityPlanner, godot::RefCounted)
  godot::PackedByteArray _plan, _indices, _instances, _jobs;
  bool _validated = false;

protected:
  static void _bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("select_clusters", "plan",
                                                "parameters", "instances",
                                                "jobs", "selection", "indices"),
                                &LieVisibilityPlanner::select_clusters);
    godot::ClassDB::bind_method(godot::D_METHOD("contract_version"),
                                &LieVisibilityPlanner::contract_version);
  }

public:
  int64_t contract_version() const { return 2; }
  godot::Dictionary select_clusters(const godot::PackedByteArray &plan,
                                    const godot::PackedByteArray &parameters,
                                    const godot::PackedByteArray &instances,
                                    const godot::PackedByteArray &jobs,
                                    const godot::PackedByteArray &selection,
                                    const godot::PackedByteArray &indices) {
    auto start = std::chrono::steady_clock::now();
    godot::Dictionary output;
    output["ok"] = false;
    auto bytes = [](const godot::PackedByteArray &data) {
      return lie::Bytes{data.ptr(), size_t(data.size())};
    };
    // Retained PackedByteArray references are immutable COW snapshots. A
    // mutation must detach; pointer+size identity can reuse permutation checks.
    auto same = [](const godot::PackedByteArray &a,
                   const godot::PackedByteArray &b) {
      return a.ptr() == b.ptr() && a.size() == b.size();
    };
    bool cached = _validated && same(plan, _plan) && same(indices, _indices) &&
                  same(instances, _instances) && same(jobs, _jobs);
    auto result = lie::select_clusters(
        bytes(plan), bytes(parameters), bytes(instances), bytes(jobs),
        bytes(selection), bytes(indices), cached);
    if (result.error) {
      output["reason"] = godot::String(result.error);
      return output;
    }
    _plan = plan;
    _indices = indices;
    _instances = instances;
    _jobs = jobs;
    _validated = true;
    godot::Array banks;
    for (size_t id = 0; id < result.banks.size(); id++) {
      const auto &bank = result.banks[id];
      if (!bank.work)
        continue;
      godot::PackedByteArray data;
      data.resize(((bank.rows.size() * 4 + bank.indices.size() + 3) / 4) * 16);
      auto ptr = data.ptrw();
      std::memset(ptr, 0, data.size());
      size_t offset = 0;
      for (auto row : bank.rows) {
        if (row[3])
          row[1] += uint32_t(bank.rows.size() * 4);
        for (uint32_t value : row)
          for (int k = 0; k < 4; k++)
            ptr[offset++] = uint8_t(value >> (8 * k));
      }
      for (uint32_t value : bank.indices)
        for (int k = 0; k < 4; k++)
          ptr[offset++] = uint8_t(value >> (8 * k));
      godot::Dictionary entry;
      entry["bank"] = int64_t(id);
      entry["data"] = data;
      entry["work"] = bank.work;
      entry["jobs"] = int64_t(bank.rows.size());
      banks.append(entry);
    }
    output["ok"] = true;
    output["permutation_validation_cached"] = cached;
    output["banks"] = banks;
    output["logical_samples"] = result.logical;
    output["selected_samples"] = result.selected;
    output["frustum_skipped_samples"] = result.frustum_skipped;
    output["backface_skipped_samples"] = result.backface_skipped;
    output["clusters"] = result.clusters;
    output["rejected_clusters"] = result.rejected_clusters;
    output["selected_jobs"] = result.selected_jobs;
    output["ranges"] = result.ranges;
    output["cpu_usec"] =
        int64_t(std::chrono::duration_cast<std::chrono::microseconds>(
                    std::chrono::steady_clock::now() - start)
                    .count());
    output["scope"] =
        "Native CPU conservative geometric backface planning, including "
        "validation and output packing. Not GPU time or optical occlusion.";
    return output;
  }
};
