#include "interval_capture.hpp"
#include <deque>
#include <iostream>
#include <vector>
#include <stdexcept>
// CPU FIFO fixture implementing the pinned backend's documented stop dump.
// This is an interval ownership regression, not emulated GPU measurements.
struct QueueSampler {
    static int live;
    std::deque<int> queued;
    int accumulated=0,value=-1;
    bool running=false,fail_start=false,fail_sample=false,fail_stop=false;
    QueueSampler(){++live;}
    ~QueueSampler(){--live;}
    std::error_code start_sampling(){if(fail_start)return std::make_error_code(std::errc::io_error);running=true;accumulated=0;return {};}
    std::error_code sample_now(){
        if(fail_sample)return std::make_error_code(std::errc::io_error);
        queued.push_back(accumulated);accumulated=0;value=queued.front();queued.pop_front();return {};
    }
    std::error_code stop_sampling(){queued.push_back(accumulated);accumulated=0;running=false;return fail_stop?std::make_error_code(std::errc::io_error):std::error_code{};}
};
int QueueSampler::live=0;
int main(){
    int checks=0;auto check=[&](bool value,const char *label){++checks;if(!value)throw std::runtime_error(label);};
    // Control: the old start/baseline/work/end/stop reuse shifts intervals.
    std::vector<int> old;
    {
        QueueSampler sampler;
        for(int work=1;work<=6;++work){sampler.start_sampling();sampler.sample_now();sampler.accumulated=work;sampler.sample_now();old.push_back(sampler.value);sampler.stop_sampling();}
    }
    check(old==std::vector<int>({1,0,0,3,0,0}),"old lifecycle must reproduce delayed camera/zero/zero pattern");
    IntervalCapture<QueueSampler> capture;
    for(int work=1;work<=6;++work){
        check(!capture.begin(std::make_unique<QueueSampler>()),"fresh begin");
        check(capture.active() && QueueSampler::live==1,"exactly one live reader");
        capture.get()->accumulated=work;
        check(!capture.sample() && capture.get()->value==work,"current interval, no earlier dump");
        check(!capture.close() && !capture.active() && QueueSampler::live==0,"stop reader is destroyed");
    }
    check(!capture.close() && bool(capture.sample()),"idle lifecycle explicit");
    auto bad=std::make_unique<QueueSampler>();bad->fail_start=true;
    check(bool(capture.begin(std::move(bad))) && !capture.active() && QueueSampler::live==0,"start failure releases reader");
    bad=std::make_unique<QueueSampler>();bad->fail_sample=true;
    check(bool(capture.begin(std::move(bad))) && !capture.active() && QueueSampler::live==0,"baseline failure stops and destroys reader");
    check(!capture.begin(std::make_unique<QueueSampler>()),"restart after failure");
    const auto nested=capture.begin(std::make_unique<QueueSampler>());
    check(bool(nested) && QueueSampler::live==1,"nested begin rejected without replacing active reader");
    capture.get()->fail_stop=true;check(bool(capture.close()) && QueueSampler::live==0,"stop failure cannot retain queued samples");
    {IntervalCapture<QueueSampler> abandoned;check(!abandoned.begin(std::make_unique<QueueSampler>()),"destructor fixture starts");}
    check(QueueSampler::live==0,"destruction closes active capture");
    std::cout<<"INTERVAL CAPTURE "<<checks<<" PASS\n";
}
