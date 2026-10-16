#pragma once
#include <memory>
#include <system_error>
#include <utility>

// A stopped HWCPipe sampler queues a final sample. Never carry that reader
// into another interval: each begin consumes a new sampler; close destroys it.
template <class Sampler> class IntervalCapture {
    std::unique_ptr<Sampler> sampler_;
    bool active_=false;
public:
    ~IntervalCapture(){close();}
    bool active() const{return active_;}
    Sampler *get() const{return sampler_.get();}
    std::error_code begin(std::unique_ptr<Sampler> fresh){
        if(active_)return std::make_error_code(std::errc::operation_in_progress);
        sampler_=std::move(fresh);
        if(!sampler_)return std::make_error_code(std::errc::no_such_device);
        auto error=sampler_->start_sampling();
        if(error){sampler_.reset();return error;}
        active_=true;
        error=sampler_->sample_now(); // discard only this reader's baseline
        if(error){close();return error;}
        return {};
    }
    std::error_code sample(){
        if(!active_ || !sampler_)return std::make_error_code(std::errc::operation_not_permitted);
        return sampler_->sample_now();
    }
    std::error_code close(){
        std::error_code error;
        if(active_ && sampler_)error=sampler_->stop_sampling();
        active_=false;sampler_.reset(); // discard stop dump even on failure
        return error;
    }
};
