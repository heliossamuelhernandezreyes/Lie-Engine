#pragma once
// Lie Engine - C++17 view-direction scoring reference. No Godot binding yet.
// The compiled unit tests guard indexing math for future GDExtension integration.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <stdexcept>
#include <vector>

namespace lie {
constexpr float pi = 3.14159265358979323846f;
struct Vec3 { float x, y, z; };
struct View {
    int azimuth_index;
    int elevation_index;
    float confidence;
};
inline float dot(Vec3 a, Vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
inline Vec3 normalized(Vec3 a) {
    const float len=std::sqrt(dot(a,a));
    if(len < 1e-7f) throw std::invalid_argument("camera direction cannot be zero");
    return {a.x/len,a.y/len,a.z/len};
}
inline Vec3 direction(int index,int samples,float elevation) {
    if(samples<4) throw std::invalid_argument("invalid angular steps");
    const float az=(2.f*pi*index)/samples,el=elevation*pi/180.f;
    return {std::sin(az)*std::cos(el),std::sin(el),std::cos(az)*std::cos(el)};
}
inline std::vector<View> top_views(Vec3 camera_relative,int count,
                                   const std::vector<float>& elevations,
                                   std::size_t limit=4) {
    if(count<4||elevations.empty()||limit==0) throw std::invalid_argument("invalid grid");
    const Vec3 target=normalized(camera_relative);
    std::vector<View> views;
    for(std::size_t e=0;e<elevations.size();++e) {
        for(int a=0;a<count;++a) {
            const float cosine=std::max(0.f,dot(target,direction(a,count,elevations[e])));
            views.push_back({a,static_cast<int>(e),std::pow(cosine,6.f)});
        }
    }
    std::stable_sort(views.begin(),views.end(),[](const auto& a,const auto& b) {
        return a.confidence>b.confidence;
    });
    views.resize(std::min(limit,views.size()));
    float sum=0.f;
    for(const auto& v:views) sum+=v.confidence;
    if(sum>1e-7f) for(auto& v:views) v.confidence/=sum;
    return views;
}
} // namespace lie
