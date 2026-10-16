// LIE diagnostics. Counter backend: Arm libGPUCounters, MIT; see staged licenses.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <hwcpipe/counter_database.hpp>
#include <hwcpipe/gpu.hpp>
#include <hwcpipe/sampler.hpp>
#include <cerrno>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>
#include "interval_capture.hpp"
using namespace godot;
namespace {
constexpr const char *LIB_SHA="378c7b59e2dae87cbbffb0ac9cf96ed13c939823";
constexpr const char *CPP_SHA="e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77";
uint64_t now_ns(){return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
std::string text_file(const std::filesystem::path &path){std::ifstream in(path);std::string line;if(in)std::getline(in,line);return line;}
bool number_file(const std::filesystem::path &path,int64_t &value){auto s=text_file(path);if(s.empty())return false;char *end=nullptr;errno=0;auto n=std::strtoll(s.c_str(),&end,10);if(errno || end==s.c_str() || *end!='\0')return false;value=n;return true;}
bool gpu_name(std::string s){for(char &c:s)c=static_cast<char>(std::tolower(static_cast<unsigned char>(c)));return s.find("gpu")!=std::string::npos || s.find("mali")!=std::string::npos;}
Dictionary unavailable(const char *reason){Dictionary d;d["available"]=false;d["reason"]=reason;return d;}
Dictionary telemetry_data(){
    Dictionary result;result["host_monotonic_ns"]=String::num_uint64(now_ns());
    Dictionary frequency=unavailable("GPU devfreq frequency is not readable by this app");Array temperatures;
    std::error_code ec;
    const std::filesystem::path devfreq("/sys/class/devfreq");
    for(std::filesystem::directory_iterator it(devfreq,ec),end;!ec && it!=end;it.increment(ec)){
        const auto path=it->path();auto name=path.filename().string()+" "+text_file(path/"name");int64_t value;
        if(gpu_name(name) && number_file(path/"cur_freq",value) && value>0){frequency["available"]=true;frequency.erase("reason");frequency["value"]=value;frequency["unit"]="Hz (Linux devfreq ABI)";frequency["source"]=String((path/"cur_freq").c_str());break;}
    }
    ec.clear();const std::filesystem::path thermal("/sys/class/thermal");
    for(std::filesystem::directory_iterator it(thermal,ec),end;!ec && it!=end;it.increment(ec)){
        const auto path=it->path();auto type=text_file(path/"type");int64_t value;
        if(gpu_name(type) && number_file(path/"temp",value)){Dictionary row;row["sensor_type"]=String(type.c_str());row["value"]=value;row["unit"]="millidegrees Celsius (Linux thermal ABI)";row["source"]=String((path/"temp").c_str());temperatures.append(row);}
    }
    result["gpu_frequency"]=frequency;Dictionary temp;temp["available"]=!temperatures.is_empty();temp["sensors"]=temperatures;if(temperatures.is_empty())temp["reason"]="No readable thermal zone explicitly named GPU/Mali";result["gpu_temperature"]=temp;
    Dictionary policy=unavailable("Android thermal status API is not available on this platform");
#ifdef __ANDROID__
    // Resolve API-30 symbols at runtime; retain APK compatibility below API 30.
    void *library=dlopen("libandroid.so",RTLD_NOW|RTLD_LOCAL);
    if(library){
        auto acquire=reinterpret_cast<void*(*)()>(dlsym(library,"AThermal_acquireManager"));
        auto release=reinterpret_cast<void(*)(void*)>(dlsym(library,"AThermal_releaseManager"));
        auto status=reinterpret_cast<int(*)(void*)>(dlsym(library,"AThermal_getCurrentThermalStatus"));
        if(acquire && release && status){void *manager=acquire();if(manager){int value=status(manager);release(manager);if(value>=0 && value<=6){policy["available"]=true;policy.erase("reason");policy["value"]=value;policy["source"]="Android AThermal_getCurrentThermalStatus";policy["scope"]="device thermal policy, not GPU temperature";}}}
        dlclose(library);
    }
#endif
    result["thermal_status"]=policy;return result;
}
}
class LieGPUProbe: public RefCounted {
    GDCLASS(LieGPUProbe,RefCounted)
    std::unique_ptr<hwcpipe::sampler<>> sampler;
    IntervalCapture<hwcpipe::sampler<>> capture;
    std::vector<hwcpipe_counter> counters;
    Dictionary state;
    uint64_t start_ns=0;
    uint64_t session_id=0;
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("probe"),&LieGPUProbe::probe);
        ClassDB::bind_method(D_METHOD("begin"),&LieGPUProbe::begin);
        ClassDB::bind_method(D_METHOD("end"),&LieGPUProbe::end);
        ClassDB::bind_method(D_METHOD("release_counters"),&LieGPUProbe::release_counters);
        ClassDB::bind_method(D_METHOD("telemetry"),&LieGPUProbe::telemetry);
    }
public:
    ~LieGPUProbe(){release_counters();}
    Dictionary telemetry(){return telemetry_data();}
    Dictionary probe(){
        release_counters();state=unavailable("not_probed");state["native_extension"]=true;state["libGPUCounters_sha"]=LIB_SHA;state["godot_cpp_sha"]=CPP_SHA;state["device_node"]="/dev/mali0";state["scope"]="whole-device counters, not exclusive to this process or a GPU pass";
        struct stat info{};
        if(stat("/dev/mali0",&info)!=0){state["reason"]="Mali device node unavailable";state["os_error"]=String(std::strerror(errno));return state.duplicate(true);}
        // kbase handles in the pinned backend open O_RDONLY; do not demand
        // write permission that the actual sampler does not require.
        if(access("/dev/mali0",R_OK)!=0){state["reason"]="Mali device node read access denied";state["os_error"]=String(std::strerror(errno));return state.duplicate(true);}
        hwcpipe::gpu gpu(0);if(!gpu){state["reason"]="Driver/GPU probe failed; permissions or unsupported driver/product may prevent access";return state.duplicate(true);}
        state["shader_cores"]=static_cast<int64_t>(gpu.num_shader_cores());state["bus_width_bits"]=static_cast<int64_t>(gpu.bus_width());
        hwcpipe::sampler_config config(gpu);Array supported,unsupported;
        const hwcpipe_counter selected[]={MaliGPUActiveCy,MaliAnyActiveCy,MaliALUUtil,MaliLSUtil,MaliLSAtomic,MaliExtBusRdBy,MaliExtBusWrBy,MaliExtBusRdStallRate,MaliExtBusWrStallRate,MaliSCBusLSExtRdBy,MaliSCBusLSL2RdBy,MaliEngDivergedInstrRate,MaliCoreAllRegsWarpRate,MaliCompQueueUtil,MaliMainQueueUtil,MaliBinningQueueUtil,MaliCSFMCUUtil};
        hwcpipe::counter_database db;for(auto counter:selected){hwcpipe::counter_metadata meta{};auto described=db.describe_counter(counter,meta);if(described)continue;auto error=config.add_counter(counter);if(error){unsupported.append(String(meta.name));continue;}counters.push_back(counter);Dictionary row;row["id"]=static_cast<int64_t>(counter);row["name"]=meta.name;row["unit"]=meta.units;supported.append(row);}
        state["supported"]=supported;state["unsupported"]=unsupported;
        if(counters.empty()){state["reason"]="No requested counters supported";return state.duplicate(true);}
        sampler=std::make_unique<hwcpipe::sampler<>>(config);
        if(!*sampler){auto error=sampler->start_sampling();state["reason"]=String(error.message().c_str());sampler.reset();return state.duplicate(true);}
        state["available"]=true;state.erase("reason");return state.duplicate(true);
    }
    Dictionary begin(){
        if(capture.active())return unavailable("sampling_already_started");
        // probe() creates a new handle/reader. A prior stop() leaves a final
        // dump in its own queue, so reusing that sampler mislabels later data.
        probe();if(!sampler)return state.duplicate(true);
        auto error=capture.begin(std::move(sampler));
        if(error){state["available"]=false;state["reason"]=String(error.message().c_str());return state.duplicate(true);}
        ++session_id;start_ns=now_ns();Dictionary result;result["available"]=true;result["session_id"]=String::num_uint64(session_id);result["host_start_ns"]=String::num_uint64(start_ns);result["fresh_reader"]=true;return result;
    }
    Dictionary end(){
        if(!capture.active())return unavailable("sampling_not_started");
        auto error=capture.sample();const auto finish=now_ns();Dictionary result;result["available"]=!error;result["session_id"]=String::num_uint64(session_id);result["fresh_reader"]=true;result["host_start_ns"]=String::num_uint64(start_ns);result["host_end_ns"]=String::num_uint64(finish);result["wall_ms"]=double(finish-start_ns)/1e6;Dictionary values;
        if(error)result["reason"]=String(error.message().c_str());
        else {
            hwcpipe::counter_database db;
            for(auto counter:counters){hwcpipe::counter_sample sample;auto read=capture.get()->get_counter_value(counter,sample);hwcpipe::counter_metadata meta{};auto described=db.describe_counter(counter,meta);if(described)continue;Dictionary row;row["unit"]=meta.units;row["available"]=!read;
                if(read)row["reason"]=String(read.message().c_str());
                else {row["timestamp_ns"]=String::num_uint64(sample.timestamp);if(sample.type==hwcpipe::counter_sample::type::uint64){row["kind"]="uint64_decimal";row["value"]=String::num_uint64(sample.value.uint64);}else if(std::isfinite(sample.value.float64)){row["kind"]="float64";row["value"]=sample.value.float64;}else{row["available"]=false;row["reason"]="nonfinite derived value; possibly no activity";}}
                values[meta.name]=row;
            }
        }
        auto stopped=capture.close();if(stopped){result["available"]=false;result["stop_error"]=String(stopped.message().c_str());}
        result["counters"]=values;result["scope"]="Fresh HWCPipe reader per interval; own baseline discarded and final stop dump destroyed with its reader. Whole-device data includes other apps and presentation; not per-dispatch. Kernel clock is not calibrated to Godot GPU timestamps.";return result;
    }
    void release_counters(){auto ignored=capture.close();(void)ignored;sampler.reset();counters.clear();}
};
void initialize_probe(ModuleInitializationLevel level){if(level==MODULE_INITIALIZATION_LEVEL_SCENE)GDREGISTER_CLASS(LieGPUProbe);}
void terminate_probe(ModuleInitializationLevel){}
extern "C" GDExtensionBool GDE_EXPORT lie_gpu_probe_init(GDExtensionInterfaceGetProcAddress get_proc,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization){GDExtensionBinding::InitObject init(get_proc,library,initialization);init.register_initializer(initialize_probe);init.register_terminator(terminate_probe);init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);return init.init();}
