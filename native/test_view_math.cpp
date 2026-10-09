#include "lie_view_math.hpp"
#include <cmath>
#include <iostream>
#include <stdexcept>

static void check(bool condition, const char* text) {
    if(!condition) throw std::runtime_error(text);
}

int main() {
  try {
    const auto exact=lie::top_views({0,0,1},16,{-30.f,0.f,30.f},4);
    check(exact.size()==4,"Four angular samples were not returned");
    check(exact[0].azimuth_index==0&&exact[0].elevation_index==1,"Front angular indexing failed");
    const auto wrap=lie::top_views({-0.01f,0.f,1},16,{0.f},4);
    check(wrap[0].azimuth_index==0&&wrap[1].azimuth_index==15,"360-degree wrap failed");
    const auto quarter=lie::top_views({1,0,1},16,{0.f},4);
    check(quarter[0].azimuth_index==2&&quarter[1].azimuth_index==1,"45-degree ordering failed");
    float sum=0.f;
    for(const auto& v:quarter) {
      check(v.confidence>=0.f,"Negative view confidence");
      sum+=v.confidence;
    }
    check(std::fabs(sum-1.f)<1e-5f,"Normalized weights do not sum to 1");
    bool rejected=false;
    try { lie::top_views({0,0,0},16,{0.f}); }
    catch(const std::invalid_argument&) { rejected=true; }
    check(rejected,"Zero direction accepted");
    std::cout<<"LIE-06 C++ VIEW PASS selected=4 wrap=stable weights=normalized\n";
    return 0;
  } catch(const std::exception& e) {
    std::cerr<<"LIE-06 C++ VIEW FAIL: "<<e.what()<<"\n";
    return 1;
  }
}
