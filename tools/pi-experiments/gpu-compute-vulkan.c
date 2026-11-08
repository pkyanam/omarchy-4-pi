#define _POSIX_C_SOURCE 200809L
#include <vulkan/vulkan.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Source candidate: parent execution only. No WSI, extensions, or optional features.
 * Every successful submission is fenced before reuse/destruction. On a timeout,
 * leave pending resources to process teardown, never destroy an in-use object. */
#define MAX_PIXELS (257u * 193u)
#define GUARD 64u
#define BYTES ((MAX_PIXELS + GUARD) * sizeof(uint32_t))
#define CHECK(call) do { VkResult r_ = (call); if (r_ != VK_SUCCESS) { \
  fprintf(stderr, "error=%s result=%d\n", #call, r_); goto cleanup; } } while (0)
static VkInstance instance;
static VkDevice device;
static VkBuffer buffers[2];
static VkDeviceMemory memory[2];
static uint32_t *mapped[2];
static VkDescriptorSetLayout set_layout;
static VkDescriptorPool descriptors;
static VkPipelineLayout pipeline_layout;
static VkShaderModule shader;
static VkPipeline pipeline;
static VkCommandPool commands;
static VkFence fence;
static uint32_t reference[MAX_PIXELS];
static double ns(clockid_t clock) {
  struct timespec t;
  if (clock_gettime(clock, &t)) { perror("clock_gettime"); _Exit(3); }
  return (double)t.tv_sec * 1e9 + t.tv_nsec;
}
static void uuid_text(const uint8_t *uuid, char out[33]) {
  for (unsigned i = 0; i < VK_UUID_SIZE; ++i) snprintf(out + i * 2, 3, "%02x", uuid[i]);
}
static uint32_t sample(unsigned x, unsigned y, unsigned pattern) {
  if (pattern == 0) return 255;
  if (pattern == 1) return (x == 0 && y == 0) ? 255 : 0;
  return ((x * 73u) ^ (y * 151u) ^ ((x * y) * 17u)) & 255u;
}
static void cpu_reference(unsigned w, unsigned h) {
  // Independent scalar traversal over the same input, exact integer division.
  for (unsigned y = 0; y < h; ++y) {
    for (unsigned x = 0; x < w; ++x) {
      unsigned sum = 0;
      for (int yy = (int)y - 1; yy <= (int)y + 1; ++yy) {
        unsigned row = yy < 0 ? 0 : (yy >= (int)h ? h - 1 : (unsigned)yy);
        for (int xx = (int)x - 1; xx <= (int)x + 1; ++xx) {
          unsigned col = xx < 0 ? 0 : (xx >= (int)w ? w - 1 : (unsigned)xx);
          sum += mapped[0][row * w + col];
        }
      }
      reference[y * w + x] = sum / 9;
    }
  }
}
int main(int argc, char **argv) {
  int status = 1;
  FILE *file = NULL;
  uint32_t *code = NULL;
  const int list = argc == 2 && !strcmp(argv[1], "--list");
  if (!list && (argc != 4 || strcmp(argv[1], "--device-uuid") || strlen(argv[2]) != 32)) {
    fprintf(stderr, "usage: %s --list | --device-uuid <32 lowercase hex> <box.spv>\n", argv[0]);
    return 2;
  }
  setvbuf(stdout, NULL, _IOLBF, 0);
  alarm(12); // Whole-process backstop; the supervisor also bounds loader/cleanup hangs.
  double setup_start = ns(CLOCK_MONOTONIC);
  VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
    .pApplicationName = "pi-bounded-box-filter", .apiVersion = VK_API_VERSION_1_2 };
  VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    .pApplicationInfo = &app };
  CHECK(vkCreateInstance(&ici, NULL, &instance));
  VkPhysicalDevice physical[16], selected = VK_NULL_HANDLE;
  uint32_t count = 16;
  CHECK(vkEnumeratePhysicalDevices(instance, &count, physical));
  VkPhysicalDeviceProperties props = {0};
  for (uint32_t i = 0; i < count; ++i) {
    VkPhysicalDeviceIDProperties id = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES };
    VkPhysicalDeviceDriverProperties driver = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES,
      .pNext = &id };
    VkPhysicalDeviceProperties2 p = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
      .pNext = &driver };
    vkGetPhysicalDeviceProperties(physical[i], &p.properties);
    // Driver/ID properties are core together only from Vulkan 1.2. Older
    // devices remain listable without querying unsupported property structs.
    if (p.properties.apiVersion >= VK_API_VERSION_1_2) vkGetPhysicalDeviceProperties2(physical[i], &p);
    char uuid[33]; uuid_text(id.deviceUUID, uuid);
    printf("device index=%u uuid=%s name=\"%s\" vendor=0x%x device=0x%x type=%u api=%u.%u.%u driver_id=%u driver_name=\"%s\" driver_info=\"%s\" driver_version=%u\n",
      i, uuid, p.properties.deviceName, p.properties.vendorID, p.properties.deviceID,
      p.properties.deviceType, VK_VERSION_MAJOR(p.properties.apiVersion),
      VK_VERSION_MINOR(p.properties.apiVersion), VK_VERSION_PATCH(p.properties.apiVersion),
      driver.driverID, driver.driverName, driver.driverInfo, p.properties.driverVersion);
    if (!list && !strcmp(uuid, argv[2])) {
      if (selected) { fprintf(stderr, "ambiguous_uuid\n"); goto cleanup; }
      if (p.properties.apiVersion < VK_API_VERSION_1_2 ||
          driver.driverID != VK_DRIVER_ID_MESA_V3DV ||
          strcmp(driver.driverName, "V3DV Mesa") ||
          strncmp(driver.driverInfo, "Mesa 26.2.6", 11) ||
          (driver.driverInfo[11] && driver.driverInfo[11] != ' ' && driver.driverInfo[11] != '-') ||
          !strstr(p.properties.deviceName, "V3D 4.2") ||
          p.properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU) {
        fprintf(stderr, "selected_device_is_not_expected_pi4_mesa_26_2_6\n"); goto cleanup;
      }
      selected = physical[i]; props = p.properties;
    }
  }
  if (list) { status = 0; goto cleanup; }
  if (!selected) { fprintf(stderr, "selected_uuid_absent\n"); goto cleanup; }
  VkQueueFamilyProperties families[32];
  uint32_t family_count = 0, family = UINT32_MAX;
  // The fill call returns only the number written, so check the full count
  // first rather than silently accepting a truncated fixed-size inventory.
  vkGetPhysicalDeviceQueueFamilyProperties(selected, &family_count, NULL);
  if (family_count > 32) { fprintf(stderr, "too_many_queue_families\n"); goto cleanup; }
  vkGetPhysicalDeviceQueueFamilyProperties(selected, &family_count, families);
  for (uint32_t i = 0; i < family_count; ++i) {
    if (families[i].queueCount && (families[i].queueFlags & VK_QUEUE_COMPUTE_BIT)) { family = i; break; }
  }
  VkPhysicalDeviceLimits l = props.limits;
  printf("limits local=%u,%u,%u invocations=%u groups=%u,%u,%u storage_range=%u storage_stage=%u storage_set=%u push=%u shared=%u allocations=%u\n",
    l.maxComputeWorkGroupSize[0], l.maxComputeWorkGroupSize[1], l.maxComputeWorkGroupSize[2],
    l.maxComputeWorkGroupInvocations, l.maxComputeWorkGroupCount[0], l.maxComputeWorkGroupCount[1],
    l.maxComputeWorkGroupCount[2], l.maxStorageBufferRange, l.maxPerStageDescriptorStorageBuffers,
    l.maxDescriptorSetStorageBuffers, l.maxPushConstantsSize, l.maxComputeSharedMemorySize, l.maxMemoryAllocationCount);
  if (family == UINT32_MAX || l.maxComputeWorkGroupSize[0] < 8 || l.maxComputeWorkGroupSize[1] < 8 ||
      l.maxComputeWorkGroupSize[2] < 1 || l.maxComputeWorkGroupInvocations < 64 ||
      l.maxComputeWorkGroupCount[0] < 33 || l.maxComputeWorkGroupCount[1] < 25 ||
      l.maxComputeWorkGroupCount[2] < 1 || l.maxStorageBufferRange < BYTES ||
      l.maxPerStageDescriptorStorageBuffers < 2 || l.maxDescriptorSetStorageBuffers < 2 ||
      l.maxPushConstantsSize < 8 || l.maxMemoryAllocationCount < 2) {
    fprintf(stderr, "insufficient_compute_limits\n"); goto cleanup;
  }
  printf("queue family=%u flags=0x%x timestamp_valid_bits=%u gpu_execution_ns=unknown energy=unknown\n",
    family, families[family].queueFlags, families[family].timestampValidBits);
  float priority = 0.5f;
  VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    .queueFamilyIndex = family, .queueCount = 1, .pQueuePriorities = &priority };
  VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci };
  CHECK(vkCreateDevice(selected, &dci, NULL, &device));
  VkQueue queue; vkGetDeviceQueue(device, family, 0, &queue);
  VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(selected, &mp);
  for (unsigned b = 0; b < 2; ++b) {
    VkBufferCreateInfo bi = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size = BYTES, .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
      .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
    CHECK(vkCreateBuffer(device, &bi, NULL, &buffers[b]));
    VkMemoryRequirements mr; vkGetBufferMemoryRequirements(device, buffers[b], &mr);
    uint32_t mt = UINT32_MAX;
    for (uint32_t j = 0; j < mp.memoryTypeCount; ++j) {
      VkMemoryPropertyFlags need = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
      if ((mr.memoryTypeBits & (1u << j)) && (mp.memoryTypes[j].propertyFlags & need) == need) { mt = j; break; }
    }
    if (mt == UINT32_MAX || mr.size > 4u * 1024u * 1024u) {
      fprintf(stderr, "coherent_memory_unavailable_or_allocation_over_cap\n"); goto cleanup;
    }
    VkMemoryAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = mr.size, .memoryTypeIndex = mt };
    CHECK(vkAllocateMemory(device, &ai, NULL, &memory[b]));
    CHECK(vkBindBufferMemory(device, buffers[b], memory[b], 0));
    CHECK(vkMapMemory(device, memory[b], 0, BYTES, 0, (void **)&mapped[b]));
    printf("buffer=%u bytes=%zu allocation=%llu memory_type=%u flags=0x%x\n", b, (size_t)BYTES,
      (unsigned long long)mr.size, mt, mp.memoryTypes[mt].propertyFlags);
  }
  VkDescriptorSetLayoutBinding bindings[2] = {
    { .binding = 0, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT },
    { .binding = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT }
  };
  VkDescriptorSetLayoutCreateInfo sli = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    .bindingCount = 2, .pBindings = bindings };
  CHECK(vkCreateDescriptorSetLayout(device, &sli, NULL, &set_layout));
  VkPushConstantRange push = { .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .size = 8 };
  VkPipelineLayoutCreateInfo pli = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    .setLayoutCount = 1, .pSetLayouts = &set_layout, .pushConstantRangeCount = 1, .pPushConstantRanges = &push };
  CHECK(vkCreatePipelineLayout(device, &pli, NULL, &pipeline_layout));
  file = fopen(argv[3], "rb");
  if (!file || fseek(file, 0, SEEK_END)) { perror("shader open/seek"); goto cleanup; }
  long length = ftell(file);
  if (length < 20 || length > 65536 || length % 4 || fseek(file, 0, SEEK_SET)) {
    fprintf(stderr, "shader_size_invalid\n"); goto cleanup;
  }
  code = malloc((size_t)length);
  if (!code || fread(code, 1, (size_t)length, file) != (size_t)length || code[0] != 0x07230203) {
    fprintf(stderr, "shader_read_invalid\n"); goto cleanup;
  }
  fclose(file); file = NULL;
  VkShaderModuleCreateInfo smi = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    .codeSize = (size_t)length, .pCode = code };
  CHECK(vkCreateShaderModule(device, &smi, NULL, &shader));
  VkComputePipelineCreateInfo pci = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
    .stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
      .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = shader, .pName = "main" }, .layout = pipeline_layout };
  CHECK(vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pci, NULL, &pipeline));
  VkDescriptorPoolSize ps = { .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 2 };
  VkDescriptorPoolCreateInfo dpi = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps };
  CHECK(vkCreateDescriptorPool(device, &dpi, NULL, &descriptors));
  VkDescriptorSetAllocateInfo sai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    .descriptorPool = descriptors, .descriptorSetCount = 1, .pSetLayouts = &set_layout };
  VkDescriptorSet set; CHECK(vkAllocateDescriptorSets(device, &sai, &set));
  VkDescriptorBufferInfo dbi[2] = { { buffers[0], 0, BYTES }, { buffers[1], 0, BYTES } };
  VkWriteDescriptorSet writes[2] = {0};
  for (unsigned i = 0; i < 2; ++i) {
    writes[i] = (VkWriteDescriptorSet){ .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      .dstSet = set, .dstBinding = i, .descriptorCount = 1,
      .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi[i] };
  }
  vkUpdateDescriptorSets(device, 2, writes, 0, NULL);
  VkCommandPoolCreateInfo cpi = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = family };
  CHECK(vkCreateCommandPool(device, &cpi, NULL, &commands));
  VkCommandBufferAllocateInfo cai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    .commandPool = commands, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
  VkCommandBuffer cb; CHECK(vkAllocateCommandBuffers(device, &cai, &cb));
  VkFenceCreateInfo fi = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
  CHECK(vkCreateFence(device, &fi, NULL, &fence));
  printf("setup_wall_ns=%.0f\n", ns(CLOCK_MONOTONIC) - setup_start);
  const uint32_t shapes[3][2] = { {1, 1}, {17, 19}, {257, 193} };
  for (unsigned test = 0; test < 3; ++test) {
    unsigned w = shapes[test][0], h = shapes[test][1], n = w * h;
    for (unsigned i = 0; i < MAX_PIXELS + GUARD; ++i) {
      mapped[0][i] = i < n ? sample(i % w, i / w, test) : 0xdeadbeef;
      mapped[1][i] = 0xdeadbeef;
    }
    double rc = ns(CLOCK_PROCESS_CPUTIME_ID), rw = ns(CLOCK_MONOTONIC);
    cpu_reference(w, h);
    double ref_wall = ns(CLOCK_MONOTONIC) - rw, ref_cpu = ns(CLOCK_PROCESS_CPUTIME_ID) - rc;
    CHECK(vkResetCommandBuffer(cb, 0));
    CHECK(vkResetFences(device, 1, &fence));
    VkCommandBufferBeginInfo begin = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    CHECK(vkBeginCommandBuffer(cb, &begin));
    VkMemoryBarrier before = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
      .srcAccessMask = VK_ACCESS_HOST_WRITE_BIT, .dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT };
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_HOST_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
      0, 1, &before, 0, NULL, 0, NULL);
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout, 0, 1, &set, 0, NULL);
    vkCmdPushConstants(cb, pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, shapes[test]);
    vkCmdDispatch(cb, (w + 7) / 8, (h + 7) / 8, 1);
    VkMemoryBarrier after = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
      .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT };
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT,
      0, 1, &after, 0, NULL, 0, NULL);
    CHECK(vkEndCommandBuffer(cb));
    VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
    double hc = ns(CLOCK_PROCESS_CPUTIME_ID), hw = ns(CLOCK_MONOTONIC);
    VkResult submit = vkQueueSubmit(queue, 1, &si, fence);
    if (submit != VK_SUCCESS) { fprintf(stderr, "submit_failed=%d health_handoff=required\n", submit); fflush(NULL); _Exit(3); }
    VkResult wait = vkWaitForFences(device, 1, &fence, VK_TRUE, 2000000000ull);
    double submit_wall = ns(CLOCK_MONOTONIC) - hw, submit_cpu = ns(CLOCK_PROCESS_CPUTIME_ID) - hc;
    if (wait != VK_SUCCESS) {
      fprintf(stderr, "fence_result=%d health_handoff=required no_retry pending_resources_process_teardown\n", wait);
      fflush(NULL); _Exit(3);
    }
    unsigned mismatch = 0, corrupt = 0;
    for (unsigned i = 0; i < MAX_PIXELS + GUARD; ++i) {
      uint32_t input = i < n ? sample(i % w, i / w, test) : 0xdeadbeef;
      if (mapped[0][i] != input) ++corrupt;
      if (i < n) {
        if (mapped[1][i] != reference[i]) {
          if (!mismatch) fprintf(stderr, "first_mismatch case=%u index=%u expected=%u actual=%u\n", test, i, reference[i], mapped[1][i]);
          ++mismatch;
        }
      } else if (mapped[1][i] != 0xdeadbeef) ++corrupt;
    }
    printf("case=%u width=%u height=%u pattern=%u pixels=%u logical_reads=%u logical_writes=%u ref_wall_ns=%.0f ref_cpu_ns=%.0f submit_fence_wall_ns=%.0f submit_fence_process_cpu_ns=%.0f gpu_execution_ns=unknown mismatches=%u corruption=%u\n",
      test, w, h, test, n, n * 9, n, ref_wall, ref_cpu, submit_wall, submit_cpu, mismatch, corrupt);
    if (mismatch || corrupt) { fprintf(stderr, "correctness=FAIL no_retry\n"); goto cleanup; }
  }
  puts("correctness=PASS cases=3 energy=unknown desktop_acceleration=unmeasured");
  status = 0;
cleanup:
  if (file) fclose(file);
  free(code);
  if (device) {
    if (fence) vkDestroyFence(device, fence, NULL);
    if (commands) vkDestroyCommandPool(device, commands, NULL);
    if (pipeline) vkDestroyPipeline(device, pipeline, NULL);
    if (shader) vkDestroyShaderModule(device, shader, NULL);
    if (descriptors) vkDestroyDescriptorPool(device, descriptors, NULL);
    if (pipeline_layout) vkDestroyPipelineLayout(device, pipeline_layout, NULL);
    if (set_layout) vkDestroyDescriptorSetLayout(device, set_layout, NULL);
    for (unsigned i = 0; i < 2; ++i) {
      if (mapped[i]) vkUnmapMemory(device, memory[i]);
      if (buffers[i]) vkDestroyBuffer(device, buffers[i], NULL);
      if (memory[i]) vkFreeMemory(device, memory[i], NULL);
    }
    vkDestroyDevice(device, NULL);
  }
  if (instance) vkDestroyInstance(instance, NULL);
  return status;
}
