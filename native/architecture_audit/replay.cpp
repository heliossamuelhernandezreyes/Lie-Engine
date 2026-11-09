// Diagnostic replay of the EXACT Godot SPIR-V and SSBO inputs, without Godot.
// This is a compute-kernel control experiment, not a complete game renderer.
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <vulkan/vulkan.h>
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
static void ok(VkResult r, const char *op) {
  if (r != VK_SUCCESS)
    throw std::runtime_error(std::string(op) + ": " + std::to_string(r));
}
static std::vector<uint8_t> read(const fs::path &p) {
  std::ifstream f(p, std::ios::binary | std::ios::ate);
  if (!f)
    throw std::runtime_error("open " + p.string());
  auto n = f.tellg();
  if (n < 0)
    throw std::runtime_error("size");
  std::vector<uint8_t> b(static_cast<size_t>(n));
  f.seekg(0);
  if (!b.empty() && !f.read(reinterpret_cast<char *>(b.data()), n))
    throw std::runtime_error("read");
  return b;
}
static std::string quoted(const std::string &s) {
  std::ostringstream o;
  o << '"';
  for (unsigned char c : s) {
    if (c == '"' || c == '\\')
      o << '\\';
    if (c >= 32)
      o << c;
  }
  return o.str() + '"';
}
struct Buffer {
  VkBuffer handle = VK_NULL_HANDLE;
  VkDeviceMemory memory = VK_NULL_HANDLE;
  void *map = nullptr;
  VkDeviceSize size = 0;
};
struct Context {
  VkInstance instance = VK_NULL_HANDLE;
  VkPhysicalDevice physical = VK_NULL_HANDLE;
  VkDevice device = VK_NULL_HANDLE;
  VkQueue queue = VK_NULL_HANDLE;
  VkPhysicalDeviceProperties props{};
  VkPhysicalDeviceMemoryProperties memory{};
  uint32_t family = 0, valid_bits = 0;
  VkDescriptorSetLayout set_layout = VK_NULL_HANDLE;
  VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
  VkDescriptorPool descriptor_pool = VK_NULL_HANDLE;
  VkCommandPool command_pool = VK_NULL_HANDLE;
  VkCommandBuffer command = VK_NULL_HANDLE;
  VkFence fence = VK_NULL_HANDLE;
  VkQueryPool queries = VK_NULL_HANDLE;
  std::vector<Buffer> buffers;
  std::map<int, VkPipeline> pipelines;
  ~Context() {
    if (device) {
      vkDeviceWaitIdle(device);
      for (auto &p : pipelines)
        vkDestroyPipeline(device, p.second, nullptr);
      if (queries)
        vkDestroyQueryPool(device, queries, nullptr);
      if (fence)
        vkDestroyFence(device, fence, nullptr);
      if (command_pool)
        vkDestroyCommandPool(device, command_pool, nullptr);
      if (descriptor_pool)
        vkDestroyDescriptorPool(device, descriptor_pool, nullptr);
      if (pipeline_layout)
        vkDestroyPipelineLayout(device, pipeline_layout, nullptr);
      if (set_layout)
        vkDestroyDescriptorSetLayout(device, set_layout, nullptr);
      for (auto &b : buffers) {
        if (b.map)
          vkUnmapMemory(device, b.memory);
        if (b.handle)
          vkDestroyBuffer(device, b.handle, nullptr);
        if (b.memory)
          vkFreeMemory(device, b.memory, nullptr);
      }
      vkDestroyDevice(device, nullptr);
    }
    if (instance)
      vkDestroyInstance(instance, nullptr);
  }
  void init() {
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "LIE exact compute replay";
    app.apiVersion = VK_API_VERSION_1_2;
    VkInstanceCreateInfo ci{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ci.pApplicationInfo = &app;
    ok(vkCreateInstance(&ci, nullptr, &instance), "instance");
    uint32_t count = 0;
    ok(vkEnumeratePhysicalDevices(instance, &count, nullptr), "devices");
    if (!count)
      throw std::runtime_error("no Vulkan device");
    std::vector<VkPhysicalDevice> all(count);
    ok(vkEnumeratePhysicalDevices(instance, &count, all.data()), "devices");
    bool found = false;
    for (auto p : all) {
      uint32_t n = 0;
      vkGetPhysicalDeviceQueueFamilyProperties(p, &n, nullptr);
      std::vector<VkQueueFamilyProperties> q(n);
      vkGetPhysicalDeviceQueueFamilyProperties(p, &n, q.data());
      for (uint32_t i = 0; i < n; i++)
        if ((q[i].queueFlags & VK_QUEUE_COMPUTE_BIT) &&
            q[i].timestampValidBits) {
          physical = p;
          family = i;
          valid_bits = q[i].timestampValidBits;
          found = true;
          break;
        }
      if (found)
        break;
    }
    if (!found)
      throw std::runtime_error("compute timestamps unavailable");
    vkGetPhysicalDeviceProperties(physical, &props);
    vkGetPhysicalDeviceMemoryProperties(physical, &memory);
    if (props.limits.maxPerStageDescriptorStorageBuffers < 12 ||
        props.limits.maxDescriptorSetStorageBuffers < 12)
      throw std::runtime_error("twelve storage bindings unavailable");
    float priority = 1;
    VkDeviceQueueCreateInfo qc{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qc.queueFamilyIndex = family;
    qc.queueCount = 1;
    qc.pQueuePriorities = &priority;
    VkDeviceCreateInfo dc{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dc.queueCreateInfoCount = 1;
    dc.pQueueCreateInfos = &qc;
    ok(vkCreateDevice(physical, &dc, nullptr, &device), "device");
    vkGetDeviceQueue(device, family, 0, &queue);
    const std::array<uint32_t, 12> bindings = {0, 1, 2,  3,  4,  5,
                                               6, 7, 13, 14, 15, 20};
    std::array<VkDescriptorSetLayoutBinding, 12> layout{};
    for (size_t i = 0; i < bindings.size(); i++)
      layout[i] = {bindings[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1,
                   VK_SHADER_STAGE_COMPUTE_BIT, nullptr};
    VkDescriptorSetLayoutCreateInfo lc{
        VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    lc.bindingCount = layout.size();
    lc.pBindings = layout.data();
    ok(vkCreateDescriptorSetLayout(device, &lc, nullptr, &set_layout),
       "descriptor layout");
    VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, 16};
    VkPipelineLayoutCreateInfo pc{
        VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    pc.setLayoutCount = 1;
    pc.pSetLayouts = &set_layout;
    pc.pushConstantRangeCount = 1;
    pc.pPushConstantRanges = &range;
    ok(vkCreatePipelineLayout(device, &pc, nullptr, &pipeline_layout),
       "pipeline layout");
    VkDescriptorPoolSize ps{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1024};
    VkDescriptorPoolCreateInfo pool{
        VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pool.maxSets = 64;
    pool.poolSizeCount = 1;
    pool.pPoolSizes = &ps;
    ok(vkCreateDescriptorPool(device, &pool, nullptr, &descriptor_pool),
       "descriptor pool");
    VkCommandPoolCreateInfo cc{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    cc.queueFamilyIndex = family;
    cc.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    ok(vkCreateCommandPool(device, &cc, nullptr, &command_pool),
       "command pool");
    VkCommandBufferAllocateInfo ca{
        VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    ca.commandPool = command_pool;
    ca.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    ca.commandBufferCount = 1;
    ok(vkAllocateCommandBuffers(device, &ca, &command), "command");
    VkFenceCreateInfo fc{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    ok(vkCreateFence(device, &fc, nullptr, &fence), "fence");
    VkQueryPoolCreateInfo query{VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO};
    query.queryType = VK_QUERY_TYPE_TIMESTAMP;
    query.queryCount = 6;
    ok(vkCreateQueryPool(device, &query, nullptr, &queries), "timestamps");
  }
  size_t buffer(VkDeviceSize size, const std::vector<uint8_t> &initial = {}) {
    if (!size || size > props.limits.maxStorageBufferRange ||
        initial.size() > size)
      throw std::runtime_error("storage buffer range");
    Buffer b;
    b.size = size;
    VkBufferCreateInfo ci{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    ci.size = size;
    ci.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
    ci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    ok(vkCreateBuffer(device, &ci, nullptr, &b.handle), "buffer");
    VkMemoryRequirements req{};
    vkGetBufferMemoryRequirements(device, b.handle, &req);
    uint32_t type = UINT32_MAX;
    for (uint32_t i = 0; i < memory.memoryTypeCount; i++)
      if ((req.memoryTypeBits & (1u << i)) &&
          ((memory.memoryTypes[i].propertyFlags &
            (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
             VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) ==
           (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
            VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))) {
        type = i;
        break;
      }
    if (type == UINT32_MAX)
      throw std::runtime_error("host coherent memory unavailable");
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = type;
    ok(vkAllocateMemory(device, &ai, nullptr, &b.memory), "memory");
    ok(vkBindBufferMemory(device, b.handle, b.memory, 0), "bind buffer");
    ok(vkMapMemory(device, b.memory, 0, size, 0, &b.map), "map");
    std::memset(b.map, 0, size);
    if (!initial.empty())
      std::memcpy(b.map, initial.data(), initial.size());
    buffers.push_back(b);
    return buffers.size() - 1;
  }
  size_t input(const fs::path &file) {
    auto b = read(file);
    return buffer(b.size(), b);
  }
  VkDescriptorSet descriptors(const std::map<int, size_t> &map) {
    VkDescriptorSet set;
    VkDescriptorSetAllocateInfo ai{
        VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    ai.descriptorPool = descriptor_pool;
    ai.descriptorSetCount = 1;
    ai.pSetLayouts = &set_layout;
    ok(vkAllocateDescriptorSets(device, &ai, &set), "descriptor set");
    std::vector<VkDescriptorBufferInfo> infos;
    std::vector<VkWriteDescriptorSet> writes;
    infos.reserve(map.size());
    writes.reserve(map.size());
    for (auto [binding, index] : map) {
      const auto &b = buffers.at(index);
      infos.push_back({b.handle, 0, b.size});
      VkWriteDescriptorSet w{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
      w.dstSet = set;
      w.dstBinding = binding;
      w.descriptorCount = 1;
      w.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
      w.pBufferInfo = &infos.back();
      writes.push_back(w);
    }
    vkUpdateDescriptorSets(device, writes.size(), writes.data(), 0, nullptr);
    return set;
  }
  void shader(int stage, const fs::path &path) {
    auto bytes = read(path);
    if (bytes.empty() || bytes.size() % 4)
      throw std::runtime_error("SPIR-V size");
    std::vector<uint32_t> code(bytes.size() / 4);
    std::memcpy(code.data(), bytes.data(), bytes.size());
    VkShaderModuleCreateInfo sc{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    sc.codeSize = bytes.size();
    sc.pCode = code.data();
    VkShaderModule module;
    ok(vkCreateShaderModule(device, &sc, nullptr, &module), "SPIR-V");
    VkComputePipelineCreateInfo pc{
        VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    pc.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pc.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pc.stage.module = module;
    pc.stage.pName = "main";
    pc.layout = pipeline_layout;
    auto result = vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pc,
                                           nullptr, &pipelines[stage]);
    vkDestroyShaderModule(device, module, nullptr);
    ok(result, "pipeline");
  }
  void barrier() {
    VkMemoryBarrier b{VK_STRUCTURE_TYPE_MEMORY_BARRIER};
    b.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    b.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &b, 0,
                         nullptr, 0, nullptr);
  }
  void dispatch(int stage, VkDescriptorSet set, uint32_t count) {
    if (!count)
      return;
    const int32_t phase[4] = {stage, 2, 1, 0};
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE,
                      pipelines.at(stage));
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE,
                            pipeline_layout, 0, 1, &set, 0, nullptr);
    vkCmdPushConstants(command, pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0,
                       16, phase);
    uint32_t groups = (count + 63) / 64, x = std::min(groups, 32768u),
             y = (groups + x - 1) / x;
    vkCmdDispatch(command, x, y, 1);
    barrier();
  }
  void dispatch_large(int stage, VkDescriptorSet set, size_t queue_buffer,
                      VkDeviceSize queue_offset) {
    const int32_t phase[4] = {stage, 2, 1, 0};
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE,pipelines.at(stage));
    vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_COMPUTE,pipeline_layout,
                           0,1,&set,0,nullptr);
    vkCmdPushConstants(command,pipeline_layout,VK_SHADER_STAGE_COMPUTE_BIT,0,16,phase);
    vkCmdDispatchIndirect(command,buffers.at(queue_buffer).handle,queue_offset);
    barrier();
  }
  void output(size_t index, const fs::path &path) {
    const auto &b = buffers.at(index);
    std::ofstream f(path, std::ios::binary);
    if (!f.write(static_cast<const char *>(b.map), b.size))
      throw std::runtime_error("output");
  }
};
struct Bank {
  uint32_t work = 0;
  VkDescriptorSet set = VK_NULL_HANDLE;
  size_t queue_buffer = 0;
  VkDeviceSize queue_offset = 0;
};
int main(int argc, char **argv) {
  try {
    if (argc != 2 && argc != 4)
      throw std::runtime_error(
          "usage: replay FIXTURE_DIRECTORY [SHADERS OUTPUT_PREFIX]");
    fs::path root = argv[1];
    fs::path shaders = argc == 4 ? fs::path(argv[2]) : root;
    std::string prefix = argc == 4 ? argv[3] : "native";
    if (prefix != "native" && prefix != "candidate-hoist" &&
        prefix != "candidate-cache")
      throw std::runtime_error("unsupported output prefix");
    std::ifstream layout(root / "layout.txt");
    uint32_t size = 0, capacity = 0, n = 0;
    if (!(layout >> size >> capacity >> n) || size < 1 || size > 2048 ||
        !capacity || !n || n > 16)
      throw std::runtime_error("fixture layout");
    Context c;
    c.init();
    bool surface = fs::exists(root / "surface-pipeline.txt");
    uint32_t stride = 80;
    if (fs::exists(root / "projection-stride.txt")) {
      std::ifstream stride_file(root / "projection-stride.txt");
      if (!(stride_file >> stride) || (stride != 64 && stride != 80))
        throw std::runtime_error("projection stride");
    }
    std::map<int, size_t> common;
    for (int binding : {1, 2, 6})
      common[binding] =
          c.input(root / ("common-" + std::to_string(binding) + ".bin"));
    common[3] = c.buffer(uint64_t(capacity) * stride);
    common[4] = c.buffer(uint64_t(size) * size * 4);
    common[5] = c.buffer(uint64_t(size) * size * 4);
    common[7] = c.buffer(uint64_t(size) * size * 32);
    common[13] = c.buffer(512 * 512 * 4);
    auto dummy = c.buffer(80);
    for (int binding : {0, 14, 15, 20})
      common[binding] = dummy;
    auto clear = c.descriptors(common);
    std::vector<Bank> banks;
    for (uint32_t i = 0; i < n; i++) {
      uint32_t id = 0, work = 0;
      if (!(layout >> id >> work) || id > 15 || work < 1)
        throw std::runtime_error("bank");
      auto bindings = common;
      for (int binding : {0, 6, 14, 15, 20})
        bindings[binding] = c.input(root / ("bank-" + std::to_string(id) + "-" +
                                            std::to_string(binding) + ".bin"));
      float header = 0;
      std::memcpy(&header,static_cast<const uint8_t *>(c.buffers[bindings[6]].map)+212,4);
      auto offset=VkDeviceSize(header)*16;
      if(surface && (offset+32+uint64_t(work)*8>c.buffers[bindings[20]].size))
        throw std::runtime_error("surface queue capacity");
      banks.push_back({work,c.descriptors(bindings),bindings[20],offset});
    }
    std::vector<int> stages = surface ? std::vector<int>{1,2,9,3,10,12,11}
                                      : std::vector<int>{1,2,3};
    for (int stage : stages)
      c.shader(stage, shaders / ("stage-" + std::to_string(stage) + ".spv"));
    std::ostringstream report;
    report << std::setprecision(12)
           << "{\"schema\":\"lie-native-compute-replay/1\",\"device\":"
           << quoted(c.props.deviceName) << ",\"variant\":" << quoted(prefix)
           << ",\"api_version\":" << c.props.apiVersion
           << ",\"driver_version\":" << c.props.driverVersion
           << ",\"projection_stride\":" << stride
           << ",\"timestamp_valid_bits\":" << c.valid_bits
           << ",\"max_storage_buffer_range\":"
           << c.props.limits.maxStorageBufferRange
           << ",\"max_storage_buffers_per_stage\":"
           << c.props.limits.maxPerStageDescriptorStorageBuffers
           << ",\"host_visible_coherent_buffers\":true,\"physical_android_"
              "tested\":false,\"surface_pipeline\":" << (surface?"true":"false")
           << ",\"rows\":[";
    std::map<int,std::vector<uint8_t>> stable;
    for (int iteration = 0; iteration < 6; iteration++) {
      // Coherent host writes occur only after the previous diagnostic fence.
      if(surface)for(const auto &bank:banks) {
        auto *p=static_cast<uint32_t *>(c.buffers[bank.queue_buffer].map)+bank.queue_offset/4;
        const uint32_t header[8]={0,1,1,0,0,0,0,0};std::memcpy(p,header,sizeof(header));
      }
      ok(vkResetCommandBuffer(c.command, 0), "reset command");
      ok(vkResetFences(c.device, 1, &c.fence), "reset fence");
      auto begin = Clock::now();
      VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
      bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
      ok(vkBeginCommandBuffer(c.command, &bi), "begin");
      vkCmdResetQueryPool(c.command, c.queries, 0, 6);
      uint32_t q = 0;
      for (int stage : stages) {
        if(!surface)vkCmdWriteTimestamp(c.command,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,c.queries,q++);
        if (stage == 1)
          c.dispatch(stage, clear, std::max(size * size, 512u * 512u));
        else if (iteration % 2 == 0) {
          for (auto it = banks.rbegin(); it != banks.rend(); ++it)
            if(stage==9 || stage==10 || stage==11)c.dispatch_large(stage,it->set,it->queue_buffer,it->queue_offset);
            else c.dispatch(stage, it->set, it->work);
        } else
          for (const auto &bank : banks) {
            if(stage==9 || stage==10 || stage==11)c.dispatch_large(stage,bank.set,bank.queue_buffer,bank.queue_offset);
            else c.dispatch(stage, bank.set, bank.work);
          }
        if(!surface)vkCmdWriteTimestamp(c.command,VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,c.queries,q++);
      }
      VkMemoryBarrier host{VK_STRUCTURE_TYPE_MEMORY_BARRIER};
      host.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
      host.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
      vkCmdPipelineBarrier(c.command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                           VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &host, 0, nullptr,
                           0, nullptr);
      ok(vkEndCommandBuffer(c.command), "end");
      double record =
          std::chrono::duration<double, std::milli>(Clock::now() - begin)
              .count();
      VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO};
      si.commandBufferCount = 1;
      si.pCommandBuffers = &c.command;
      auto submit_begin = Clock::now();
      ok(vkQueueSubmit(c.queue, 1, &si, c.fence), "submit");
      ok(vkWaitForFences(c.device, 1, &c.fence, VK_TRUE, 120000000000ull),
         "wait");
      double wall =
          std::chrono::duration<double, std::milli>(Clock::now() - submit_begin)
              .count();
      uint64_t t[6]{};
      if(!surface)ok(vkGetQueryPoolResults(
             c.device, c.queries, 0, 6, sizeof(t), t, sizeof(uint64_t),
             VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT),
         "timestamps");
      uint64_t mask =
          c.valid_bits == 64 ? UINT64_MAX : ((uint64_t(1) << c.valid_bits) - 1);
      auto ms = [&](int i) {
        if(surface)return 0.; // New-path correctness replay does not fabricate pass timings.
        return double((t[2 * i + 1] - t[2 * i]) & mask) *
               c.props.limits.timestampPeriod / 1e6;
      };
      if (iteration)
        report << ',';
      report << "{\"iteration\":" << iteration
             << ",\"warm_up\":" << (iteration == 0 ? "true" : "false")
             << ",\"record_cpu_ms\":" << record
             << ",\"submit_and_wait_ms\":" << wall;
      if(!surface)report << ",\"clear_ms\":" << ms(0) << ",\"projection_depth_ms\":" << ms(1)
                         << ",\"material_accumulation_ms\":" << ms(2);
      else report << ",\"pass_timestamps_available\":false";
      report << '}';
      for(int binding:{4,5,7}) {
        const auto &b=c.buffers[common.at(binding)];auto *p=static_cast<const uint8_t *>(b.map);
        if(iteration==0)stable[binding]=std::vector<uint8_t>(p,p+b.size);
        else if(std::memcmp(p,stable[binding].data(),b.size)!=0)
          throw std::runtime_error("bank-order output instability at binding "+std::to_string(binding));
      }
    }
    report << "],\"scope\":\"Selected SPIR-V and exact captured SSBO inputs; "
           << (surface ? "clear plus split small/cooperative-large depth, owner and material passes. "
                       : "clear, projection/depth and material accumulation. ")
           << "No Godot, window, "
              "physics, light field, shading or presentation. CPU buffer "
              "layout is an experimental replay path. Timings apply only to "
              "this device.\"}\n";
    for (int binding : {4, 5, 7})
      c.output(common.at(binding),
               root / (prefix + "-" + std::to_string(binding) + ".bin"));
    if(surface) {
      for(size_t i=0;i<banks.size();i++) {
        const auto &bank=banks[i];const auto &b=c.buffers[bank.queue_buffer];
        auto *p=static_cast<const uint8_t *>(b.map)+bank.queue_offset;
        std::ofstream out(root/(prefix+"-queue-"+std::to_string(i)+".bin"),std::ios::binary);
        out.write(reinterpret_cast<const char *>(p),32);
      }
    }
    std::ofstream file(root / (prefix + "-replay.json"));
    file << report.str();
    std::cout << report.str();
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "LIE REPLAY ERROR: " << e.what() << '\n';
    return 1;
  }
}
