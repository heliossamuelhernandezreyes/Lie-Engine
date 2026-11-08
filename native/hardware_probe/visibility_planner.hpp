// Portable CPU visibility planning. No GPU-vendor API, threading or Godot
// types.
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <vector>

namespace lie {
struct Bytes {
  const uint8_t *data;
  size_t size;
  const char **error = nullptr;
  void fail(const char *reason) const {
    if (error && !*error)
      *error = reason;
  }
  uint32_t u32(size_t at) const {
    if (at > size || size - at < 4) {
      fail("packet_bounds");
      return 0;
    }
    return uint32_t(data[at]) | (uint32_t(data[at + 1]) << 8) |
           (uint32_t(data[at + 2]) << 16) | (uint32_t(data[at + 3]) << 24);
  }
  double f32(size_t at) const {
    static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559);
    uint32_t bits = u32(at);
    float value;
    std::memcpy(&value, &bits, 4);
    if (!std::isfinite(value)) {
      fail("nonfinite_packet");
      return 0;
    }
    return value;
  }
};
using Vec = std::array<double, 3>;
inline Vec cross(Vec a, Vec b) {
  return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
          a[0] * b[1] - a[1] * b[0]};
}
inline double dot(Vec a, Vec b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
inline double sum_abs(Vec a) {
  return std::abs(a[0]) + std::abs(a[1]) + std::abs(a[2]);
}
struct ViewInterval {
  Vec eye{};
  double condition = 0;
  bool enabled = false;
};
inline ViewInterval local_view(Bytes instances, size_t id, Vec eye,
                               bool enabled) {
  size_t at = id * 96;
  Vec x{}, y{}, z{}, d{};
  for (int k = 0; k < 3; k++) {
    x[k] = instances.f32(at + k * 4);
    y[k] = instances.f32(at + 16 + k * 4);
    z[k] = instances.f32(at + 32 + k * 4);
    d[k] = eye[k] - instances.f32(at + 48 + k * 4);
  }
  auto r0 = cross(y, z), r1 = cross(z, x), r2 = cross(x, y);
  double det = dot(x, r0);
  ViewInterval result;
  // Fail open on unstable transforms: never certify a backface from them.
  if (std::abs(det) < 1e-12)
    return result;
  for (int k = 0; k < 3; k++) {
    r0[k] /= det;
    r1[k] /= det;
    r2[k] /= det;
  }
  double norm = 0;
  for (int k = 0; k < 3; k++)
    norm = std::max(norm, std::abs(x[k]) + std::abs(y[k]) + std::abs(z[k]));
  result.condition = norm * std::max({sum_abs(r0), sum_abs(r1), sum_abs(r2)});
  result.eye = {dot(r0, d), dot(r1, d), dot(r2, d)};
  result.enabled =
      enabled && std::isfinite(result.condition) && result.condition <= 64.;
  return result;
}
inline bool certainly_backfacing(Bytes plan, size_t at,
                                 const ViewInterval &view) {
  double upper = 0, scale = 1;
  for (int k = 0; k < 3; k++) {
    double plo = plan.f32(at + 16 + k * 4), phi = plan.f32(at + 28 + k * 4);
    double nlo = plan.f32(at + 40 + k * 4), nhi = plan.f32(at + 52 + k * 4);
    if (plo > phi || nlo > nhi || nlo < -1.001 || nhi > 1.001) {
      plan.fail("cluster_bounds");
      return false;
    }
    double lo = view.eye[k] - phi, hi = view.eye[k] - plo;
    upper += std::max({nlo * lo, nlo * hi, nhi * lo, nhi * hi});
    scale += std::max(std::abs(nlo), std::abs(nhi)) *
             std::max(std::abs(lo), std::abs(hi));
  }
  // Broad error guard against float32 inverse/normalization in the GPU. The
  // shader requires front > .015; we only remove strictly negative intervals.
  return view.enabled && upper < -1e-4 * std::max(1., view.condition) * scale;
}
struct BankDispatch {
  std::vector<std::array<uint32_t, 4>> rows;
  std::vector<uint32_t> indices;
  uint32_t work = 0;
};
struct VisibilityResult {
  const char *error = nullptr;
  static VisibilityResult failure(const char *reason) {
    VisibilityResult result;
    result.error = reason;
    return result;
  }
  std::array<BankDispatch, 16> banks;
  uint32_t logical = 0, selected = 0, frustum_skipped = 0, backface_skipped = 0;
  uint32_t clusters = 0, rejected_clusters = 0, selected_jobs = 0, ranges = 0;
};
inline VisibilityResult select_clusters(Bytes plan, Bytes parameters,
                                        Bytes instances, Bytes jobs,
                                        Bytes selection,
                                        Bytes indices = {nullptr, 0},
                                        bool trusted_indices = false) {
  if (parameters.size != 256 || !instances.size || instances.size % 96 ||
      instances.size > 2048 * 96 || !jobs.size || jobs.size % 16 ||
      jobs.size > 2048 * 16 || !plan.size || plan.size % 64 ||
      plan.size > 131072 * 64 ||
      (selection.size && selection.size != jobs.size / 16))
    return VisibilityResult::failure("packet_shape");
  const char *error = nullptr;
  plan.error = parameters.error = instances.error = jobs.error = indices.error =
      selection.error = &error;
  size_t count = jobs.size / 16;
  VisibilityResult result;
  std::vector<uint32_t> offsets(count), bank_ids(count);
  std::vector<bool> used(count, false);
  std::vector<ViewInterval> views;
  views.reserve(count);
  Vec eye{parameters.f32(0), parameters.f32(4), parameters.f32(8)};
  bool unmodified = parameters.f32(244) >= .5;
  for (size_t j = 0; j < count; j++) {
    uint32_t amount = jobs.u32(j * 16 + 4), id = jobs.u32(j * 16 + 8),
             prefix = jobs.u32(j * 16 + 12);
    if (!amount || amount > 3000000 || id >= instances.size / 96 ||
        prefix != result.logical || result.logical > 3000000 - amount ||
        (selection.size && selection.data[j] > 1))
      return VisibilityResult::failure("job_contract");
    double bank = instances.f32(size_t(id) * 96 + 68);
    if (bank < 0 || bank > 15 || bank != std::floor(bank))
      return VisibilityResult::failure("bank_contract");
    bank_ids[j] = uint32_t(bank);
    result.logical += amount;
    if (selection.size && !selection.data[j])
      result.frustum_skipped += amount;
    views.push_back(local_view(instances, id, eye, unmodified));
  }
  if (error)
    return VisibilityResult::failure(error);
  bool indexed = indices.size != 0;
  if (indexed && indices.size != size_t(result.logical) * 4)
    return VisibilityResult::failure("index_packet_shape");
  if (indexed && !trusted_indices) {
    for (size_t j = 0; j < count; j++) {
      uint32_t amount = jobs.u32(j * 16 + 4), prefix = jobs.u32(j * 16 + 12);
      std::vector<uint8_t> seen(amount, 0);
      for (uint32_t k = 0; k < amount; k++) {
        uint32_t id = indices.u32(size_t(prefix + k) * 4);
        if (id >= amount || seen[id])
          return VisibilityResult::failure("index_permutation");
        seen[id] = 1;
      }
    }
  }
  uint32_t last_job = 0;
  for (size_t at = 0; at < plan.size; at += 64) {
    uint32_t j = plan.u32(at), offset = plan.u32(at + 4),
             amount = plan.u32(at + 8), bank = plan.u32(at + 12);
    if (j >= count || j < last_job ||
        offset != offsets[j] + (indexed ? jobs.u32(j * 16 + 12) : 0) ||
        !amount || amount > 64 || bank != bank_ids[j] ||
        amount > jobs.u32(j * 16 + 4) - offsets[j])
      return VisibilityResult::failure("cluster_partition");
    offsets[j] += amount;
    last_job = j;
    result.clusters++;
    bool back = certainly_backfacing(plan, at, views[j]);
    if (error)
      return VisibilityResult::failure(error);
    if (selection.size && !selection.data[j])
      continue;
    if (back) {
      result.backface_skipped += amount;
      result.rejected_clusters++;
      continue;
    }
    auto &dispatch = result.banks[bank];
    if (indexed) {
      if (dispatch.rows.empty() || dispatch.rows.back()[2] != j) {
        dispatch.rows.push_back(
            {dispatch.work, uint32_t(dispatch.indices.size()), j, 1});
        result.ranges++;
      }
      uint32_t prefix = jobs.u32(j * 16 + 12);
      for (uint32_t k = 0; k < amount; k++)
        dispatch.indices.push_back(prefix +
                                   indices.u32(size_t(offset + k) * 4));
      dispatch.work += amount;
    } else {
      uint32_t first = jobs.u32(j * 16 + 12) + offset;
      if (!dispatch.rows.empty() && dispatch.rows.back()[2] == j &&
          dispatch.rows.back()[1] + dispatch.work - dispatch.rows.back()[0] ==
              first) {
        dispatch.work += amount;
      } else {
        dispatch.rows.push_back({dispatch.work, first, j, 0});
        dispatch.work += amount;
        result.ranges++;
      }
    }
    result.selected += amount;
    if (!used[j]) {
      used[j] = true;
      result.selected_jobs++;
    }
  }
  for (size_t j = 0; j < count; j++)
    if (offsets[j] != jobs.u32(j * 16 + 4))
      return VisibilityResult::failure("incomplete_partition");
  return result;
}
} // namespace lie
