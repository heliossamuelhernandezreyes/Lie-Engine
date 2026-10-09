#include "lie_view_math.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
int main() {
  const auto exact=lie::top_views({0,0,1},16,{-30.f,0.f,30.f},4);
  assert(exact.size()==4 && exact[0].azimuth_index==0 && exact[0].elevation_index==1);
  const auto wrap=lie::top_views({-0.01f,0.f,1},16,{0.f},4);
  assert(wrap[0].azimuth_index==0 && wrap[1].azimuth_index==15);
  const auto quarter=lie::top_views({1,0,1},16,{0.f},4);
  assert(quarter[0].azimuth_index==2 && quarter[1].azimuth_index==1);
  float sum=0.f;
  for(const auto& v:quarter) { assert(v.confidence>=0.f); sum+=v.confidence; }
  assert(std::fabs(sum-1.f)<1e-5f);
  bool rejected=false;
  try { lie::top_views({0,0,0},16,{0.f}); } catch (const std::invalid_argument&) { rejected=true; }
  assert(rejected);
  std::cout<<"LIE-06 C++ VIEW PASS selected=4 wrap=stable weights=normalized\n";
}
