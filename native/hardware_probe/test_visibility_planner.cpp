#include "visibility_planner.hpp"
#include <cassert>
#include <iostream>
#include <random>

using Packet = std::vector<uint8_t>;
void u32(Packet &p, size_t at, uint32_t value) {
  for (int k = 0; k < 4; k++)
    p.at(at + k) = uint8_t(value >> (k * 8));
}
void f32(Packet &p, size_t at, float value) {
  uint32_t bits;
  std::memcpy(&bits, &value, 4);
  u32(p, at, bits);
}
lie::Bytes bytes(const Packet &p) { return {p.data(), p.size()}; }
Packet instance(float x = 1, float y = 1, float z = 1) {
  Packet p(96);
  f32(p, 0, x);
  f32(p, 20, y);
  f32(p, 40, z);
  return p;
}
Packet params(float z = 5) {
  Packet p(256);
  f32(p, 8, z);
  f32(p, 244, 1);
  return p;
}
Packet job(uint32_t count) {
  Packet p(16);
  u32(p, 4, count);
  return p;
}
Packet cluster(uint32_t offset, lie::Vec normal) {
  Packet p(64);
  u32(p, 4, offset);
  u32(p, 8, 64);
  for (int k = 0; k < 3; k++) {
    f32(p, 40 + k * 4, float(normal[k]));
    f32(p, 52 + k * 4, float(normal[k]));
  }
  return p;
}
template <class Fn> void rejects(Fn fn) { assert(fn().error != nullptr); }
int main() {
  Packet plan;
  for (int i = 0; i < 5; i++) {
    auto c = cluster(i * 64, {0, 0, (i == 1 || i == 4) ? -1. : 1.});
    plan.insert(plan.end(), c.begin(), c.end());
  }
  auto p = params(), inst = instance(), jobs = job(320);
  Packet selection;
  auto run = [&]() {
    return lie::select_clusters(bytes(plan), bytes(p), bytes(inst), bytes(jobs),
                                bytes(selection));
  };
  auto r = run();
  assert(r.selected == 192 && r.backface_skipped == 128 && r.logical == 320 &&
         r.ranges == 2);
  assert(r.banks[0].rows[0][1] == 0 && r.banks[0].rows[1][1] == 128 &&
         r.banks[0].rows[1][0] == 64);
  assert(r.banks[0].work == 192 && r.selected_jobs == 1);
  Packet permutation(320 * 4);
  std::vector<uint32_t> ids(320);
  for (uint32_t i = 0; i < 320; i++)
    ids[i] = i;
  std::mt19937 permutation_rng(7319);
  std::shuffle(ids.begin(), ids.end(), permutation_rng);
  for (size_t i = 0; i < ids.size(); i++)
    u32(permutation, i * 4, ids[i]);
  auto indexed =
      lie::select_clusters(bytes(plan), bytes(p), bytes(inst), bytes(jobs),
                           bytes(selection), bytes(permutation));
  assert(!indexed.error && indexed.selected == 192 && indexed.ranges == 1 &&
         indexed.banks[0].indices.size() == 192);
  for (size_t i = 0; i < 64; i++)
    assert(indexed.banks[0].indices[i] == ids[i]);
  for (size_t i = 0; i < 128; i++)
    assert(indexed.banks[0].indices[i + 64] == ids[i + 128]);
  u32(permutation, 0, ids[1]);
  assert(lie::select_clusters(bytes(plan), bytes(p), bytes(inst), bytes(jobs),
                              bytes(selection), bytes(permutation))
             .error);
  u32(permutation, 0, ids[0]);
  selection = {0};
  r = run();
  assert(r.selected == 0 && r.frustum_skipped == 320 &&
         r.backface_skipped == 0);
  selection = {2};
  rejects(run);
  selection.clear();
  u32(plan, 4, 1);
  rejects(run);
  u32(plan, 4, 0);
  f32(plan, 40, std::numeric_limits<float>::quiet_NaN());
  rejects(run);
  f32(plan, 40, 0);
  u32(jobs, 12, 1);
  rejects(run);
  u32(jobs, 12, 0);
  auto saved = plan;
  plan.pop_back();
  rejects(run);
  plan = saved;
  f32(p, 244, 0);
  r = run();
  assert(r.selected == 320 && r.backface_skipped == 0);
  f32(p, 244, 1);
  inst = instance(1e-8f, 1, 1);
  r = run();
  assert(r.selected == 320);
  inst = instance();
  p = params(-5);
  r = run();
  assert(r.selected == 128 && r.backface_skipped == 192);
  // Property: conservative intervals must never reject a front-facing point
  // under rotations, reflected/nonuniform bases and perspective eye positions.
  std::mt19937 rng(2102);
  std::uniform_real_distribution<double> random(-1., 1.);
  uint32_t rejected = 0, tested = 0;
  for (int trial = 0; trial < 2000; trial++) {
    double angle = random(rng) * 3.14, c = std::cos(angle), s = std::sin(angle);
    double sx = (trial % 2 ? -1 : 1) * (.2 + std::abs(random(rng)) * 2),
           sy = .2 + std::abs(random(rng)) * 2,
           sz = .2 + std::abs(random(rng)) * 2;
    inst = Packet(96);
    f32(inst, 0, float(c * sx));
    f32(inst, 8, float(-s * sx));
    f32(inst, 20, float(sy));
    f32(inst, 32, float(s * sz));
    f32(inst, 40, float(c * sz));
    p = params();
    for (int k = 0; k < 3; k++)
      f32(p, k * 4, float(random(rng) * 5));
    std::array<lie::Vec, 64> positions, normals;
    lie::Vec base{random(rng), random(rng), random(rng)};
    plan = cluster(0, {0, 0, 0});
    for (int k = 0; k < 3; k++) {
      f32(plan, 16 + k * 4, std::numeric_limits<float>::infinity());
      f32(plan, 28 + k * 4, -std::numeric_limits<float>::infinity());
      f32(plan, 40 + k * 4, std::numeric_limits<float>::infinity());
      f32(plan, 52 + k * 4, -std::numeric_limits<float>::infinity());
    }
    std::array<float, 12> bounds;
    for (int k = 0; k < 3; k++) {
      bounds[k] = bounds[6 + k] = std::numeric_limits<float>::infinity();
      bounds[3 + k] = bounds[9 + k] = -std::numeric_limits<float>::infinity();
    }
    for (int i = 0; i < 64; i++) {
      for (int k = 0; k < 3; k++) {
        positions[i][k] = float(random(rng) * .1);
        normals[i][k] = base[k] + random(rng) * .01;
      }
      double norm = std::sqrt(lie::dot(normals[i], normals[i]));
      for (int k = 0; k < 3; k++) {
        normals[i][k] = float(normals[i][k] / norm);
        float pos = float(positions[i][k]), n = float(normals[i][k]);
        bounds[k] = std::min(bounds[k], pos);
        bounds[3 + k] = std::max(bounds[3 + k], pos);
        bounds[6 + k] = std::min(bounds[6 + k], n);
        bounds[9 + k] = std::max(bounds[9 + k], n);
      }
    }
    for (int k = 0; k < 12; k++)
      f32(plan, 16 + k * 4, bounds[k]);
    jobs = job(64);
    r = run();
    tested += 64;
    if (r.selected == 0) {
      rejected++;
      lie::Vec eye{bytes(p).f32(0), bytes(p).f32(4), bytes(p).f32(8)};
      auto view = lie::local_view(bytes(inst), 0, eye, true);
      for (int i = 0; i < 64; i++) {
        lie::Vec d;
        for (int k = 0; k < 3; k++)
          d[k] = view.eye[k] - positions[i][k];
        assert(lie::dot(normals[i], d) < 0.);
      }
    }
  }
  assert(rejected > 100);
  std::cout << "VISIBILITY PLANNER PASS " << tested << " sampled points; "
            << rejected << " wholly backfacing clusters\n";
}
