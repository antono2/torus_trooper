#ifndef TT_VULKAN_BRIDGE_H
#define TT_VULKAN_BRIDGE_H

#ifndef GLFW_INCLUDE_VULKAN
#define GLFW_INCLUDE_VULKAN
#endif
#include <GLFW/glfw3.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stddef.h>
#include <ctype.h>
#include "../shaders/hud_state.h"

#define TT_MAX_DEVICES 16
#define TT_FRAMES_IN_FLIGHT 2
#define TT_MAX_BULLETS 512
#define TT_MAX_RENDER_INSTANCES 2048
#define TT_MAX_TUNNEL_VERTICES 350000
#define TT_MAX_TUNNEL_FILL_VERTICES 400000
#define TT_MAX_SHIP_VERTICES 196608
#define TT_INPUT_ACTION_COUNT 13
#define TT_MAX_ACTION_KEYS 24
#define TT_GAMEPAD_BUTTON_BASE (-100)
#define TT_GAMEPAD_AXIS_NEGATIVE_BASE (-200)
#define TT_GAMEPAD_AXIS_POSITIVE_BASE (-220)
#define TT_JOYSTICK_BUTTON_BASE (-300)
#define TT_JOYSTICK_AXIS_NEGATIVE_BASE (-400)
#define TT_JOYSTICK_AXIS_POSITIVE_BASE (-420)
#define TT_TITLE_MASK_VERTEX_COUNT (32 * 6 + 32 * 16 * 6 + 6)
#define TT_HUD_DIGIT_VERTEX_COUNT (42 * 66)
#define TT_HUD_TITLE_TORUS_VERTEX_COUNT (32 * 16 * 2 * 6)
#define TT_HUD_TITLE_WORDMARK_VERTEX_COUNT (13 * 7 * 5 * 6)
#define TT_HUD_TITLE_GRADE_RING_VERTEX_COUNT (3 * 64 * 6)
#define TT_HUD_DIGIT_VERTEX_OFFSET TT_TITLE_MASK_VERTEX_COUNT
#define TT_HUD_TITLE_WORDMARK_VERTEX_OFFSET \
    (TT_HUD_DIGIT_VERTEX_OFFSET + TT_HUD_DIGIT_VERTEX_COUNT + \
     TT_HUD_TITLE_TORUS_VERTEX_COUNT)
#define TT_HUD_TITLE_GRADE_LABEL_VERTEX_OFFSET \
    (TT_HUD_TITLE_WORDMARK_VERTEX_OFFSET + TT_HUD_TITLE_WORDMARK_VERTEX_COUNT + \
     TT_HUD_TITLE_GRADE_RING_VERTEX_COUNT)
#define TT_HUD_MENU_SELECTION_VERTEX_COUNT (6 * 6)
#define TT_HUD_HELP_DIAGRAM_VERTEX_COUNT (4 * 6)
#define TT_HUD_HELP_VERTEX_COUNT (4 * 6 + 29 * 23 * 7 * 5 * 6)
#define TT_HUD_VERTEX_COUNT \
    (TT_HUD_DIGIT_VERTEX_COUNT + TT_TITLE_MASK_VERTEX_COUNT + \
     TT_HUD_TITLE_TORUS_VERTEX_COUNT + TT_HUD_TITLE_WORDMARK_VERTEX_COUNT + \
     TT_HUD_TITLE_GRADE_RING_VERTEX_COUNT + 83 * 7 * 5 * 6 + \
     9 * 7 * 5 * 6 + 7 * 42 + 8 * 7 * 5 * 6 + 46 * 7 * 5 * 6 + \
     7 * 7 * 5 * 6 + TT_HUD_HELP_VERTEX_COUNT + TT_HUD_MENU_SELECTION_VERTEX_COUNT)
#define TT_HUD_HELP_VERTEX_OFFSET \
    (TT_HUD_VERTEX_COUNT - TT_HUD_MENU_SELECTION_VERTEX_COUNT - TT_HUD_HELP_VERTEX_COUNT)

// Opaque clears, in normalized RGBA. Keep the background in sync with
// color_background_navy in shaders/palette.glsl so the near fade meets it.
static const VkClearValue tt_background_navy = {.color = {{0.008f, 0.012f, 0.03f, 1.0f}}};
static const VkClearValue tt_opaque_black = {.color = {{0.0f, 0.0f, 0.0f, 1.0f}}};
static const VkClearValue tt_loading_bar_slate = {.color = {{0.08f, 0.12f, 0.18f, 1.0f}}};
static const VkClearValue tt_loading_progress_cyan = {.color = {{0.22f, 0.82f, 1.0f, 1.0f}}};

typedef struct TTDeviceInfo {
    char name[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE];
    uint32_t api_version;
    uint32_t driver_version;
    int graphics_queue_family;
    int present_queue_family;
} TTDeviceInfo;

typedef struct TTPushConstants {
    float time, aspect, view_angle;
    int score, remaining_time_ms, hits, zone, state;
    float tunnel_color[4];
    float brightness, luminosity;
    float camera_depth_offset, camera_zoom;
    float transition_fade;
    int speed, rank, rank_remaining;
    float camera_shake_x, camera_shake_y;
    float camera_3d, camera_eye_height;
    float camera_look_angle, camera_look_depth, camera_look_height;
    float camera_rotation;
    int next_extend_score, time_change_ticks, time_change_seconds;
    float ship_surface_radius;
} TTPushConstants;

typedef char tt_push_constant_size_must_be_128[
    sizeof(TTPushConstants) == 128 ? 1 : -1];
typedef char tt_camera_3d_offset_must_be_88[
    offsetof(TTPushConstants, camera_3d) == 88 ? 1 : -1];
typedef char tt_camera_rotation_offset_must_be_108[
    offsetof(TTPushConstants, camera_rotation) == 108 ? 1 : -1];
typedef char tt_next_extend_score_offset_must_be_112[
    offsetof(TTPushConstants, next_extend_score) == 112 ? 1 : -1];
typedef char tt_time_change_seconds_offset_must_be_120[
    offsetof(TTPushConstants, time_change_seconds) == 120 ? 1 : -1];
typedef char tt_ship_surface_radius_offset_must_be_124[
    offsetof(TTPushConstants, ship_surface_radius) == 124 ? 1 : -1];

typedef struct TTMappedBuffer {
    VkBuffer handle;
    void *mapped;
    VkDeviceSize size;
    VkDeviceSize frame_size;
} TTMappedBuffer;

typedef struct TTShaderPair {
    VkShaderModule vertex;
    VkShaderModule fragment;
} TTShaderPair;

typedef struct TTPostPushConstants {
    float aspect;
    float near_blur;
    float ship_radius;
    float enabled;
    float near_fade;
} TTPostPushConstants;

typedef struct TTFrameResources {
    VkCommandBuffer command;
    VkSemaphore image_available;
    VkFence in_flight;
} TTFrameResources;

typedef struct TTPlatform {
    GLFWwindow *window;
    bool replay_library_open;
    bool replay_text_edit;
    int replay_events[128];
    int replay_event_count;
    uint32_t replay_gamepad_latch;
    unsigned char replay_lines[24][80];
    int replay_line_count;
    int replay_selected_line;
    VkInstance instance;
    VkSurfaceKHR surface;
    TTDeviceInfo devices[TT_MAX_DEVICES];
    VkPhysicalDevice physical_devices[TT_MAX_DEVICES];
    int device_count;
    int selected_device;
    bool wide_lines;
    float max_line_width;
    VkDevice device;
    VkQueue graphics_queue;
    VkQueue present_queue;
    VkSwapchainKHR swapchain;
    VkFormat swapchain_format;
    VkFormat depth_format;
    VkSampleCountFlagBits sample_count;
    int requested_sample_count;
    VkExtent2D swapchain_extent;
    VkImage *swapchain_images;
    VkImageView *swapchain_views;
    VkImage *multisample_images;
    VkDeviceMemory *multisample_memories;
    VkImageView *multisample_views;
    VkImage *scene_images;
    VkDeviceMemory *scene_memories;
    VkImageView *scene_views;
    VkImage *depth_images;
    VkDeviceMemory *depth_memories;
    VkImageView *depth_views;
    VkFramebuffer *framebuffers;
    VkFramebuffer *post_framebuffers;
    bool *image_initialized;
    uint32_t swapchain_image_count;
    VkRenderPass render_pass;
    VkRenderPass post_render_pass;
    VkPipelineLayout pipeline_layout;
    VkPipelineLayout post_pipeline_layout;
    VkPipeline pipeline;
    VkPipeline tunnel_fill_pipeline;
    VkPipeline ship_pipeline;
    VkPipeline bullet_pipeline;
    VkPipeline bullet_opacity_pipeline;
    VkPipeline bullet_overlay_pipeline;
    VkPipeline hud_pipeline;
    VkPipeline post_pipeline;
    VkDescriptorSetLayout post_descriptor_layout;
    VkDescriptorPool post_descriptor_pool;
    VkDescriptorSet *post_descriptor_sets;
    VkSampler post_sampler;
    VkRenderPass loading_render_pass;
    VkFramebuffer *loading_framebuffers;
    TTMappedBuffer bullet_buffer;
    uint32_t bullet_count;
    bool bullet_opacity[TT_MAX_RENDER_INSTANCES];
    uint32_t multiplier_popup_first;
    uint32_t multiplier_popup_count;
    TTMappedBuffer tunnel_buffer;
    uint32_t tunnel_vertex_count;
    TTMappedBuffer tunnel_fill_buffer;
    uint32_t tunnel_fill_vertex_count;
    uint32_t ship_vertex_count;
    uint32_t ship_material_seed;
    float tunnel_color[4];
    float brightness;
    float luminosity;
    float camera_depth_offset;
    float camera_zoom;
    float camera_shake_x;
    float camera_shake_y;
    float camera_3d;
    float camera_eye_height;
    float camera_look_angle;
    float camera_look_depth;
    float camera_look_height;
    float camera_rotation;
    float ship_surface_radius;
    float ship_render_depth;
    float near_camera_blur;
    float near_camera_fade;
    float transition_fade;
    float replay_view_ratio;
    int action_keys[TT_INPUT_ACTION_COUNT][TT_MAX_ACTION_KEYS];
    int action_key_counts[TT_INPUT_ACTION_COUNT];
    int god_mode_sequence_index;
    bool god_mode_toggle_requested;
    bool fullscreen_toggle_requested;
    bool fullscreen_key_was_down;
    bool fps_toggle_requested;
    bool fps_key_was_down;
    bool fps_visible;
    bool calibration_save_requested;
    bool calibration_reload_requested;
    bool calibration_reset_requested;
    bool calibration_auto_orbit_requested;
    int calibration_cycle_requested;
    bool mouse_captured;
    bool mouse_initialized;
    double mouse_x;
    double mouse_y;
    double mouse_delta_x;
    double mouse_delta_y;
    uint32_t typed_letter_mask;
    bool borderless_fullscreen;
    int windowed_x;
    int windowed_y;
    int windowed_width;
    int windowed_height;
    float view_angle;
    VkCommandPool command_pool;
    TTFrameResources frames[TT_FRAMES_IN_FLIGHT];
    VkSemaphore *render_finished;
    uint32_t frame_index;
    bool upload_frame_ready;
    uint64_t rendered_frames;
    uint64_t fps_sample_frames;
    double fps_sample_time;
    int display_fps;
    int fps_limit;
    double next_frame_deadline;
    VkPresentModeKHR present_mode;
    double start_time;
    double paused_time;
    bool paused;
    bool startup_complete;
    bool startup_cancel_requested;
    int hud_score;
    int hud_remaining_time_ms;
    int hud_hits;
    int hud_zone;
    int hud_state;
    int hud_speed;
    int hud_rank;
    int hud_rank_remaining;
    int hud_next_extend_score;
    int hud_time_change_ticks;
    int hud_time_change_seconds;
    int title_levels[3];
    int title_max_levels[3];
    int title_high_scores[3];
    int title_high_score_start_levels[3];
    int title_high_score_end_levels[3];
    int title_antialiasing_samples;
    int title_near_blur_percent;
    int title_near_fade_percent;
    int title_rear_track_blend_percent;
    int title_track_draw_distance;
    int title_wire_draw_distance;
    int title_border_draw_distance;
    int title_player_shot_distance;
    bool hud_visible;
} TTPlatform;

static char tt_platform_error[512];
static void tt_platform_destroy(TTPlatform *platform);
static bool tt_create_swapchain(TTPlatform *platform);
static bool tt_platform_toggle_borderless_fullscreen(TTPlatform *platform);
static bool tt_platform_set_loading_progress(TTPlatform *platform, float progress);
static void tt_platform_finish_loading(TTPlatform *platform);
static bool tt_action_pressed(TTPlatform *platform, int action);
static void tt_set_error(const char *message);
static void tt_set_vk_error(const char *operation, VkResult result);

static int tt_antialiasing_sample_count(int requested_samples,
                                        VkSampleCountFlags support) {
    if (requested_samples >= 8 && (support & VK_SAMPLE_COUNT_8_BIT)) return 8;
    if (requested_samples >= 4 && (support & VK_SAMPLE_COUNT_4_BIT)) return 4;
    if (requested_samples >= 2 && (support & VK_SAMPLE_COUNT_2_BIT)) return 2;
    return 1;
}

static uint32_t tt_find_memory_type(VkPhysicalDevice physical, uint32_t type_bits,
                                    VkMemoryPropertyFlags required) {
    VkPhysicalDeviceMemoryProperties properties;
    vkGetPhysicalDeviceMemoryProperties(physical, &properties);
    for (uint32_t index = 0; index < properties.memoryTypeCount; ++index) {
        if ((type_bits & (1u << index)) &&
            (properties.memoryTypes[index].propertyFlags & required) == required)
            return index;
    }
    return UINT32_MAX;
}

static bool tt_create_depth_targets(TTPlatform *platform) {
    uint32_t count = platform->swapchain_image_count;
    platform->depth_images = calloc(count, sizeof(*platform->depth_images));
    platform->depth_memories = calloc(count, sizeof(*platform->depth_memories));
    platform->depth_views = calloc(count, sizeof(*platform->depth_views));
    if (!platform->depth_images || !platform->depth_memories || !platform->depth_views) {
        tt_set_error("out of memory while creating depth-target state");
        return false;
    }
    VkPhysicalDevice physical = platform->physical_devices[platform->selected_device];
    const VkFormat candidates[] = {
        VK_FORMAT_D32_SFLOAT,
        VK_FORMAT_D24_UNORM_S8_UINT,
        VK_FORMAT_D32_SFLOAT_S8_UINT,
        VK_FORMAT_D16_UNORM,
    };
    platform->depth_format = VK_FORMAT_UNDEFINED;
    for (size_t index = 0; index < sizeof(candidates) / sizeof(candidates[0]); ++index) {
        VkFormatProperties properties;
        vkGetPhysicalDeviceFormatProperties(physical, candidates[index], &properties);
        if (properties.optimalTilingFeatures &
            VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) {
            platform->depth_format = candidates[index];
            break;
        }
    }
    if (platform->depth_format == VK_FORMAT_UNDEFINED) {
        tt_set_error("physical device exposes no depth-attachment format");
        return false;
    }
    for (uint32_t index = 0; index < count; ++index) {
        VkImageCreateInfo image_info = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = VK_IMAGE_TYPE_2D,
            .format = platform->depth_format,
            .extent = {platform->swapchain_extent.width,
                       platform->swapchain_extent.height, 1},
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = platform->sample_count,
            .tiling = VK_IMAGE_TILING_OPTIMAL,
            .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        };
        VkResult result = vkCreateImage(platform->device, &image_info, NULL,
                                        &platform->depth_images[index]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateImage(depth)", result);
            return false;
        }
        VkMemoryRequirements requirements;
        vkGetImageMemoryRequirements(platform->device, platform->depth_images[index],
                                     &requirements);
        uint32_t memory_type = tt_find_memory_type(
            physical, requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        if (memory_type == UINT32_MAX)
            memory_type = tt_find_memory_type(physical, requirements.memoryTypeBits, 0);
        if (memory_type == UINT32_MAX) {
            tt_set_error("no compatible memory type for depth target");
            return false;
        }
        VkMemoryAllocateInfo allocation_info = {
            .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = requirements.size,
            .memoryTypeIndex = memory_type,
        };
        result = vkAllocateMemory(platform->device, &allocation_info, NULL,
                                  &platform->depth_memories[index]);
        if (result == VK_SUCCESS)
            result = vkBindImageMemory(platform->device, platform->depth_images[index],
                                       platform->depth_memories[index], 0);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("depth-target allocation", result);
            return false;
        }
        VkImageViewCreateInfo view_info = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = platform->depth_images[index],
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = platform->depth_format,
            .subresourceRange = {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 1, 0, 1},
        };
        result = vkCreateImageView(platform->device, &view_info, NULL,
                                   &platform->depth_views[index]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateImageView(depth)", result);
            return false;
        }
    }
    return true;
}

static bool tt_create_multisample_targets(TTPlatform *platform) {
    if (platform->sample_count == VK_SAMPLE_COUNT_1_BIT) return true;
    uint32_t count = platform->swapchain_image_count;
    platform->multisample_images = calloc(count, sizeof(*platform->multisample_images));
    platform->multisample_memories = calloc(count, sizeof(*platform->multisample_memories));
    platform->multisample_views = calloc(count, sizeof(*platform->multisample_views));
    if (!platform->multisample_images || !platform->multisample_memories ||
        !platform->multisample_views) {
        tt_set_error("out of memory while creating multisample-target state");
        return false;
    }
    VkPhysicalDevice physical = platform->physical_devices[platform->selected_device];
    for (uint32_t index = 0; index < count; ++index) {
        VkImageCreateInfo image_info = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = VK_IMAGE_TYPE_2D,
            .format = platform->swapchain_format,
            .extent = {platform->swapchain_extent.width,
                       platform->swapchain_extent.height, 1},
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = platform->sample_count,
            .tiling = VK_IMAGE_TILING_OPTIMAL,
            .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        };
        VkResult result = vkCreateImage(platform->device, &image_info, NULL,
                                        &platform->multisample_images[index]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateImage(multisample color)", result);
            return false;
        }
        VkMemoryRequirements requirements;
        vkGetImageMemoryRequirements(platform->device,
                                     platform->multisample_images[index],
                                     &requirements);
        uint32_t memory_type = tt_find_memory_type(
            physical, requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        if (memory_type == UINT32_MAX)
            memory_type = tt_find_memory_type(physical, requirements.memoryTypeBits, 0);
        if (memory_type == UINT32_MAX) {
            tt_set_error("no compatible memory type for multisample color target");
            return false;
        }
        VkMemoryAllocateInfo allocation_info = {
            .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = requirements.size,
            .memoryTypeIndex = memory_type,
        };
        result = vkAllocateMemory(platform->device, &allocation_info, NULL,
                                  &platform->multisample_memories[index]);
        if (result == VK_SUCCESS)
            result = vkBindImageMemory(platform->device,
                                       platform->multisample_images[index],
                                       platform->multisample_memories[index], 0);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("multisample color allocation", result);
            return false;
        }
        VkImageViewCreateInfo view_info = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = platform->multisample_images[index],
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = platform->swapchain_format,
            .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
        };
        result = vkCreateImageView(platform->device, &view_info, NULL,
                                   &platform->multisample_views[index]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateImageView(multisample color)", result);
            return false;
        }
    }
    return true;
}

static bool tt_create_scene_targets(TTPlatform *platform) {
    uint32_t count = platform->swapchain_image_count;
    platform->scene_images = calloc(count, sizeof(*platform->scene_images));
    platform->scene_memories = calloc(count, sizeof(*platform->scene_memories));
    platform->scene_views = calloc(count, sizeof(*platform->scene_views));
    if (!platform->scene_images || !platform->scene_memories ||
        !platform->scene_views) {
        tt_set_error("out of memory while creating post-process scene targets");
        return false;
    }
    VkPhysicalDevice physical = platform->physical_devices[platform->selected_device];
    for (uint32_t index = 0; index < count; ++index) {
        VkImageCreateInfo image_info = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = VK_IMAGE_TYPE_2D,
            .format = platform->swapchain_format,
            .extent = {platform->swapchain_extent.width,
                       platform->swapchain_extent.height, 1},
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = VK_SAMPLE_COUNT_1_BIT,
            .tiling = VK_IMAGE_TILING_OPTIMAL,
            .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                     VK_IMAGE_USAGE_SAMPLED_BIT,
            .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        };
        VkResult result = vkCreateImage(platform->device, &image_info, NULL,
                                        &platform->scene_images[index]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateImage(post-process scene)", result);
            return false;
        }
        VkMemoryRequirements requirements;
        vkGetImageMemoryRequirements(platform->device, platform->scene_images[index],
                                     &requirements);
        uint32_t memory_type = tt_find_memory_type(
            physical, requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        if (memory_type == UINT32_MAX)
            memory_type = tt_find_memory_type(physical, requirements.memoryTypeBits, 0);
        if (memory_type == UINT32_MAX) {
            tt_set_error("no compatible memory type for post-process scene target");
            return false;
        }
        VkMemoryAllocateInfo allocation_info = {
            .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = requirements.size,
            .memoryTypeIndex = memory_type,
        };
        result = vkAllocateMemory(platform->device, &allocation_info, NULL,
                                  &platform->scene_memories[index]);
        if (result == VK_SUCCESS)
            result = vkBindImageMemory(platform->device, platform->scene_images[index],
                                       platform->scene_memories[index], 0);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("post-process scene allocation", result);
            return false;
        }
        VkImageViewCreateInfo view_info = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = platform->scene_images[index],
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = platform->swapchain_format,
            .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
        };
        result = vkCreateImageView(platform->device, &view_info, NULL,
                                   &platform->scene_views[index]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateImageView(post-process scene)", result);
            return false;
        }
    }
    return true;
}

static bool tt_upload_mapped_buffer_at(TTMappedBuffer *buffer,
                                       uint32_t frame_index,
                                       VkDeviceSize frame_offset,
                                       const void *data, VkDeviceSize size) {
    if (!buffer || !buffer->mapped || frame_index >= TT_FRAMES_IN_FLIGHT ||
        frame_offset > buffer->frame_size ||
        size > buffer->frame_size - frame_offset)
        return false;
    if (size && data)
        memcpy((uint8_t *)buffer->mapped + frame_index * buffer->frame_size +
                   frame_offset,
               data, (size_t)size);
    return true;
}

static bool tt_upload_mapped_buffer(TTMappedBuffer *buffer, uint32_t frame_index,
                                    const void *data, VkDeviceSize size) {
    return tt_upload_mapped_buffer_at(buffer, frame_index, 0, data, size);
}

static bool tt_prepare_frame_upload(TTPlatform *platform) {
    if (platform->upload_frame_ready) return true;
    TTFrameResources *frame = &platform->frames[platform->frame_index];
    VkResult result = vkWaitForFences(platform->device, 1, &frame->in_flight,
                                      VK_TRUE, UINT64_MAX);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkWaitForFences", result);
        return false;
    }
    platform->upload_frame_ready = true;
    return true;
}

static uint32_t *tt_read_spirv(const char *path, size_t *size) {
    FILE *file = fopen(path, "rb");
    if (!file) {
        snprintf(tt_platform_error, sizeof(tt_platform_error), "could not open shader %s", path);
        return NULL;
    }
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    if (length <= 0 || length % 4 != 0) {
        fclose(file);
        snprintf(tt_platform_error, sizeof(tt_platform_error), "invalid SPIR-V shader %s", path);
        return NULL;
    }
    uint32_t *bytes = malloc((size_t)length);
    if (!bytes || fread(bytes, 1, (size_t)length, file) != (size_t)length) {
        free(bytes);
        fclose(file);
        snprintf(tt_platform_error, sizeof(tt_platform_error), "could not read shader %s", path);
        return NULL;
    }
    fclose(file);
    *size = (size_t)length;
    return bytes;
}

static bool tt_create_shader_module(VkDevice device, const char *path,
                                    VkShaderModule *module) {
    size_t code_size = 0;
    uint32_t *code = tt_read_spirv(path, &code_size);
    if (!code)
        return false;
    VkShaderModuleCreateInfo create_info = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code_size,
        .pCode = code,
    };
    VkResult result = vkCreateShaderModule(device, &create_info, NULL, module);
    free(code);
    if (result != VK_SUCCESS) {
        char operation[256];
        snprintf(operation, sizeof(operation), "vkCreateShaderModule(%s)", path);
        tt_set_vk_error(operation, result);
        return false;
    }
    return true;
}

static void tt_destroy_shader_pair(VkDevice device, TTShaderPair *shaders) {
    if (shaders->vertex)
        vkDestroyShaderModule(device, shaders->vertex, NULL);
    if (shaders->fragment)
        vkDestroyShaderModule(device, shaders->fragment, NULL);
    memset(shaders, 0, sizeof(*shaders));
}

static bool tt_create_shader_pair(VkDevice device, const char *vertex_path,
                                  const char *fragment_path, TTShaderPair *shaders) {
    if (!tt_create_shader_module(device, vertex_path, &shaders->vertex) ||
        !tt_create_shader_module(device, fragment_path, &shaders->fragment)) {
        tt_destroy_shader_pair(device, shaders);
        return false;
    }
    return true;
}

static bool tt_create_frame_resources(TTPlatform *platform, TTFrameResources *frame) {
    VkCommandBufferAllocateInfo allocate_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = platform->command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    VkResult result = vkAllocateCommandBuffers(platform->device, &allocate_info,
                                               &frame->command);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkAllocateCommandBuffers", result);
        return false;
    }
    VkSemaphoreCreateInfo semaphore_info = {
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    result = vkCreateSemaphore(platform->device, &semaphore_info, NULL,
                               &frame->image_available);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateSemaphore(image available)", result);
        return false;
    }
    VkFenceCreateInfo fence_info = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = VK_FENCE_CREATE_SIGNALED_BIT,
    };
    result = vkCreateFence(platform->device, &fence_info, NULL, &frame->in_flight);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateFence(in flight)", result);
        return false;
    }
    return true;
}

static void tt_destroy_frame_resources(VkDevice device, TTFrameResources *frame) {
    if (frame->image_available)
        vkDestroySemaphore(device, frame->image_available, NULL);
    if (frame->in_flight)
        vkDestroyFence(device, frame->in_flight, NULL);
    memset(frame, 0, sizeof(*frame));
}

static void tt_set_error(const char *message) {
    snprintf(tt_platform_error, sizeof(tt_platform_error), "%s", message);
}

static void tt_set_vk_error(const char *operation, VkResult result) {
    snprintf(tt_platform_error, sizeof(tt_platform_error), "%s failed with VkResult %d",
             operation, result);
}

static void tt_glfw_error_callback(int code, const char *description) {
    snprintf(tt_platform_error, sizeof(tt_platform_error), "GLFW error %d: %s", code,
             description ? description : "unknown error");
}

// Action indices are also bit positions in the mask returned to V.
// The first six positions match the saved replay format in sim/replay.v.
enum TTInputAction {
    TT_ACTION_LEFT,
    TT_ACTION_RIGHT,
    TT_ACTION_UP,
    TT_ACTION_DOWN,
    TT_ACTION_FIRE,
    TT_ACTION_CHARGE,
    TT_ACTION_PAUSE,
    TT_ACTION_RESTART,
    TT_ACTION_BACK,
    TT_ACTION_VOLUME_DOWN,
    TT_ACTION_VOLUME_UP,
    TT_ACTION_FULLSCREEN,
    TT_ACTION_FPS,
};

static void tt_replay_event(TTPlatform *platform, int event) {
    if (platform->replay_event_count < 128)
        platform->replay_events[platform->replay_event_count++] = event;
}

static int tt_platform_take_replay_event(TTPlatform *platform) {
    if (!platform || !platform->replay_event_count) return 0;
    int event = platform->replay_events[0];
    memmove(platform->replay_events, platform->replay_events + 1,
            (size_t)(--platform->replay_event_count) * sizeof(int));
    return event;
}

static const char *tt_platform_clipboard(TTPlatform *platform) {
    const char *value = glfwGetClipboardString(platform->window);
    return value ? value : "";
}

static void tt_platform_replay_overlay(TTPlatform *platform, bool open,
                                      bool editing, int selected) {
    platform->replay_library_open = open;
    platform->replay_text_edit = editing;
    platform->replay_line_count = 0;
    platform->replay_selected_line = selected;
    if (!open) platform->replay_event_count = 0;
}

static void tt_platform_replay_line(TTPlatform *platform,
                                   const unsigned char *codes, int length) {
    if (platform->replay_line_count >= 24) return;
    unsigned char *line = platform->replay_lines[platform->replay_line_count++];
    memset(line, 0, 80);
    if (length > 80) length = 80;
    if (length > 0) memcpy(line, codes, (size_t)length);
}

static void tt_key_callback(GLFWwindow *window, int key, int scancode,
                            int action, int mods) {
    (void)scancode;
    if (action != GLFW_PRESS && action != GLFW_REPEAT) return;
    TTPlatform *platform = glfwGetWindowUserPointer(window);
    if (!platform) return;
    if (platform->replay_library_open) {
        if (action == GLFW_REPEAT && key != GLFW_KEY_UP && key != GLFW_KEY_DOWN &&
            key != GLFW_KEY_BACKSPACE) return;
        if (platform->replay_text_edit && key == GLFW_KEY_A && (mods & GLFW_MOD_CONTROL))
            tt_replay_event(platform, -1001);
        else if (platform->replay_text_edit && key == GLFW_KEY_V && (mods & GLFW_MOD_CONTROL))
            tt_replay_event(platform, -1000);
        else if (!platform->replay_text_edit || key == GLFW_KEY_ENTER ||
                 key == GLFW_KEY_ESCAPE || key == GLFW_KEY_BACKSPACE)
            tt_replay_event(platform, -key);
        return;
    }
    if (action != GLFW_PRESS) return;
    if (key == GLFW_KEY_ESCAPE && !platform->startup_complete) {
        // A quick press can begin and end while a driver is compiling the next
        // pipeline. Latch it so startup remains cancellable between stages.
        platform->startup_cancel_requested = true;
        return;
    }
    if (key == GLFW_KEY_S && (mods & GLFW_MOD_CONTROL))
        platform->calibration_save_requested = true;
    if (key == GLFW_KEY_R && (mods & GLFW_MOD_CONTROL))
        platform->calibration_reload_requested = true;
    if (key == GLFW_KEY_BACKSPACE)
        platform->calibration_reset_requested = true;
    if (key == GLFW_KEY_SPACE)
        platform->calibration_auto_orbit_requested = true;
    if (key == GLFW_KEY_TAB)
        platform->calibration_cycle_requested +=
            (mods & GLFW_MOD_SHIFT) ? -1 : 1;
    for (int index = 0;
         index < platform->action_key_counts[TT_ACTION_FULLSCREEN]; ++index) {
        if (platform->action_keys[TT_ACTION_FULLSCREEN][index] == key) {
            // Defer the resize until event polling has returned. Calling
            // glfwSetWindowMonitor from inside GLFW's callback is reentrant and
            // left some window managers in the prior windowed state.
            platform->fullscreen_toggle_requested = true;
            return;
        }
    }
    for (int index = 0; index < platform->action_key_counts[TT_ACTION_FPS]; ++index) {
        if (platform->action_keys[TT_ACTION_FPS][index] == key) {
            platform->fps_toggle_requested = true;
            return;
        }
    }
}

static void tt_cursor_position_callback(GLFWwindow *window, double x, double y) {
    TTPlatform *platform = glfwGetWindowUserPointer(window);
    if (!platform || !platform->mouse_captured) return;
    if (platform->mouse_initialized) {
        platform->mouse_delta_x += x - platform->mouse_x;
        platform->mouse_delta_y += y - platform->mouse_y;
    }
    platform->mouse_x = x;
    platform->mouse_y = y;
    platform->mouse_initialized = true;
}

static int tt_god_mode_sequence_step(int index, unsigned int codepoint) {
    static const char phrase[] = "itstantrum";
    if (codepoint > 127 || index < 0 || index >= (int)sizeof(phrase) - 1) return 0;
    char character = (char)tolower((unsigned char)codepoint);
    if (character == phrase[index]) {
        index++;
        if (phrase[index] == '\0') return -1;
    } else {
        index = character == phrase[0] ? 1 : 0;
    }
    return index;
}

static void tt_character_callback(GLFWwindow *window, unsigned int codepoint) {
    TTPlatform *platform = glfwGetWindowUserPointer(window);
    if (!platform) return;
    if (platform->replay_library_open) {
        if (platform->replay_text_edit && codepoint >= 32)
            tt_replay_event(platform, (int)codepoint);
        return;
    }
    bool was_in_sequence = platform->god_mode_sequence_index > 0;
    int next = tt_god_mode_sequence_step(platform->god_mode_sequence_index, codepoint);
    if (was_in_sequence) {
        if (codepoint >= 'a' && codepoint <= 'z')
            platform->typed_letter_mask |= 1u << (codepoint - 'a');
        else if (codepoint >= 'A' && codepoint <= 'Z')
            platform->typed_letter_mask |= 1u << (codepoint - 'A');
    }
    if (next < 0) {
        platform->god_mode_toggle_requested = true;
        next = 0;
    }
    platform->god_mode_sequence_index = next;
}

static const char *tt_platform_last_error(void) { return tt_platform_error; }

static bool tt_pause_overlay_visible(double wall_time) {
    return fmod(wall_time * 60.0, 128.0) < 64.0;
}

static void tt_platform_set_status(TTPlatform *platform, int score,
                                   int remaining_time_ms, int hits, int zone,
                                   int speed, int rank, int rank_remaining,
                                   int next_extend_score, int time_change_ticks,
                                   int time_change_seconds,
                                   bool game_over, bool paused, bool god_mode) {
    if (!platform || !platform->window)
        return;
    char title[160];
    int seconds = remaining_time_ms > 0 ? (remaining_time_ms + 999) / 1000 : 0;
    snprintf(title, sizeof(title),
             "Torus Trooper  |  LEVEL %d  |  SCORE %d  |  TIME %d:%02d  |  %d KM/H  |  STAGE PROG %d  |  BOSS DIST %d  |  HITS %d%s%s",
             zone, score, seconds / 60, seconds % 60, speed, rank, rank_remaining, hits,
             game_over ? "  |  GAME OVER" : (paused ? "  |  PAUSED" : ""),
             god_mode ? "  |  GODMODE" : "");
    glfwSetWindowTitle(platform->window, title);
    platform->hud_score = score;
    platform->hud_remaining_time_ms = remaining_time_ms;
    platform->hud_hits = hits;
    platform->hud_zone = zone;
    platform->hud_state = (paused ? TT_HUD_PAUSED : 0) | (game_over ? TT_HUD_GAME_OVER : 0);
    platform->hud_speed = speed;
    platform->hud_rank = rank;
    platform->hud_rank_remaining = rank_remaining;
    platform->hud_next_extend_score = next_extend_score;
    platform->hud_time_change_ticks = time_change_ticks;
    platform->hud_time_change_seconds = time_change_seconds;
}

static void tt_platform_set_title_grade_info(TTPlatform *platform, int grade,
                                              int level, int max_level,
                                              int high_score,
                                              int high_score_start_level,
                                              int high_score_end_level) {
    if (!platform || grade < 0 || grade > 2) return;
    platform->title_levels[grade] = level;
    platform->title_max_levels[grade] = max_level;
    platform->title_high_scores[grade] = high_score;
    platform->title_high_score_start_levels[grade] = high_score_start_level;
    platform->title_high_score_end_levels[grade] = high_score_end_level;
}

static void tt_platform_set_title_status(TTPlatform *platform, int grade, int level,
                                         int max_level, int high_score,
                                         int high_score_start_level,
                                         int high_score_end_level, bool has_replay,
                                         int active_menu_item, int volume_percent,
                                         int help_page, bool god_mode,
                                         bool settings_open, int settings_item,
                                         int antialiasing_samples,
                                         int near_blur_percent,
                                         int near_fade_percent,
                                         int rear_track_blend_percent,
                                         int track_draw_distance,
                                         int wire_draw_distance,
                                         int border_draw_distance,
                                         int player_shot_distance,
                                         int fps_limit) {
    if (!platform || !platform->window) return;
    const char *names[] = {"NORMAL", "HARD", "EXTREME"};
    if (grade < 0 || grade > 2) grade = 0;
    char title[256];
    snprintf(title, sizeof(title),
             "Torus Trooper  |  %s  |  START LEVEL %d/%d  |  VOLUME %d%%  |  AA %dX  |  PANEL %d  |  WIRE %d  |  BORDER %d  |  BEST %d (LV %d-%d)  |  FIRE/START TO START%s%s",
             names[grade], level, max_level, volume_percent, antialiasing_samples,
             track_draw_distance, wire_draw_distance, border_draw_distance,
             high_score, high_score_start_level,
             high_score_end_level,
             has_replay ? "  |  CHARGE TO REPLAY" : "",
             god_mode ? "  |  GODMODE" : "");
    glfwSetWindowTitle(platform->window, title);
    platform->hud_score = high_score;
    platform->hud_remaining_time_ms = active_menu_item;
    platform->hud_hits = level;
    platform->hud_zone = grade + 1;
    platform->hud_state = TT_HUD_TITLE | (has_replay ? TT_HUD_HAS_REPLAY : 0) |
                          (god_mode ? TT_HUD_GOD_MODE : 0) |
                          (settings_open ? TT_HUD_SETTINGS : 0);
    platform->hud_speed = max_level;
    platform->hud_rank = high_score_start_level;
    platform->hud_rank_remaining = settings_open ? fps_limit : high_score_end_level;
    platform->hud_next_extend_score = volume_percent;
    platform->hud_time_change_ticks = volume_percent;
    platform->hud_time_change_seconds = help_page;
    platform->title_antialiasing_samples = antialiasing_samples;
    platform->title_near_blur_percent = near_blur_percent;
    platform->title_near_fade_percent = near_fade_percent;
    platform->title_rear_track_blend_percent = rear_track_blend_percent;
    platform->title_track_draw_distance = track_draw_distance;
    platform->title_wire_draw_distance = wire_draw_distance;
    platform->title_border_draw_distance = border_draw_distance;
    platform->title_player_shot_distance = player_shot_distance;
    if (settings_open) platform->hud_time_change_seconds = settings_item;
}

static void tt_platform_set_near_camera_blur(TTPlatform *platform,
                                              float strength) {
    if (!platform) return;
    platform->near_camera_blur = strength < 0.0f ? 0.0f
                               : strength > 1.0f ? 1.0f : strength;
}

static void tt_platform_set_near_camera_fade(TTPlatform *platform,
                                              float strength) {
    if (!platform) return;
    platform->near_camera_fade = strength < 0.0f ? 0.0f
                               : strength > 1.0f ? 1.0f : strength;
}

static bool tt_inspect_devices(TTPlatform *platform) {
    uint32_t count = 0;
    VkResult result = vkEnumeratePhysicalDevices(platform->instance, &count, NULL);
    if (result != VK_SUCCESS || !count) {
        tt_set_error("no Vulkan physical devices found");
        return false;
    }
    VkPhysicalDevice *physical_devices = calloc(count, sizeof(*physical_devices));
    if (!physical_devices) {
        tt_set_error("out of memory while enumerating Vulkan devices");
        return false;
    }
    result = vkEnumeratePhysicalDevices(platform->instance, &count, physical_devices);
    if (result != VK_SUCCESS) {
        free(physical_devices);
        tt_set_vk_error("vkEnumeratePhysicalDevices", result);
        return false;
    }
    platform->device_count = count < TT_MAX_DEVICES ? (int)count : TT_MAX_DEVICES;
    platform->selected_device = -1;
    for (int device_index = 0; device_index < platform->device_count; ++device_index) {
        VkPhysicalDevice device = physical_devices[device_index];
        platform->physical_devices[device_index] = device;
        VkPhysicalDeviceProperties properties;
        vkGetPhysicalDeviceProperties(device, &properties);
        TTDeviceInfo *info = &platform->devices[device_index];
        snprintf(info->name, sizeof(info->name), "%s", properties.deviceName);
        info->api_version = properties.apiVersion;
        info->driver_version = properties.driverVersion;
        info->graphics_queue_family = -1;
        info->present_queue_family = -1;
        uint32_t queue_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_count, NULL);
        VkQueueFamilyProperties *queues = calloc(queue_count, sizeof(*queues));
        if (!queues) continue;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_count, queues);
        for (uint32_t queue_index = 0; queue_index < queue_count; ++queue_index) {
            if (info->graphics_queue_family < 0 &&
                (queues[queue_index].queueFlags & VK_QUEUE_GRAPHICS_BIT))
                info->graphics_queue_family = (int)queue_index;
            VkBool32 present_supported = VK_FALSE;
            if (vkGetPhysicalDeviceSurfaceSupportKHR(device, queue_index, platform->surface,
                                                     &present_supported) == VK_SUCCESS &&
                present_supported && info->present_queue_family < 0)
                info->present_queue_family = (int)queue_index;
        }
        free(queues);
        if (platform->selected_device < 0 && info->graphics_queue_family >= 0 &&
            info->present_queue_family >= 0)
            platform->selected_device = device_index;
    }
    free(physical_devices);
    if (platform->selected_device < 0) {
        tt_set_error("no Vulkan device supports both graphics and presentation");
        return false;
    }
    return true;
}

static bool tt_create_device(TTPlatform *platform) {
    TTDeviceInfo *info = &platform->devices[platform->selected_device];
    uint32_t families[2] = {(uint32_t)info->graphics_queue_family,
                            (uint32_t)info->present_queue_family};
    uint32_t unique_count = families[0] == families[1] ? 1 : 2;
    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_infos[2] = {0};
    for (uint32_t i = 0; i < unique_count; ++i) {
        queue_infos[i].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queue_infos[i].queueFamilyIndex = families[i];
        queue_infos[i].queueCount = 1;
        queue_infos[i].pQueuePriorities = &priority;
    }
    const char *extensions[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    VkPhysicalDeviceFeatures available_features = {0};
    vkGetPhysicalDeviceFeatures(platform->physical_devices[platform->selected_device],
                                &available_features);
    VkPhysicalDeviceProperties device_properties = {0};
    vkGetPhysicalDeviceProperties(platform->physical_devices[platform->selected_device],
                                  &device_properties);
    VkSampleCountFlags sample_support =
        device_properties.limits.framebufferColorSampleCounts &
        device_properties.limits.framebufferDepthSampleCounts;
    int requested_samples = platform->requested_sample_count;
    platform->sample_count = (VkSampleCountFlagBits)tt_antialiasing_sample_count(
        requested_samples, sample_support);
    VkPhysicalDeviceFeatures enabled_features = {0};
    enabled_features.wideLines = available_features.wideLines;
    platform->wide_lines = available_features.wideLines == VK_TRUE;
    platform->max_line_width = device_properties.limits.lineWidthRange[1];
    VkDeviceCreateInfo create_info = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = unique_count,
        .pQueueCreateInfos = queue_infos,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = extensions,
        .pEnabledFeatures = &enabled_features,
    };
    VkResult result = vkCreateDevice(platform->physical_devices[platform->selected_device],
                                     &create_info, NULL, &platform->device);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateDevice", result);
        return false;
    }
    volkLoadDevice(platform->device);
    vkGetDeviceQueue(platform->device, families[0], 0, &platform->graphics_queue);
    vkGetDeviceQueue(platform->device, families[1], 0, &platform->present_queue);
    VkCommandPoolCreateInfo pool_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = families[0],
    };
    result = vkCreateCommandPool(platform->device, &pool_info, NULL, &platform->command_pool);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateCommandPool", result);
        return false;
    }
    for (int i = 0; i < TT_FRAMES_IN_FLIGHT; ++i) {
        if (!tt_create_frame_resources(platform, &platform->frames[i]))
            return false;
    }
    return true;
}

static bool tt_create_graphics_pipeline(TTPlatform *platform) {
    TTShaderPair shaders = {0};
    if (!tt_create_shader_pair(platform->device, "shaders/tunnel.vert.spv",
                               "shaders/tunnel.frag.spv", &shaders))
        return false;
    VkResult result;
    bool multisampled = platform->sample_count != VK_SAMPLE_COUNT_1_BIT;
    VkAttachmentDescription attachments[3] = {
        {
            .format = platform->swapchain_format,
            .samples = platform->sample_count,
            .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = multisampled ? VK_ATTACHMENT_STORE_OP_DONT_CARE
                                    : VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = multisampled ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
                                        : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        },
        {
            .format = platform->depth_format,
            .samples = platform->sample_count,
            .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        },
        {
            .format = platform->swapchain_format,
            .samples = VK_SAMPLE_COUNT_1_BIT,
            .loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        },
    };
    VkAttachmentReference color_reference = {
        .attachment = 0,
        .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    VkAttachmentReference depth_reference = {
        .attachment = 1,
        .layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    };
    VkAttachmentReference resolve_reference = {
        .attachment = 2,
        .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    VkSubpassDescription subpass = {
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_reference,
        .pResolveAttachments = multisampled ? &resolve_reference : NULL,
        .pDepthStencilAttachment = &depth_reference,
    };
    VkSubpassDependency dependencies[2] = {
        {
            .srcSubpass = VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                             VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        },
        {
            .srcSubpass = 0,
            .dstSubpass = VK_SUBPASS_EXTERNAL,
            .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .dstAccessMask = VK_ACCESS_SHADER_READ_BIT,
        },
    };
    VkRenderPassCreateInfo render_pass_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = multisampled ? 3 : 2,
        .pAttachments = attachments,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 2,
        .pDependencies = dependencies,
    };
    result = vkCreateRenderPass(platform->device, &render_pass_info, NULL,
                                &platform->render_pass);
    if (result != VK_SUCCESS) {
        tt_destroy_shader_pair(platform->device, &shaders);
        tt_set_vk_error("vkCreateRenderPass", result);
        return false;
    }
    VkPushConstantRange push_range = {
        .stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = sizeof(TTPushConstants),
    };
    VkPipelineLayoutCreateInfo layout_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_range,
    };
    result = vkCreatePipelineLayout(platform->device, &layout_info, NULL,
                                    &platform->pipeline_layout);
    VkPipelineShaderStageCreateInfo stages[2] = {
        {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_VERTEX_BIT,
            .module = shaders.vertex,
            .pName = "main",
        },
        {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = shaders.fragment,
            .pName = "main",
        },
    };
    VkVertexInputBindingDescription tunnel_binding = {
        .binding = 0, .stride = sizeof(float) * 4,
        .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
    };
    VkVertexInputAttributeDescription tunnel_attributes[2] = {
        {.location = 0, .binding = 0, .format = VK_FORMAT_R32G32B32_SFLOAT, .offset = 0},
        {.location = 1, .binding = 0, .format = VK_FORMAT_R32_SFLOAT, .offset = sizeof(float) * 3},
    };
    VkPipelineVertexInputStateCreateInfo vertex_input = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &tunnel_binding,
        .vertexAttributeDescriptionCount = 2,
        .pVertexAttributeDescriptions = tunnel_attributes,
    };
    VkPipelineInputAssemblyStateCreateInfo input_assembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
    };
    VkPipelineViewportStateCreateInfo viewport_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };
    VkPipelineRasterizationStateCreateInfo rasterization = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL,
        .cullMode = VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_CLOCKWISE,
        .lineWidth = 1.0f,
    };
    VkPipelineMultisampleStateCreateInfo multisample = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = platform->sample_count,
        // tunnel.frag tapers distant wire coverage below one pixel. With
        // multisampling, alpha-to-coverage turns that value into actual sample
        // coverage instead of a stack of equally wide translucent lines.
        .alphaToCoverageEnable =
            platform->sample_count != VK_SAMPLE_COUNT_1_BIT ? VK_TRUE : VK_FALSE,
    };
    VkPipelineDepthStencilStateCreateInfo depth_stencil = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = VK_TRUE,
        .depthWriteEnable = VK_TRUE,
        .depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL,
    };
    VkPipelineColorBlendAttachmentState blend_attachment = {
        // Alpha-to-coverage supplies fractional width for multisampled lines.
        // Use ordinary alpha blending only for the 1x fallback; applying both
        // would attenuate the same line twice.
        .blendEnable =
            platform->sample_count == VK_SAMPLE_COUNT_1_BIT ? VK_TRUE : VK_FALSE,
        .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .alphaBlendOp = VK_BLEND_OP_ADD,
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                          VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    };
    VkPipelineColorBlendStateCreateInfo blend = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &blend_attachment,
    };
    VkDynamicState dynamic_states[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR,
                                       VK_DYNAMIC_STATE_LINE_WIDTH};
    VkPipelineDynamicStateCreateInfo dynamic = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = 3,
        .pDynamicStates = dynamic_states,
    };
    VkGraphicsPipelineCreateInfo pipeline_info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = stages,
        .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterization,
        .pMultisampleState = &multisample,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &blend,
        .pDynamicState = &dynamic,
        .layout = platform->pipeline_layout,
        .renderPass = platform->render_pass,
        .subpass = 0,
    };
    if (result == VK_SUCCESS)
        result = vkCreateGraphicsPipelines(platform->device, VK_NULL_HANDLE, 1,
                                           &pipeline_info, NULL, &platform->pipeline);
    tt_destroy_shader_pair(platform->device, &shaders);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateGraphicsPipelines", result);
        return false;
    }
    return true;
}

static bool tt_create_tunnel_fill_pipeline(TTPlatform *platform) {
    TTShaderPair shaders = {0};
    if (!tt_create_shader_pair(platform->device, "shaders/tunnel_fill.vert.spv",
                               "shaders/tunnel_fill.frag.spv", &shaders))
        return false;
    VkPipelineShaderStageCreateInfo stages[2] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = shaders.vertex, .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = shaders.fragment, .pName = "main"},
    };
    VkVertexInputBindingDescription binding = {
        .binding = 0, .stride = sizeof(float) * 7,
        .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
    };
    VkVertexInputAttributeDescription attributes[2] = {
        {.location = 0, .binding = 0, .format = VK_FORMAT_R32G32B32_SFLOAT, .offset = 0},
        {.location = 1, .binding = 0, .format = VK_FORMAT_R32G32B32A32_SFLOAT,
         .offset = sizeof(float) * 3},
    };
    VkPipelineVertexInputStateCreateInfo vertex_input = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1, .pVertexBindingDescriptions = &binding,
        .vertexAttributeDescriptionCount = 2, .pVertexAttributeDescriptions = attributes,
    };
    VkPipelineInputAssemblyStateCreateInfo assembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };
    VkPipelineViewportStateCreateInfo viewport = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1, .scissorCount = 1,
    };
    VkPipelineRasterizationStateCreateInfo raster = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_CLOCKWISE, .lineWidth = 1.0f,
    };
    VkPipelineMultisampleStateCreateInfo multisample = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = platform->sample_count,
    };
    VkPipelineDepthStencilStateCreateInfo depth_stencil = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = VK_TRUE,
        .depthWriteEnable = VK_TRUE,
        .depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL,
    };
    VkPipelineColorBlendAttachmentState attachment = {
        .blendEnable = VK_TRUE,
        .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .alphaBlendOp = VK_BLEND_OP_ADD,
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                          VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    };
    VkPipelineColorBlendStateCreateInfo blend = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1, .pAttachments = &attachment,
    };
    VkDynamicState states[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = 2, .pDynamicStates = states,
    };
    VkGraphicsPipelineCreateInfo info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2, .pStages = stages, .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &assembly, .pViewportState = &viewport,
        .pRasterizationState = &raster, .pMultisampleState = &multisample,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &blend, .pDynamicState = &dynamic,
        .layout = platform->pipeline_layout, .renderPass = platform->render_pass,
    };
    VkResult result = vkCreateGraphicsPipelines(platform->device, VK_NULL_HANDLE, 1,
                                                &info, NULL,
                                                &platform->tunnel_fill_pipeline);
    tt_destroy_shader_pair(platform->device, &shaders);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateGraphicsPipelines(tunnel fill)", result);
        return false;
    }
    return true;
}

static bool tt_create_ship_pipeline(TTPlatform *platform) {
    TTShaderPair shaders = {0};
    if (!tt_create_shader_pair(platform->device, "shaders/ship.vert.spv",
                               "shaders/ship.frag.spv", &shaders))
        return false;
    VkPipelineShaderStageCreateInfo stages[2] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = shaders.vertex,
         .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = shaders.fragment,
         .pName = "main"},
    };
    VkVertexInputBindingDescription binding = {
        .binding = 0, .stride = sizeof(float) * 7,
        .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
    };
    VkVertexInputAttributeDescription attributes[2] = {
        {.location = 0, .binding = 0, .format = VK_FORMAT_R32G32B32_SFLOAT,
         .offset = 0},
        {.location = 1, .binding = 0, .format = VK_FORMAT_R32G32B32A32_SFLOAT,
         .offset = sizeof(float) * 3},
    };
    VkPipelineVertexInputStateCreateInfo vertex_input = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &binding,
        .vertexAttributeDescriptionCount = 2,
        .pVertexAttributeDescriptions = attributes,
    };
    VkPipelineInputAssemblyStateCreateInfo assembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };
    VkPipelineViewportStateCreateInfo viewport = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1, .scissorCount = 1,
    };
    VkPipelineRasterizationStateCreateInfo raster = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_CLOCKWISE, .lineWidth = 1.0f,
    };
    VkPipelineMultisampleStateCreateInfo multisample = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = platform->sample_count,
    };
    VkPipelineDepthStencilStateCreateInfo depth_stencil = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = VK_TRUE,
        // Solid hulls occlude their rear faces and attached exhaust. Their
        // small alpha margin softens edges without adding the track color.
        .depthWriteEnable = VK_TRUE,
        .depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL,
    };
    VkPipelineColorBlendAttachmentState attachment = {
        .blendEnable = VK_TRUE,
        .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .alphaBlendOp = VK_BLEND_OP_ADD,
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                          VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    };
    VkPipelineColorBlendStateCreateInfo blend = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1, .pAttachments = &attachment,
    };
    VkDynamicState states[] = {VK_DYNAMIC_STATE_VIEWPORT,
                               VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = 2, .pDynamicStates = states,
    };
    VkGraphicsPipelineCreateInfo info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2, .pStages = stages,
        .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &assembly, .pViewportState = &viewport,
        .pRasterizationState = &raster, .pMultisampleState = &multisample,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &blend, .pDynamicState = &dynamic,
        .layout = platform->pipeline_layout, .renderPass = platform->render_pass,
    };
    VkResult result = vkCreateGraphicsPipelines(platform->device,
                                                VK_NULL_HANDLE, 1, &info, NULL,
                                                &platform->ship_pipeline);
    tt_destroy_shader_pair(platform->device, &shaders);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateGraphicsPipelines(ships)", result);
        return false;
    }
    return true;
}

static bool tt_create_bullet_pipeline(TTPlatform *platform) {
    TTShaderPair shaders = {0};
    if (!tt_create_shader_pair(platform->device, "shaders/bullet.vert.spv",
                               "shaders/bullet.frag.spv", &shaders))
        return false;
    VkPipelineShaderStageCreateInfo stages[2] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = shaders.vertex, .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = shaders.fragment, .pName = "main"},
    };
    VkVertexInputBindingDescription binding = {
        .binding = 0, .stride = sizeof(float) * 16, .inputRate = VK_VERTEX_INPUT_RATE_INSTANCE,
    };
    VkVertexInputAttributeDescription attributes[4] = {
        {.location = 0, .binding = 0, .format = VK_FORMAT_R32G32B32A32_SFLOAT,
         .offset = 0},
        {.location = 1, .binding = 0, .format = VK_FORMAT_R32G32B32A32_SFLOAT,
         .offset = sizeof(float) * 4},
        {.location = 2, .binding = 0, .format = VK_FORMAT_R32G32B32A32_SFLOAT,
         .offset = sizeof(float) * 8},
        {.location = 3, .binding = 0, .format = VK_FORMAT_R32G32B32A32_SFLOAT,
         .offset = sizeof(float) * 12},
    };
    VkPipelineVertexInputStateCreateInfo vertex_input = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1, .pVertexBindingDescriptions = &binding,
        .vertexAttributeDescriptionCount = 4, .pVertexAttributeDescriptions = attributes,
    };
    VkPipelineInputAssemblyStateCreateInfo assembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };
    VkPipelineViewportStateCreateInfo viewport = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1, .scissorCount = 1,
    };
    VkPipelineRasterizationStateCreateInfo raster = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_CLOCKWISE, .lineWidth = 1.0f,
    };
    VkPipelineMultisampleStateCreateInfo multisample = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = platform->sample_count,
    };
    VkPipelineDepthStencilStateCreateInfo depth_stencil = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = VK_TRUE,
        .depthWriteEnable = VK_FALSE,
        .depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL,
    };
    VkPipelineColorBlendAttachmentState attachment = {
        .blendEnable = VK_TRUE,
        .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = VK_BLEND_FACTOR_ONE,
        .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
        .alphaBlendOp = VK_BLEND_OP_ADD,
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                          VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    };
    VkPipelineColorBlendStateCreateInfo blend = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1, .pAttachments = &attachment,
    };
    VkDynamicState states[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = 2, .pDynamicStates = states,
    };
    VkGraphicsPipelineCreateInfo info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2, .pStages = stages, .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &assembly, .pViewportState = &viewport,
        .pRasterizationState = &raster, .pMultisampleState = &multisample,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &blend, .pDynamicState = &dynamic,
        .layout = platform->pipeline_layout, .renderPass = platform->render_pass,
    };
    VkResult result = vkCreateGraphicsPipelines(platform->device, VK_NULL_HANDLE, 1,
                                                &info, NULL, &platform->bullet_pipeline);
    if (result != VK_SUCCESS) {
        tt_destroy_shader_pair(platform->device, &shaders);
        tt_set_vk_error("vkCreateGraphicsPipelines(bullets)", result);
        return false;
    }
    // Solid projectiles need to darken a pale background. Keep the original
    // additive pipeline for flames, sparks and fragments.
    attachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    attachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    result = vkCreateGraphicsPipelines(platform->device, VK_NULL_HANDLE, 1,
                                       &info, NULL, &platform->bullet_opacity_pipeline);
    if (result != VK_SUCCESS) {
        tt_destroy_shader_pair(platform->device, &shaders);
        tt_set_vk_error("vkCreateGraphicsPipelines(projectile opacity)", result);
        return false;
    }
    attachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE;
    attachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    // Multiplier notices are HUD information. Render their trailing instance
    // range after post-processing, without depth, so accessibility blur/fade
    // and rear-track blending cannot soften or occlude the list.
    multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    depth_stencil.depthTestEnable = VK_FALSE;
    info.renderPass = platform->post_render_pass;
    result = vkCreateGraphicsPipelines(platform->device, VK_NULL_HANDLE, 1,
                                       &info, NULL,
                                       &platform->bullet_overlay_pipeline);
    tt_destroy_shader_pair(platform->device, &shaders);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateGraphicsPipelines(multiplier overlay)", result);
        return false;
    }
    return true;
}

static bool tt_create_post_pipeline(TTPlatform *platform) {
    VkAttachmentDescription attachment = {
        .format = platform->swapchain_format,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };
    VkAttachmentReference color_reference = {
        .attachment = 0,
        .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    VkSubpassDescription subpass = {
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_reference,
    };
    VkSubpassDependency dependencies[2] = {
        {
            .srcSubpass = VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        },
        {
            .srcSubpass = 0,
            .dstSubpass = VK_SUBPASS_EXTERNAL,
            .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
            .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        },
    };
    VkRenderPassCreateInfo render_pass_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 2,
        .pDependencies = dependencies,
    };
    VkResult result = vkCreateRenderPass(platform->device, &render_pass_info, NULL,
                                         &platform->post_render_pass);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateRenderPass(post process)", result);
        return false;
    }

    VkDescriptorSetLayoutBinding binding = {
        .binding = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
    };
    VkDescriptorSetLayoutCreateInfo descriptor_layout_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &binding,
    };
    result = vkCreateDescriptorSetLayout(platform->device, &descriptor_layout_info,
                                         NULL, &platform->post_descriptor_layout);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateDescriptorSetLayout(post process)", result);
        return false;
    }
    VkPushConstantRange push_range = {
        .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = sizeof(TTPostPushConstants),
    };
    VkPipelineLayoutCreateInfo pipeline_layout_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &platform->post_descriptor_layout,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_range,
    };
    result = vkCreatePipelineLayout(platform->device, &pipeline_layout_info, NULL,
                                    &platform->post_pipeline_layout);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreatePipelineLayout(post process)", result);
        return false;
    }
    VkSamplerCreateInfo sampler_info = {
        .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = VK_FILTER_LINEAR,
        .minFilter = VK_FILTER_LINEAR,
        .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .maxLod = 0.0f,
    };
    result = vkCreateSampler(platform->device, &sampler_info, NULL,
                             &platform->post_sampler);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateSampler(post process)", result);
        return false;
    }
    VkDescriptorPoolSize pool_size = {
        .type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = platform->swapchain_image_count,
    };
    VkDescriptorPoolCreateInfo pool_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = platform->swapchain_image_count,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
    };
    result = vkCreateDescriptorPool(platform->device, &pool_info, NULL,
                                    &platform->post_descriptor_pool);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateDescriptorPool(post process)", result);
        return false;
    }
    platform->post_descriptor_sets = calloc(platform->swapchain_image_count,
                                            sizeof(VkDescriptorSet));
    VkDescriptorSetLayout *layouts = calloc(platform->swapchain_image_count,
                                            sizeof(VkDescriptorSetLayout));
    if (!platform->post_descriptor_sets || !layouts) {
        free(layouts);
        tt_set_error("out of memory while creating post-process descriptors");
        return false;
    }
    for (uint32_t index = 0; index < platform->swapchain_image_count; ++index)
        layouts[index] = platform->post_descriptor_layout;
    VkDescriptorSetAllocateInfo allocation_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = platform->post_descriptor_pool,
        .descriptorSetCount = platform->swapchain_image_count,
        .pSetLayouts = layouts,
    };
    result = vkAllocateDescriptorSets(platform->device, &allocation_info,
                                      platform->post_descriptor_sets);
    free(layouts);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkAllocateDescriptorSets(post process)", result);
        return false;
    }
    for (uint32_t index = 0; index < platform->swapchain_image_count; ++index) {
        VkDescriptorImageInfo image_info = {
            .sampler = platform->post_sampler,
            .imageView = platform->scene_views[index],
            .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        };
        VkWriteDescriptorSet write = {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = platform->post_descriptor_sets[index],
            .dstBinding = 0,
            .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &image_info,
        };
        vkUpdateDescriptorSets(platform->device, 1, &write, 0, NULL);
    }

    TTShaderPair shaders = {0};
    if (!tt_create_shader_pair(platform->device, "shaders/post.vert.spv",
                               "shaders/post.frag.spv", &shaders))
        return false;
    VkPipelineShaderStageCreateInfo stages[2] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = shaders.vertex, .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = shaders.fragment, .pName = "main"},
    };
    VkPipelineVertexInputStateCreateInfo vertex_input = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };
    VkPipelineInputAssemblyStateCreateInfo assembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };
    VkPipelineViewportStateCreateInfo viewport = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1, .scissorCount = 1,
    };
    VkPipelineRasterizationStateCreateInfo raster = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0f,
    };
    VkPipelineMultisampleStateCreateInfo multisample = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
    };
    VkPipelineColorBlendAttachmentState color_attachment = {
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                          VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    };
    VkPipelineColorBlendStateCreateInfo blend = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1, .pAttachments = &color_attachment,
    };
    VkDynamicState states[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = 2, .pDynamicStates = states,
    };
    VkGraphicsPipelineCreateInfo pipeline_info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2, .pStages = stages, .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &assembly, .pViewportState = &viewport,
        .pRasterizationState = &raster, .pMultisampleState = &multisample,
        .pColorBlendState = &blend, .pDynamicState = &dynamic,
        .layout = platform->post_pipeline_layout,
        .renderPass = platform->post_render_pass,
    };
    result = vkCreateGraphicsPipelines(platform->device, VK_NULL_HANDLE, 1,
                                       &pipeline_info, NULL,
                                       &platform->post_pipeline);
    tt_destroy_shader_pair(platform->device, &shaders);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateGraphicsPipelines(post process)", result);
        return false;
    }
    return true;
}

static bool tt_create_hud_pipeline(TTPlatform *platform) {
    TTShaderPair shaders = {0};
    if (!tt_create_shader_pair(platform->device, "shaders/hud.vert.spv",
                               "shaders/hud.frag.spv", &shaders))
        return false;
    VkPipelineShaderStageCreateInfo stages[2] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = shaders.vertex, .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = shaders.fragment, .pName = "main"},
    };
    VkPipelineVertexInputStateCreateInfo vertex_input = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };
    VkPipelineInputAssemblyStateCreateInfo assembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };
    VkPipelineViewportStateCreateInfo viewport = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1, .scissorCount = 1,
    };
    VkPipelineRasterizationStateCreateInfo raster = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL, .cullMode = VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_CLOCKWISE, .lineWidth = 1.0f,
    };
    VkPipelineMultisampleStateCreateInfo multisample = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
    };
    VkPipelineDepthStencilStateCreateInfo depth_stencil = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = VK_FALSE,
        .depthWriteEnable = VK_FALSE,
    };
    VkPipelineColorBlendAttachmentState attachment = {
        .blendEnable = VK_TRUE,
        .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .alphaBlendOp = VK_BLEND_OP_ADD,
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                          VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    };
    VkPipelineColorBlendStateCreateInfo blend = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1, .pAttachments = &attachment,
    };
    VkDynamicState states[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = 2, .pDynamicStates = states,
    };
    VkGraphicsPipelineCreateInfo info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2, .pStages = stages, .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &assembly, .pViewportState = &viewport,
        .pRasterizationState = &raster, .pMultisampleState = &multisample,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &blend, .pDynamicState = &dynamic,
        .layout = platform->pipeline_layout, .renderPass = platform->post_render_pass,
    };
    VkResult result = vkCreateGraphicsPipelines(platform->device, VK_NULL_HANDLE, 1,
                                                &info, NULL, &platform->hud_pipeline);
    tt_destroy_shader_pair(platform->device, &shaders);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateGraphicsPipelines(hud)", result);
        return false;
    }
    return true;
}

static void tt_destroy_loading_resources(TTPlatform *platform) {
    if (!platform || !platform->device) return;
    if (platform->loading_framebuffers) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->loading_framebuffers[i])
                vkDestroyFramebuffer(platform->device,
                                     platform->loading_framebuffers[i], NULL);
    }
    free(platform->loading_framebuffers);
    platform->loading_framebuffers = NULL;
    if (platform->loading_render_pass)
        vkDestroyRenderPass(platform->device, platform->loading_render_pass, NULL);
    platform->loading_render_pass = VK_NULL_HANDLE;
}

static bool tt_create_loading_resources(TTPlatform *platform) {
    VkAttachmentDescription attachment = {
        .format = platform->swapchain_format,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };
    VkAttachmentReference color_reference = {
        .attachment = 0,
        .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    VkSubpassDescription subpass = {
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_reference,
    };
    VkSubpassDependency dependency = {
        .srcSubpass = VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };
    VkRenderPassCreateInfo render_pass_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };
    VkResult result = vkCreateRenderPass(platform->device, &render_pass_info, NULL,
                                         &platform->loading_render_pass);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateRenderPass(loading)", result);
        return false;
    }
    platform->loading_framebuffers =
        calloc(platform->swapchain_image_count, sizeof(VkFramebuffer));
    if (!platform->loading_framebuffers) {
        tt_set_error("out of memory while creating loading framebuffers");
        return false;
    }
    for (uint32_t i = 0; i < platform->swapchain_image_count; ++i) {
        VkFramebufferCreateInfo framebuffer_info = {
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = platform->loading_render_pass,
            .attachmentCount = 1,
            .pAttachments = &platform->swapchain_views[i],
            .width = platform->swapchain_extent.width,
            .height = platform->swapchain_extent.height,
            .layers = 1,
        };
        result = vkCreateFramebuffer(platform->device, &framebuffer_info, NULL,
                                     &platform->loading_framebuffers[i]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateFramebuffer(loading)", result);
            return false;
        }
    }
    return true;
}

static bool tt_platform_set_loading_progress(TTPlatform *platform, float progress) {
    if (!platform || !platform->window || !platform->loading_render_pass ||
        !platform->loading_framebuffers)
        return true;
    if (progress < 0.0f) progress = 0.0f;
    if (progress > 1.0f) progress = 1.0f;
    glfwPollEvents();
    if (platform->startup_cancel_requested ||
        glfwWindowShouldClose(platform->window) ||
        glfwGetKey(platform->window, GLFW_KEY_ESCAPE) == GLFW_PRESS) {
        tt_set_error("startup cancelled");
        return false;
    }
    char title[96];
    snprintf(title, sizeof(title), "Torus Trooper  |  LOADING %d%%",
             (int)(progress * 100.0f + 0.5f));
    glfwSetWindowTitle(platform->window, title);

    uint32_t frame_index = platform->frame_index;
    TTFrameResources *frame = &platform->frames[frame_index];
    VkResult result = vkWaitForFences(platform->device, 1, &frame->in_flight,
                                      VK_TRUE, UINT64_MAX);
    uint32_t image_index = 0;
    if (result == VK_SUCCESS)
        result = vkAcquireNextImageKHR(platform->device, platform->swapchain,
                                       UINT64_MAX, frame->image_available,
                                       VK_NULL_HANDLE, &image_index);
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR)
        return true;
    if (result != VK_SUCCESS) {
        tt_set_vk_error("loading frame acquire", result);
        return false;
    }
    VkCommandBuffer command = frame->command;
    result = vkResetCommandBuffer(command, 0);
    VkCommandBufferBeginInfo begin_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    if (result == VK_SUCCESS) result = vkBeginCommandBuffer(command, &begin_info);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("loading command begin", result);
        return false;
    }
    VkClearValue background = tt_background_navy;
    VkRenderPassBeginInfo render_pass_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = platform->loading_render_pass,
        .framebuffer = platform->loading_framebuffers[image_index],
        .renderArea = {{0, 0}, platform->swapchain_extent},
        .clearValueCount = 1,
        .pClearValues = &background,
    };
    vkCmdBeginRenderPass(command, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
    uint32_t width = platform->swapchain_extent.width;
    uint32_t height = platform->swapchain_extent.height;
    uint32_t bar_width = width * 3 / 5;
    uint32_t bar_height = height / 36;
    if (bar_width < 1) bar_width = width;
    if (bar_height < 8) bar_height = 8;
    if (bar_height > 28) bar_height = 28;
    if (bar_height > height) bar_height = height;
    uint32_t bar_x = (width - bar_width) / 2;
    uint32_t bar_y = (height - bar_height) / 2;
    VkClearAttachment bar = {
        .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
        .colorAttachment = 0,
        .clearValue = tt_loading_bar_slate,
    };
    VkClearRect rect = {
        .rect = {{(int32_t)bar_x, (int32_t)bar_y}, {bar_width, bar_height}},
        .baseArrayLayer = 0,
        .layerCount = 1,
    };
    vkCmdClearAttachments(command, 1, &bar, 1, &rect);
    uint32_t filled_width = (uint32_t)((float)bar_width * progress);
    if (filled_width > 0) {
        bar.clearValue = tt_loading_progress_cyan;
        rect.rect.extent.width = filled_width;
        vkCmdClearAttachments(command, 1, &bar, 1, &rect);
    }
    vkCmdEndRenderPass(command);
    result = vkEndCommandBuffer(command);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("loading command end", result);
        return false;
    }
    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit_info = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &frame->image_available,
        .pWaitDstStageMask = &wait_stage,
        .commandBufferCount = 1,
        .pCommandBuffers = &command,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &platform->render_finished[image_index],
    };
    result = vkResetFences(platform->device, 1, &frame->in_flight);
    if (result == VK_SUCCESS)
        result = vkQueueSubmit(platform->graphics_queue, 1, &submit_info,
                               frame->in_flight);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("loading queue submit", result);
        return false;
    }
    VkPresentInfoKHR present_info = {
        .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &platform->render_finished[image_index],
        .swapchainCount = 1,
        .pSwapchains = &platform->swapchain,
        .pImageIndices = &image_index,
    };
    result = vkQueuePresentKHR(platform->present_queue, &present_info);
    if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR &&
        result != VK_ERROR_OUT_OF_DATE_KHR) {
        tt_set_vk_error("loading queue present", result);
        return false;
    }
    platform->frame_index = (frame_index + 1) % TT_FRAMES_IN_FLIGHT;
    glfwPollEvents();
    return true;
}

static void tt_platform_reset_frame_timing(TTPlatform *platform) {
    if (!platform) return;
    platform->fps_sample_frames = 0;
    platform->fps_sample_time = glfwGetTime();
    platform->display_fps = 0;
    platform->next_frame_deadline = 0.0;
}

static void tt_platform_finish_loading(TTPlatform *platform) {
    if (!platform) return;
    if (platform->loading_render_pass) {
        (void)tt_platform_set_loading_progress(platform, 1.0f);
        vkDeviceWaitIdle(platform->device);
        tt_destroy_loading_resources(platform);
    }
    platform->startup_complete = true;
    /* Loading and first-scene construction are not rendered frames. Begin the
       HUD sample at the handoff so their wall time cannot appear as 1-2 FPS. */
    tt_platform_reset_frame_timing(platform);
    if (platform->window) glfwSetWindowTitle(platform->window, "Torus Trooper");
}

static void tt_destroy_swapchain(TTPlatform *platform) {
    if (!platform->device) return;
    tt_destroy_loading_resources(platform);
    free(platform->swapchain_images);
    if (platform->render_finished) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->render_finished[i])
                vkDestroySemaphore(platform->device,
                                   platform->render_finished[i], NULL);
    }
    if (platform->framebuffers) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->framebuffers[i])
                vkDestroyFramebuffer(platform->device, platform->framebuffers[i], NULL);
    }
    if (platform->post_framebuffers) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->post_framebuffers[i])
                vkDestroyFramebuffer(platform->device,
                                     platform->post_framebuffers[i], NULL);
    }
    if (platform->post_descriptor_pool)
        vkDestroyDescriptorPool(platform->device,
                                platform->post_descriptor_pool, NULL);
    if (platform->depth_views) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->depth_views[i])
                vkDestroyImageView(platform->device, platform->depth_views[i], NULL);
    }
    if (platform->depth_images) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->depth_images[i])
                vkDestroyImage(platform->device, platform->depth_images[i], NULL);
    }
    if (platform->depth_memories) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->depth_memories[i])
                vkFreeMemory(platform->device, platform->depth_memories[i], NULL);
    }
    if (platform->multisample_views) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->multisample_views[i])
                vkDestroyImageView(platform->device,
                                   platform->multisample_views[i], NULL);
    }
    if (platform->multisample_images) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->multisample_images[i])
                vkDestroyImage(platform->device,
                               platform->multisample_images[i], NULL);
    }
    if (platform->multisample_memories) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->multisample_memories[i])
                vkFreeMemory(platform->device,
                             platform->multisample_memories[i], NULL);
    }
    if (platform->scene_views) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->scene_views[i])
                vkDestroyImageView(platform->device, platform->scene_views[i], NULL);
    }
    if (platform->scene_images) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->scene_images[i])
                vkDestroyImage(platform->device, platform->scene_images[i], NULL);
    }
    if (platform->scene_memories) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->scene_memories[i])
                vkFreeMemory(platform->device, platform->scene_memories[i], NULL);
    }
    if (platform->pipeline) vkDestroyPipeline(platform->device, platform->pipeline, NULL);
    if (platform->tunnel_fill_pipeline)
        vkDestroyPipeline(platform->device, platform->tunnel_fill_pipeline, NULL);
    if (platform->ship_pipeline)
        vkDestroyPipeline(platform->device, platform->ship_pipeline, NULL);
    if (platform->bullet_pipeline)
        vkDestroyPipeline(platform->device, platform->bullet_pipeline, NULL);
    if (platform->bullet_opacity_pipeline)
        vkDestroyPipeline(platform->device, platform->bullet_opacity_pipeline, NULL);
    if (platform->bullet_overlay_pipeline)
        vkDestroyPipeline(platform->device, platform->bullet_overlay_pipeline, NULL);
    if (platform->hud_pipeline)
        vkDestroyPipeline(platform->device, platform->hud_pipeline, NULL);
    if (platform->post_pipeline)
        vkDestroyPipeline(platform->device, platform->post_pipeline, NULL);
    if (platform->post_sampler)
        vkDestroySampler(platform->device, platform->post_sampler, NULL);
    if (platform->post_pipeline_layout)
        vkDestroyPipelineLayout(platform->device,
                                platform->post_pipeline_layout, NULL);
    if (platform->post_descriptor_layout)
        vkDestroyDescriptorSetLayout(platform->device,
                                     platform->post_descriptor_layout, NULL);
    if (platform->pipeline_layout)
        vkDestroyPipelineLayout(platform->device, platform->pipeline_layout, NULL);
    if (platform->render_pass)
        vkDestroyRenderPass(platform->device, platform->render_pass, NULL);
    if (platform->post_render_pass)
        vkDestroyRenderPass(platform->device, platform->post_render_pass, NULL);
    if (platform->swapchain_views) {
        for (uint32_t i = 0; i < platform->swapchain_image_count; ++i)
            if (platform->swapchain_views[i])
                vkDestroyImageView(platform->device, platform->swapchain_views[i], NULL);
    }
    free(platform->framebuffers);
    free(platform->post_framebuffers);
    free(platform->swapchain_views);
    free(platform->depth_images);
    free(platform->depth_memories);
    free(platform->depth_views);
    free(platform->multisample_images);
    free(platform->multisample_memories);
    free(platform->multisample_views);
    free(platform->scene_images);
    free(platform->scene_memories);
    free(platform->scene_views);
    free(platform->post_descriptor_sets);
    free(platform->image_initialized);
    free(platform->render_finished);
    platform->swapchain_images = NULL;
    platform->swapchain_views = NULL;
    platform->framebuffers = NULL;
    platform->post_framebuffers = NULL;
    platform->depth_images = NULL;
    platform->depth_memories = NULL;
    platform->depth_views = NULL;
    platform->multisample_images = NULL;
    platform->multisample_memories = NULL;
    platform->multisample_views = NULL;
    platform->scene_images = NULL;
    platform->scene_memories = NULL;
    platform->scene_views = NULL;
    platform->post_descriptor_sets = NULL;
    platform->image_initialized = NULL;
    platform->render_finished = NULL;
    platform->swapchain_image_count = 0;
    platform->pipeline = VK_NULL_HANDLE;
    platform->tunnel_fill_pipeline = VK_NULL_HANDLE;
    platform->ship_pipeline = VK_NULL_HANDLE;
    platform->bullet_pipeline = VK_NULL_HANDLE;
    platform->bullet_opacity_pipeline = VK_NULL_HANDLE;
    platform->bullet_overlay_pipeline = VK_NULL_HANDLE;
    platform->hud_pipeline = VK_NULL_HANDLE;
    platform->post_pipeline = VK_NULL_HANDLE;
    platform->post_sampler = VK_NULL_HANDLE;
    platform->post_descriptor_pool = VK_NULL_HANDLE;
    platform->post_descriptor_layout = VK_NULL_HANDLE;
    platform->post_pipeline_layout = VK_NULL_HANDLE;
    platform->pipeline_layout = VK_NULL_HANDLE;
    platform->render_pass = VK_NULL_HANDLE;
    platform->post_render_pass = VK_NULL_HANDLE;
    if (platform->swapchain) vkDestroySwapchainKHR(platform->device, platform->swapchain, NULL);
    platform->swapchain = VK_NULL_HANDLE;
}

static bool tt_create_swapchain(TTPlatform *platform) {
    VkPhysicalDevice physical = platform->physical_devices[platform->selected_device];
    VkSurfaceCapabilitiesKHR capabilities;
    VkResult result = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical, platform->surface,
                                                                &capabilities);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkGetPhysicalDeviceSurfaceCapabilitiesKHR", result);
        return false;
    }
    uint32_t format_count = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(physical, platform->surface, &format_count, NULL);
    if (!format_count) {
        tt_set_error("Vulkan surface has no supported formats");
        return false;
    }
    VkSurfaceFormatKHR *formats = calloc(format_count, sizeof(*formats));
    vkGetPhysicalDeviceSurfaceFormatsKHR(physical, platform->surface, &format_count, formats);
    VkSurfaceFormatKHR format = formats[0];
    for (uint32_t i = 0; i < format_count; ++i) {
        if (formats[i].format == VK_FORMAT_B8G8R8A8_SRGB &&
            formats[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            format = formats[i];
            break;
        }
    }
    free(formats);
    VkExtent2D extent = capabilities.currentExtent;
    if (extent.width == UINT32_MAX) {
        int width = 0, height = 0;
        glfwGetFramebufferSize(platform->window, &width, &height);
        extent.width = (uint32_t)width;
        extent.height = (uint32_t)height;
        if (extent.width < capabilities.minImageExtent.width) extent.width = capabilities.minImageExtent.width;
        if (extent.width > capabilities.maxImageExtent.width) extent.width = capabilities.maxImageExtent.width;
        if (extent.height < capabilities.minImageExtent.height) extent.height = capabilities.minImageExtent.height;
        if (extent.height > capabilities.maxImageExtent.height) extent.height = capabilities.maxImageExtent.height;
    }
    uint32_t image_count = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount && image_count > capabilities.maxImageCount)
        image_count = capabilities.maxImageCount;
    TTDeviceInfo *device_info = &platform->devices[platform->selected_device];
    uint32_t queue_indices[] = {(uint32_t)device_info->graphics_queue_family,
                                (uint32_t)device_info->present_queue_family};
    VkPresentModeKHR present_mode = VK_PRESENT_MODE_FIFO_KHR;
    uint32_t present_mode_count = 0;
    vkGetPhysicalDeviceSurfacePresentModesKHR(physical, platform->surface,
                                              &present_mode_count, NULL);
    /* DISPLAY is paced explicitly to the monitor containing the window. Use a
     * non-blocking presentation mode for it as well as UNLOCKED; FIFO on X11
     * can otherwise synchronize a secondary-window swapchain to the primary
     * monitor's refresh rate. */
    if (platform->fps_limit <= 0 && present_mode_count > 0) {
        VkPresentModeKHR *present_modes =
            calloc(present_mode_count, sizeof(*present_modes));
        if (present_modes) {
            vkGetPhysicalDeviceSurfacePresentModesKHR(physical, platform->surface,
                                                      &present_mode_count,
                                                      present_modes);
            for (uint32_t i = 0; i < present_mode_count; ++i)
                if (present_modes[i] == VK_PRESENT_MODE_IMMEDIATE_KHR)
                    present_mode = VK_PRESENT_MODE_IMMEDIATE_KHR;
            for (uint32_t i = 0; i < present_mode_count; ++i)
                if (present_modes[i] == VK_PRESENT_MODE_MAILBOX_KHR) {
                    present_mode = VK_PRESENT_MODE_MAILBOX_KHR;
                    break;
                }
            free(present_modes);
        }
    }
    VkSwapchainCreateInfoKHR create_info = {
        .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = platform->surface,
        .minImageCount = image_count,
        .imageFormat = format.format,
        .imageColorSpace = format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = VK_TRUE,
    };
    if (queue_indices[0] != queue_indices[1]) {
        create_info.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
        create_info.queueFamilyIndexCount = 2;
        create_info.pQueueFamilyIndices = queue_indices;
    } else {
        create_info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    }
    result = vkCreateSwapchainKHR(platform->device, &create_info, NULL, &platform->swapchain);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateSwapchainKHR", result);
        return false;
    }
    platform->swapchain_format = format.format;
    platform->present_mode = present_mode;
    platform->swapchain_extent = extent;
    vkGetSwapchainImagesKHR(platform->device, platform->swapchain,
                            &platform->swapchain_image_count, NULL);
    platform->swapchain_images = calloc(platform->swapchain_image_count, sizeof(VkImage));
    platform->image_initialized = calloc(platform->swapchain_image_count, sizeof(bool));
    platform->render_finished = calloc(platform->swapchain_image_count,
                                       sizeof(VkSemaphore));
    if (!platform->swapchain_images || !platform->image_initialized ||
        !platform->render_finished) {
        tt_set_error("out of memory while creating swapchain image state");
        return false;
    }
    result = vkGetSwapchainImagesKHR(platform->device, platform->swapchain,
                                     &platform->swapchain_image_count,
                                     platform->swapchain_images);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkGetSwapchainImagesKHR", result);
        return false;
    }
    VkSemaphoreCreateInfo semaphore_info = {
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    for (uint32_t i = 0; i < platform->swapchain_image_count; ++i) {
        result = vkCreateSemaphore(platform->device, &semaphore_info, NULL,
                                   &platform->render_finished[i]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateSemaphore(render finished)", result);
            return false;
        }
    }
    platform->swapchain_views = calloc(platform->swapchain_image_count, sizeof(VkImageView));
    platform->framebuffers = calloc(platform->swapchain_image_count, sizeof(VkFramebuffer));
    platform->post_framebuffers = calloc(platform->swapchain_image_count,
                                         sizeof(VkFramebuffer));
    if (!platform->swapchain_views || !platform->framebuffers ||
        !platform->post_framebuffers) {
        tt_set_error("out of memory while creating swapchain views");
        return false;
    }
    for (uint32_t i = 0; i < platform->swapchain_image_count; ++i) {
        VkImageViewCreateInfo view_info = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = platform->swapchain_images[i],
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = platform->swapchain_format,
            .components = {VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
                           VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY},
            .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
        };
        result = vkCreateImageView(platform->device, &view_info, NULL,
                                   &platform->swapchain_views[i]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateImageView", result);
            return false;
        }
    }
    if (!platform->startup_complete) {
        if (!tt_create_loading_resources(platform) ||
            !tt_platform_set_loading_progress(platform, 0.18f))
            return false;
    }
    if (!tt_create_scene_targets(platform) ||
        !tt_create_multisample_targets(platform) ||
        !tt_create_depth_targets(platform))
        return false;
    if (!platform->startup_complete &&
        !tt_platform_set_loading_progress(platform, 0.30f))
        return false;
    if (!tt_create_graphics_pipeline(platform))
        return false;
    if (!platform->startup_complete &&
        !tt_platform_set_loading_progress(platform, 0.48f))
        return false;
    if (!tt_create_tunnel_fill_pipeline(platform))
        return false;
    if (!platform->startup_complete &&
        !tt_platform_set_loading_progress(platform, 0.58f))
        return false;
    if (!tt_create_ship_pipeline(platform))
        return false;
    if (!platform->startup_complete &&
        !tt_platform_set_loading_progress(platform, 0.68f))
        return false;
    if (!tt_create_post_pipeline(platform))
        return false;
    if (!platform->startup_complete &&
        !tt_platform_set_loading_progress(platform, 0.78f))
        return false;
    if (!tt_create_bullet_pipeline(platform) || !tt_create_hud_pipeline(platform))
        return false;
    if (!platform->startup_complete &&
        !tt_platform_set_loading_progress(platform, 0.88f))
        return false;
    for (uint32_t i = 0; i < platform->swapchain_image_count; ++i) {
        bool multisampled = platform->sample_count != VK_SAMPLE_COUNT_1_BIT;
        VkImageView attachments[3] = {
            multisampled ? platform->multisample_views[i]
                         : platform->scene_views[i],
            platform->depth_views[i],
            platform->scene_views[i],
        };
        VkFramebufferCreateInfo framebuffer_info = {
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = platform->render_pass,
            .attachmentCount = multisampled ? 3 : 2,
            .pAttachments = attachments,
            .width = platform->swapchain_extent.width,
            .height = platform->swapchain_extent.height,
            .layers = 1,
        };
        result = vkCreateFramebuffer(platform->device, &framebuffer_info, NULL,
                                     &platform->framebuffers[i]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateFramebuffer", result);
            return false;
        }
        VkFramebufferCreateInfo post_framebuffer_info = {
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = platform->post_render_pass,
            .attachmentCount = 1,
            .pAttachments = &platform->swapchain_views[i],
            .width = platform->swapchain_extent.width,
            .height = platform->swapchain_extent.height,
            .layers = 1,
        };
        result = vkCreateFramebuffer(platform->device, &post_framebuffer_info, NULL,
                                     &platform->post_framebuffers[i]);
        if (result != VK_SUCCESS) {
            tt_set_vk_error("vkCreateFramebuffer(post process)", result);
            return false;
        }
    }
    if (!platform->startup_complete &&
        !tt_platform_set_loading_progress(platform, 0.92f))
        return false;
    return true;
}

static bool tt_recreate_swapchain(TTPlatform *platform) {
    int width = 0, height = 0;
    glfwGetFramebufferSize(platform->window, &width, &height);
    while (!width || !height) {
        glfwWaitEvents();
        glfwGetFramebufferSize(platform->window, &width, &height);
    }
    vkDeviceWaitIdle(platform->device);
    tt_destroy_swapchain(platform);
    return tt_create_swapchain(platform);
}

static int tt_platform_antialiasing_samples(TTPlatform *platform) {
    return platform ? (int)platform->sample_count : 1;
}

static bool tt_platform_antialiasing_supported(TTPlatform *platform, int samples) {
    if (!platform || !platform->device) return samples == 1;
    VkPhysicalDeviceProperties properties = {0};
    vkGetPhysicalDeviceProperties(platform->physical_devices[platform->selected_device],
                                  &properties);
    VkSampleCountFlags support = properties.limits.framebufferColorSampleCounts &
                                 properties.limits.framebufferDepthSampleCounts;
    return (support & (VkSampleCountFlags)samples) != 0;
}

static int tt_platform_set_antialiasing(TTPlatform *platform, int requested_samples) {
    if (!platform || !platform->device) return 0;
    VkPhysicalDeviceProperties properties = {0};
    vkGetPhysicalDeviceProperties(platform->physical_devices[platform->selected_device],
                                  &properties);
    VkSampleCountFlags support = properties.limits.framebufferColorSampleCounts &
                                 properties.limits.framebufferDepthSampleCounts;
    VkSampleCountFlagBits desired = (VkSampleCountFlagBits)
        tt_antialiasing_sample_count(requested_samples, support);
    if (desired == platform->sample_count) return (int)desired;

    VkSampleCountFlagBits previous = platform->sample_count;
    platform->requested_sample_count = requested_samples;
    vkDeviceWaitIdle(platform->device);
    tt_destroy_swapchain(platform);
    platform->sample_count = desired;
    if (tt_create_swapchain(platform)) return (int)platform->sample_count;

    /* Preserve a usable renderer if a driver rejects an advertised mode. */
    tt_destroy_swapchain(platform);
    platform->sample_count = previous;
    platform->requested_sample_count = (int)previous;
    if (!tt_create_swapchain(platform)) return 0;
    return (int)previous;
}

static bool tt_platform_set_fps_limit(TTPlatform *platform, int fps_limit) {
    if (!platform || !platform->device) return false;
    if (fps_limit != -1 && fps_limit != 0 && fps_limit != 60) {
        tt_set_error("FPS limit must be 60, display, or unlocked");
        return false;
    }
    if (platform->fps_limit == fps_limit) return true;
    int previous = platform->fps_limit;
    platform->fps_limit = fps_limit;
    platform->next_frame_deadline = 0.0;
    if ((previous <= 0) == (fps_limit <= 0)) return true;
    if (tt_recreate_swapchain(platform)) return true;
    platform->fps_limit = previous;
    return tt_recreate_swapchain(platform);
}

static GLFWmonitor *tt_monitor_for_window(GLFWwindow *window) {
    int window_x = 0, window_y = 0, window_width = 0, window_height = 0;
    glfwGetWindowPos(window, &window_x, &window_y);
    glfwGetWindowSize(window, &window_width, &window_height);
    int monitor_count = 0;
    GLFWmonitor **monitors = glfwGetMonitors(&monitor_count);
    GLFWmonitor *best = glfwGetPrimaryMonitor();
    int best_area = -1;
    for (int index = 0; monitors && index < monitor_count; ++index) {
        int monitor_x = 0, monitor_y = 0;
        glfwGetMonitorPos(monitors[index], &monitor_x, &monitor_y);
        const GLFWvidmode *mode = glfwGetVideoMode(monitors[index]);
        if (!mode) continue;
        int overlap_left = window_x > monitor_x ? window_x : monitor_x;
        int overlap_top = window_y > monitor_y ? window_y : monitor_y;
        int window_right = window_x + window_width;
        int monitor_right = monitor_x + mode->width;
        int overlap_right = window_right < monitor_right ? window_right : monitor_right;
        int window_bottom = window_y + window_height;
        int monitor_bottom = monitor_y + mode->height;
        int overlap_bottom = window_bottom < monitor_bottom ? window_bottom : monitor_bottom;
        int overlap_width = overlap_right > overlap_left ? overlap_right - overlap_left : 0;
        int overlap_height = overlap_bottom > overlap_top ? overlap_bottom - overlap_top : 0;
        int area = overlap_width * overlap_height;
        if (area > best_area) {
            best = monitors[index];
            best_area = area;
        }
    }
    return best;
}

static int tt_target_frame_rate(int fps_limit, int display_refresh_rate) {
    if (fps_limit == -1)
        return display_refresh_rate > 0 ? display_refresh_rate : 60;
    if (fps_limit == 60) return fps_limit;
    return 0;
}

static bool tt_platform_toggle_borderless_fullscreen(TTPlatform *platform) {
    if (!platform || !platform->window) return false;
    if (platform->borderless_fullscreen) {
        glfwSetWindowMonitor(platform->window, NULL,
                             platform->windowed_x, platform->windowed_y,
                             platform->windowed_width, platform->windowed_height,
                             GLFW_DONT_CARE);
        glfwSetWindowAttrib(platform->window, GLFW_DECORATED, GLFW_TRUE);
        glfwSetWindowPos(platform->window, platform->windowed_x,
                         platform->windowed_y);
        glfwSetWindowSize(platform->window, platform->windowed_width,
                          platform->windowed_height);
        platform->borderless_fullscreen = false;
        return true;
    }
    GLFWmonitor *monitor = tt_monitor_for_window(platform->window);
    if (!monitor) {
        tt_set_error("could not find a monitor for borderless fullscreen");
        return false;
    }
    const GLFWvidmode *mode = glfwGetVideoMode(monitor);
    if (!mode) {
        tt_set_error("could not read the fullscreen monitor video mode");
        return false;
    }
    glfwGetWindowPos(platform->window, &platform->windowed_x,
                     &platform->windowed_y);
    glfwGetWindowSize(platform->window, &platform->windowed_width,
                      &platform->windowed_height);
    int monitor_x = 0, monitor_y = 0;
    glfwGetMonitorPos(monitor, &monitor_x, &monitor_y);
    // Attach at the monitor's current mode. GLFW provides a borderless surface
    // that covers system panels without requesting a resolution change.
    glfwSetWindowAttrib(platform->window, GLFW_DECORATED, GLFW_FALSE);
    glfwSetWindowMonitor(platform->window, monitor, monitor_x, monitor_y,
                         mode->width, mode->height, mode->refreshRate);
    platform->borderless_fullscreen = true;
    return true;
}

static TTPlatform *tt_platform_create(int width, int height, const char *title,
                                      int fullscreen, int sample_count,
                                      int fps_limit) {
    tt_platform_error[0] = '\0';
    glfwSetErrorCallback(tt_glfw_error_callback);
    if (!glfwInit()) {
        if (!tt_platform_error[0]) tt_set_error("could not initialize GLFW");
        return NULL;
    }
    if (!glfwVulkanSupported()) {
        tt_set_error("GLFW could not find a Vulkan loader");
        glfwTerminate();
        return NULL;
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);
    // Borderless fullscreen must remain visible when another monitor receives
    // focus; GLFW's fullscreen default otherwise minimizes it automatically.
    glfwWindowHint(GLFW_AUTO_ICONIFY, GLFW_FALSE);
    TTPlatform *platform = calloc(1, sizeof(*platform));
    if (!platform) {
        tt_set_error("out of memory while creating platform state");
        glfwTerminate();
        return NULL;
    }
    platform->hud_visible = true;
    platform->replay_view_ratio = 1.0f;
    platform->requested_sample_count = sample_count;
    platform->sample_count = VK_SAMPLE_COUNT_1_BIT;
    platform->fps_limit = fps_limit;
    platform->window = glfwCreateWindow(width, height, title, NULL, NULL);
    if (!platform->window) {
        if (!tt_platform_error[0]) tt_set_error("could not create a GLFW window");
        tt_platform_destroy(platform);
        return NULL;
    }
    glfwSetWindowUserPointer(platform->window, platform);
    glfwSetWindowTitle(platform->window, "Torus Trooper  |  LOADING 0%");
    glfwShowWindow(platform->window);
    glfwPollEvents();
    glfwSetCharCallback(platform->window, tt_character_callback);
    glfwSetKeyCallback(platform->window, tt_key_callback);
    glfwSetCursorPosCallback(platform->window, tt_cursor_position_callback);
    if (fullscreen && !tt_platform_toggle_borderless_fullscreen(platform)) {
        tt_platform_destroy(platform);
        return NULL;
    }
    uint32_t extension_count = 0;
    const char **extensions = glfwGetRequiredInstanceExtensions(&extension_count);
    if (!extensions || !extension_count) {
        tt_set_error("GLFW returned no Vulkan instance extensions");
        tt_platform_destroy(platform);
        return NULL;
    }
    VkApplicationInfo application_info = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Torus Trooper",
        .applicationVersion = VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "Torus V Engine",
        .engineVersion = VK_MAKE_VERSION(0, 1, 0),
        // The allocator uses Vulkan 1.1's core memory-requirements query to
        // honor driver requests for dedicated buffer allocations.
        .apiVersion = VK_API_VERSION_1_1,
    };
    VkInstanceCreateInfo instance_info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &application_info,
        .enabledExtensionCount = extension_count,
        .ppEnabledExtensionNames = extensions,
    };
    VkResult result = vkCreateInstance(&instance_info, NULL, &platform->instance);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkCreateInstance", result);
        tt_platform_destroy(platform);
        return NULL;
    }
    volkLoadInstance(platform->instance);
    result = glfwCreateWindowSurface(platform->instance, platform->window, NULL,
                                     &platform->surface);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("glfwCreateWindowSurface", result);
        tt_platform_destroy(platform);
        return NULL;
    }
    if (!tt_inspect_devices(platform) || !tt_create_device(platform) ||
        !tt_create_swapchain(platform)) {
        tt_platform_destroy(platform);
        return NULL;
    }
    platform->start_time = glfwGetTime();
    return platform;
}

static float tt_title_replay_viewport_fraction(float ratio) {
    float expanded = ratio * 2.4f;
    if (expanded < 0.0f) expanded = 0.0f;
    if (expanded > 1.0f) expanded = 1.0f;
    return 0.80f + expanded * 0.20f;
}

static float tt_title_replay_viewport_x_fraction(float ratio) {
    float width_fraction = tt_title_replay_viewport_fraction(ratio);
    return (1.0f - width_fraction) * 0.1f;
}

static float tt_course_line_width_for_extent(uint32_t height, bool wide_lines,
                                              float max_line_width) {
    if (!wide_lines || height == 0 || max_line_width < 1.0f) return 1.0f;
    float width = (float)height / 480.0f;
    if (width < 1.0f) width = 1.0f;
    if (width > max_line_width) width = max_line_width;
    return width;
}

static int tt_pack_title_pair(int first, int second) {
    if (first < 0) first = 0;
    if (first > 999) first = 999;
    if (second < 0) second = 0;
    if (second > 999) second = 999;
    return first + second * 1000;
}

static int tt_title_rank_remaining_value(int hud_state, int settings_value,
                                         int extreme_high_score) {
    return (hud_state & TT_HUD_SETTINGS) != 0 ? settings_value : extreme_high_score;
}

static void tt_store_int_bits(float *destination, int value) {
    memcpy(destination, &value, sizeof(value));
}

static void tt_draw_hud_text_ranges(VkCommandBuffer command) {
    vkCmdDraw(command, TT_HUD_DIGIT_VERTEX_COUNT, 1,
              TT_HUD_DIGIT_VERTEX_OFFSET, 0);
    vkCmdDraw(command, TT_HUD_TITLE_WORDMARK_VERTEX_COUNT, 1,
              TT_HUD_TITLE_WORDMARK_VERTEX_OFFSET, 0);
    vkCmdDraw(command,
              TT_HUD_HELP_VERTEX_OFFSET - TT_HUD_TITLE_GRADE_LABEL_VERTEX_OFFSET,
              1, TT_HUD_TITLE_GRADE_LABEL_VERTEX_OFFSET, 0);
    vkCmdDraw(command, TT_HUD_HELP_VERTEX_COUNT - TT_HUD_HELP_DIAGRAM_VERTEX_COUNT,
              1, TT_HUD_HELP_VERTEX_OFFSET + TT_HUD_HELP_DIAGRAM_VERTEX_COUNT, 0);
}

static void tt_draw_replay_library(TTPlatform *platform, VkCommandBuffer command,
                                   float aspect) {
    TTPushConstants push = {0};
    push.state = TT_HUD_REPLAY_LIBRARY;
    push.aspect = aspect;
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS, platform->hud_pipeline);
    vkCmdPushConstants(command, platform->pipeline_layout,
                       VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                       0, sizeof(push), &push);
    vkCmdDraw(command, 6, 1, TT_HUD_VERTEX_COUNT, 0);
    float pitch = fminf(0.018f, 1.86f * aspect / (64.0f * 6.0f));
    pitch = fmaxf(2.0f, floorf(pitch * (float)platform->swapchain_extent.height * 0.5f))
            * 2.0f / (float)platform->swapchain_extent.height;
    for (int row = 0; row < platform->replay_line_count; ++row) {
        if (row == platform->replay_selected_line) {
            push.time = -0.91f + (float)row * 0.076f;
            for (int part = 2; part <= 3; ++part) {
                push.remaining_time_ms = part;
                vkCmdPushConstants(command, platform->pipeline_layout,
                                   VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                                   0, sizeof(push), &push);
                vkCmdDraw(command, 6, 1, TT_HUD_VERTEX_COUNT, 0);
            }
        }
        for (int chunk = 0; chunk < 2; ++chunk) {
            push.time = -0.91f + (float)row * 0.076f;
            push.view_angle = -0.94f + (float)(chunk * 32 * 6) * pitch / aspect;
            push.hits = row;
            push.zone = row == platform->replay_selected_line ? 1 : 0;
            push.remaining_time_ms = 1;
            push.ship_surface_radius = pitch;
            memset((char *)&push + 32, 0, 40);
            memcpy((char *)&push + 32, platform->replay_lines[row] + chunk * 32, 32);
            vkCmdPushConstants(command, platform->pipeline_layout,
                               VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                               0, sizeof(push), &push);
            vkCmdDraw(command, 32 * 35 * 6, 1, TT_HUD_VERTEX_COUNT + 6, 0);
        }
    }
}

static bool tt_draw_frame(TTPlatform *platform) {
    uint32_t frame_index = platform->frame_index;
    TTFrameResources *frame = &platform->frames[frame_index];
    if (!tt_prepare_frame_upload(platform)) return false;
    VkResult result;
    uint32_t image_index = 0;
    result = vkAcquireNextImageKHR(platform->device, platform->swapchain, UINT64_MAX,
                                   frame->image_available, VK_NULL_HANDLE, &image_index);
    if (result == VK_ERROR_OUT_OF_DATE_KHR) return tt_recreate_swapchain(platform);
    if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR) {
        tt_set_vk_error("vkAcquireNextImageKHR", result);
        return false;
    }
    VkCommandBuffer command = frame->command;
    result = vkResetCommandBuffer(command, 0);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkResetCommandBuffer", result);
        return false;
    }
    VkCommandBufferBeginInfo begin_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    result = vkBeginCommandBuffer(command, &begin_info);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkBeginCommandBuffer", result);
        return false;
    }
    VkClearValue clears[3] = {
        tt_background_navy,
        {.depthStencil = {1.0f, 0}},
        tt_opaque_black,
    };
    VkRenderPassBeginInfo render_pass_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = platform->render_pass,
        .framebuffer = platform->framebuffers[image_index],
        .renderArea = {{0, 0}, platform->swapchain_extent},
        .clearValueCount = platform->sample_count == VK_SAMPLE_COUNT_1_BIT ? 2 : 3,
        .pClearValues = clears,
    };
    vkCmdBeginRenderPass(command, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
    float surface_width = (float)platform->swapchain_extent.width;
    VkViewport viewport = {
        .x = surface_width * tt_title_replay_viewport_x_fraction(platform->replay_view_ratio),
        .y = 0.0f,
        .width = surface_width * tt_title_replay_viewport_fraction(platform->replay_view_ratio),
        .height = (float)platform->swapchain_extent.height,
        .minDepth = 0.0f,
        .maxDepth = 1.0f,
    };
    VkRect2D scissor = {{0, 0}, platform->swapchain_extent};
    vkCmdSetViewport(command, 0, 1, &viewport);
    vkCmdSetScissor(command, 0, 1, &scissor);
    int packed_fps = platform->display_fps < 0 ? 0
                   : platform->display_fps > TT_HUD_FPS_MAX_DISPLAY
                       ? TT_HUD_FPS_MAX_DISPLAY : platform->display_fps;
    int display_hud_state = platform->hud_state |
                            (platform->fps_visible ? TT_HUD_FPS_VISIBLE : 0) |
                            (packed_fps << TT_HUD_FPS_SHIFT);
    if ((display_hud_state & TT_HUD_PAUSED) != 0 &&
        tt_pause_overlay_visible(glfwGetTime()))
        display_hud_state |= TT_HUD_PAUSE_OVERLAY;
    TTPushConstants push = {
        (float)((platform->paused ? platform->paused_time : glfwGetTime()) - platform->start_time),
        (float)platform->swapchain_extent.width / (float)platform->swapchain_extent.height,
        platform->view_angle,
        platform->hud_score,
        platform->hud_remaining_time_ms,
        platform->hud_hits,
        platform->hud_zone,
        display_hud_state,
        {platform->tunnel_color[0], platform->tunnel_color[1],
         platform->tunnel_color[2], platform->tunnel_color[3]},
        platform->brightness,
        platform->luminosity,
        platform->camera_depth_offset,
        platform->camera_zoom,
        platform->transition_fade,
        platform->hud_speed,
        platform->hud_rank,
        platform->hud_rank_remaining,
        platform->camera_shake_x,
        platform->camera_shake_y,
        platform->camera_3d,
        platform->camera_eye_height,
        platform->camera_look_angle,
        platform->camera_look_depth,
        platform->camera_look_height,
        platform->camera_rotation,
        platform->hud_next_extend_score,
        platform->hud_time_change_ticks,
        platform->hud_time_change_seconds,
        platform->ship_surface_radius,
    };
    vkCmdPushConstants(command, platform->pipeline_layout,
                       VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                       0, sizeof(push), &push);
    VkDeviceSize tunnel_fill_offset =
        frame_index * platform->tunnel_fill_buffer.frame_size;
    if (platform->tunnel_fill_vertex_count) {
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                          platform->tunnel_fill_pipeline);
        vkCmdBindVertexBuffers(command, 0, 1,
                               &platform->tunnel_fill_buffer.handle,
                               &tunnel_fill_offset);
        vkCmdDraw(command, platform->tunnel_fill_vertex_count, 1, 0, 0);
    }
    vkCmdSetLineWidth(command,
                      tt_course_line_width_for_extent(platform->swapchain_extent.height,
                                                      platform->wide_lines,
                                                      platform->max_line_width));
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS, platform->pipeline);
    VkDeviceSize tunnel_offset = frame_index * platform->tunnel_buffer.frame_size;
    vkCmdBindVertexBuffers(command, 0, 1, &platform->tunnel_buffer.handle, &tunnel_offset);
    vkCmdDraw(command, platform->tunnel_vertex_count, 1, 0, 0);
    if (platform->ship_vertex_count) {
        /* Hull shaders do not use animation time. Reuse that slot only for
           this draw, preserving the portable 128-byte push-constant limit. */
        vkCmdPushConstants(command, platform->pipeline_layout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                           0, sizeof(platform->ship_material_seed),
                           &platform->ship_material_seed);
        VkDeviceSize ship_offset =
            frame_index * platform->tunnel_fill_buffer.frame_size +
            TT_MAX_TUNNEL_FILL_VERTICES * sizeof(float) * 7;
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                          platform->ship_pipeline);
        vkCmdBindVertexBuffers(command, 0, 1,
                               &platform->tunnel_fill_buffer.handle,
                               &ship_offset);
        vkCmdDraw(command, platform->ship_vertex_count, 1, 0, 0);
        vkCmdPushConstants(command, platform->pipeline_layout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                           0, sizeof(push.time), &push.time);
    }
    uint32_t world_bullet_count = platform->multiplier_popup_count
        ? platform->multiplier_popup_first : platform->bullet_count;
    if (world_bullet_count) {
        VkDeviceSize offset = frame_index * platform->bullet_buffer.frame_size;
        vkCmdBindVertexBuffers(command, 0, 1, &platform->bullet_buffer.handle, &offset);
        // Preserve the instance stream's draw order, grouping adjacent objects
        // with the same blend mode rather than rearranging translucent effects.
        for (uint32_t first = 0; first < world_bullet_count;) {
            bool opaque = platform->bullet_opacity[first];
            uint32_t end = first + 1;
            while (end < world_bullet_count && platform->bullet_opacity[end] == opaque)
                ++end;
            vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                              opaque ? platform->bullet_opacity_pipeline
                                     : platform->bullet_pipeline);
            vkCmdDraw(command, 6, end - first, 0, first);
            first = end;
        }
    }
    vkCmdEndRenderPass(command);

    VkClearValue post_clear = tt_background_navy;
    VkRenderPassBeginInfo post_render_pass_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = platform->post_render_pass,
        .framebuffer = platform->post_framebuffers[image_index],
        .renderArea = {{0, 0}, platform->swapchain_extent},
        .clearValueCount = 1,
        .pClearValues = &post_clear,
    };
    vkCmdBeginRenderPass(command, &post_render_pass_info,
                         VK_SUBPASS_CONTENTS_INLINE);
    viewport.x = 0.0f;
    viewport.y = 0.0f;
    viewport.width = (float)platform->swapchain_extent.width;
    vkCmdSetViewport(command, 0, 1, &viewport);
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                      platform->post_pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                            platform->post_pipeline_layout, 0, 1,
                            &platform->post_descriptor_sets[image_index],
                            0, NULL);
    float post_ship_radius = 0.24f;
    if (platform->camera_3d < 0.5f) {
        float tunnel_scale = platform->tunnel_color[3];
        float ship_view_depth = (2.2f +
            (platform->ship_render_depth + platform->camera_depth_offset) * 0.55f) *
            tunnel_scale;
        if (ship_view_depth < 0.6f) ship_view_depth = 0.6f;
        post_ship_radius = platform->ship_surface_radius * tunnel_scale /
                           ship_view_depth;
        if (post_ship_radius < 0.12f) post_ship_radius = 0.12f;
        if (post_ship_radius > 0.42f) post_ship_radius = 0.42f;
    }
    TTPostPushConstants post_push = {
        .aspect = (float)platform->swapchain_extent.width /
                  (float)platform->swapchain_extent.height,
        .near_blur = platform->near_camera_blur,
        .ship_radius = post_ship_radius,
        .enabled = (platform->hud_state & TT_HUD_TITLE) == 0 ? 1.0f : 0.0f,
        .near_fade = platform->near_camera_fade,
    };
    vkCmdPushConstants(command, platform->post_pipeline_layout,
                       VK_SHADER_STAGE_FRAGMENT_BIT, 0,
                       sizeof(post_push), &post_push);
    vkCmdDraw(command, 3, 1, 0, 0);

    if (platform->multiplier_popup_count) {
        VkDeviceSize offset = frame_index * platform->bullet_buffer.frame_size;
        vkCmdPushConstants(command, platform->pipeline_layout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                           0, sizeof(push), &push);
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                          platform->bullet_overlay_pipeline);
        vkCmdBindVertexBuffers(command, 0, 1, &platform->bullet_buffer.handle,
                               &offset);
        vkCmdDraw(command, 6, platform->multiplier_popup_count, 0,
                  platform->multiplier_popup_first);
    }

    if (platform->hud_visible && !platform->replay_library_open) {
        TTPushConstants hud_push = push;
        hud_push.luminosity = (float)platform->swapchain_extent.height;
        if ((platform->hud_state & TT_HUD_TITLE) != 0) {
            hud_push.score = platform->title_high_scores[0];
            hud_push.rank = platform->title_high_scores[1];
            /* The settings overlay reuses rank_remaining for its FPS value. */
            hud_push.rank_remaining = tt_title_rank_remaining_value(
                platform->hud_state, hud_push.rank_remaining,
                platform->title_high_scores[2]);
            hud_push.hits = tt_pack_title_pair(platform->title_levels[0],
                                                platform->title_max_levels[0]);
            hud_push.speed = tt_pack_title_pair(platform->title_levels[1],
                                                 platform->title_max_levels[1]);
            hud_push.next_extend_score =
                tt_pack_title_pair(platform->title_levels[2],
                                   platform->title_max_levels[2]);
            int normal_range = tt_pack_title_pair(
                platform->title_high_score_start_levels[0],
                platform->title_high_score_end_levels[0]);
            int hard_range = tt_pack_title_pair(
                platform->title_high_score_start_levels[1],
                platform->title_high_score_end_levels[1]);
            int extreme_range = tt_pack_title_pair(
                platform->title_high_score_start_levels[2],
                platform->title_high_score_end_levels[2]);
            tt_store_int_bits(&hud_push.camera_depth_offset,
                              (platform->hud_state & TT_HUD_SETTINGS) != 0
                                  ? platform->title_player_shot_distance
                                  : normal_range);
            tt_store_int_bits(&hud_push.camera_zoom, hard_range);
            tt_store_int_bits(&hud_push.camera_shake_x, extreme_range);
            hud_push.camera_rotation = (float)platform->title_antialiasing_samples;
            tt_store_int_bits(&hud_push.ship_surface_radius,
                              platform->title_near_blur_percent);
            tt_store_int_bits(&hud_push.camera_shake_y,
                              platform->title_near_fade_percent);
            /* The 128-byte portable push-constant budget is full. Each menu
             * horizon is 0..999, so three ten-bit values share this title-only
             * field; hud.vert unpacks them for separate settings rows. */
            tt_store_int_bits(&hud_push.camera_look_angle,
                              (platform->title_track_draw_distance & 1023) |
                              ((platform->title_wire_draw_distance & 1023) << 10) |
                              ((platform->title_border_draw_distance & 1023) << 20));
            tt_store_int_bits(&hud_push.camera_3d,
                              platform->title_rear_track_blend_percent);
        }
        vkCmdPushConstants(command, platform->pipeline_layout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                           0, sizeof(hud_push), &hud_push);
        viewport.x = 0.0f;
        viewport.width = (float)platform->swapchain_extent.width;
        vkCmdSetViewport(command, 0, 1, &viewport);
        vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                          platform->hud_pipeline);
        // The opaque title mask must complete before text and wireframes draw
        // over it. Separate draws provide that ordering across GPU primitives.
        vkCmdDraw(command, TT_TITLE_MASK_VERTEX_COUNT, 1, 0, 0);
        // The animated torus stays behind settings and selection backings.
        vkCmdDraw(command, TT_HUD_TITLE_TORUS_VERTEX_COUNT, 1,
                  TT_HUD_TITLE_WORDMARK_VERTEX_OFFSET - TT_HUD_TITLE_TORUS_VERTEX_COUNT, 0);
        vkCmdDraw(command, TT_HUD_HELP_DIAGRAM_VERTEX_COUNT, 1,
                  TT_HUD_HELP_VERTEX_OFFSET, 0);
        vkCmdDraw(command, TT_HUD_MENU_SELECTION_VERTEX_COUNT, 1,
                  TT_HUD_VERTEX_COUNT - TT_HUD_MENU_SELECTION_VERTEX_COUNT, 0);

        // Build a dark outline around text-only ranges before the colored pass.
        // Reusing camera_3d as the HUD-only pass marker keeps the portable
        // 128-byte push-constant layout intact. Unlike the signed view angle,
        // its restored value is guaranteed to be zero or one.
        float hud_shadow_marker = -1.0f;
        vkCmdPushConstants(command, platform->pipeline_layout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                           offsetof(TTPushConstants, camera_3d), sizeof(float),
                           &hud_shadow_marker);
        float shadow_pixels = fmaxf(1.0f,
                                    (float)platform->swapchain_extent.height / 720.0f);
        const float outline_directions[8][2] = {
            {-1.0f, -1.0f}, {0.0f, -1.0f}, {1.0f, -1.0f},
            {-1.0f,  0.0f},                 {1.0f,  0.0f},
            {-1.0f,  1.0f}, {0.0f,  1.0f}, {1.0f,  1.0f},
        };
        for (int outline = 0; outline < 8; ++outline) {
            viewport.x = outline_directions[outline][0] * shadow_pixels;
            viewport.y = outline_directions[outline][1] * shadow_pixels;
            vkCmdSetViewport(command, 0, 1, &viewport);
            tt_draw_hud_text_ranges(command);
        }
        vkCmdPushConstants(command, platform->pipeline_layout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                           offsetof(TTPushConstants, camera_3d), sizeof(float),
                           &hud_push.camera_3d);
        viewport.x = 0.0f;
        viewport.y = 0.0f;
        vkCmdSetViewport(command, 0, 1, &viewport);
        vkCmdDraw(command, TT_HUD_DIGIT_VERTEX_COUNT, 1,
                  TT_HUD_DIGIT_VERTEX_OFFSET, 0);
        vkCmdDraw(command, TT_HUD_HELP_VERTEX_OFFSET - TT_HUD_TITLE_WORDMARK_VERTEX_OFFSET,
                  1, TT_HUD_TITLE_WORDMARK_VERTEX_OFFSET, 0);
        vkCmdDraw(command, TT_HUD_HELP_VERTEX_COUNT - TT_HUD_HELP_DIAGRAM_VERTEX_COUNT,
                  1, TT_HUD_HELP_VERTEX_OFFSET + TT_HUD_HELP_DIAGRAM_VERTEX_COUNT, 0);
    }
    if (platform->replay_library_open) {
        viewport.x = viewport.y = 0.0f;
        vkCmdSetViewport(command, 0, 1, &viewport);
        tt_draw_replay_library(platform, command, push.aspect);
    }
    vkCmdEndRenderPass(command);
    result = vkEndCommandBuffer(command);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkEndCommandBuffer", result);
        return false;
    }
    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit_info = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &frame->image_available,
        .pWaitDstStageMask = &wait_stage,
        .commandBufferCount = 1,
        .pCommandBuffers = &command,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &platform->render_finished[image_index],
    };
    result = vkResetFences(platform->device, 1, &frame->in_flight);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkResetFences", result);
        return false;
    }
    result = vkQueueSubmit(platform->graphics_queue, 1, &submit_info, frame->in_flight);
    if (result != VK_SUCCESS) {
        tt_set_vk_error("vkQueueSubmit", result);
        return false;
    }
    platform->upload_frame_ready = false;
    VkPresentInfoKHR present_info = {
        .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &platform->render_finished[image_index],
        .swapchainCount = 1,
        .pSwapchains = &platform->swapchain,
        .pImageIndices = &image_index,
    };
    result = vkQueuePresentKHR(platform->present_queue, &present_info);
    platform->image_initialized[image_index] = true;
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
        if (!tt_recreate_swapchain(platform)) return false;
    } else if (result != VK_SUCCESS) {
        tt_set_vk_error("vkQueuePresentKHR", result);
        return false;
    }
    platform->frame_index = (frame_index + 1) % TT_FRAMES_IN_FLIGHT;
    platform->rendered_frames++;
    return true;
}

static void tt_platform_destroy(TTPlatform *platform) {
    if (!platform) return;
    if (platform->device) vkDeviceWaitIdle(platform->device);
    tt_destroy_swapchain(platform);
    if (platform->device) {
        for (int i = 0; i < TT_FRAMES_IN_FLIGHT; ++i)
            tt_destroy_frame_resources(platform->device, &platform->frames[i]);
        if (platform->command_pool)
            vkDestroyCommandPool(platform->device, platform->command_pool, NULL);
        vkDestroyDevice(platform->device, NULL);
    }
    if (platform->surface && platform->instance)
        vkDestroySurfaceKHR(platform->instance, platform->surface, NULL);
    if (platform->instance) vkDestroyInstance(platform->instance, NULL);
    if (platform->window) glfwDestroyWindow(platform->window);
    free(platform);
    glfwTerminate();
}

static void *tt_platform_physical_device(TTPlatform *platform) {
    if (!platform || platform->selected_device < 0) return NULL;
    return platform->physical_devices[platform->selected_device];
}

static void *tt_platform_device(TTPlatform *platform) {
    return platform ? platform->device : NULL;
}

static uint64_t tt_platform_buffer_frame_size(int slot) {
    switch (slot) {
    case 0: return TT_MAX_RENDER_INSTANCES * sizeof(float) * 16;
    case 1: return TT_MAX_TUNNEL_VERTICES * sizeof(float) * 4;
    case 2: return (TT_MAX_TUNNEL_FILL_VERTICES + TT_MAX_SHIP_VERTICES) *
                   sizeof(float) * 7;
    default: return 0;
    }
}

static uint64_t tt_platform_buffer_size(int slot) {
    return tt_platform_buffer_frame_size(slot) * TT_FRAMES_IN_FLIGHT;
}

static bool tt_platform_attach_mapped_buffer(TTPlatform *platform, int slot,
                                             void *handle, void *mapped,
                                             uint64_t size) {
    uint64_t frame_size = tt_platform_buffer_frame_size(slot);
    if (!platform || !handle || !mapped || !frame_size ||
        size < frame_size * TT_FRAMES_IN_FLIGHT)
        return false;
    TTMappedBuffer *target = NULL;
    switch (slot) {
    case 0: target = &platform->bullet_buffer; break;
    case 1: target = &platform->tunnel_buffer; break;
    case 2: target = &platform->tunnel_fill_buffer; break;
    default: return false;
    }
    target->handle = (VkBuffer)handle;
    target->mapped = mapped;
    target->size = (VkDeviceSize)size;
    target->frame_size = (VkDeviceSize)frame_size;
    return true;
}

static void tt_platform_wait_idle(TTPlatform *platform) {
    if (platform && platform->device)
        vkDeviceWaitIdle(platform->device);
}

static bool tt_platform_poll(TTPlatform *platform) {
    glfwPollEvents();
    // The callback preserves a short tap; polling the configured binding is a
    // fallback for platforms/window managers that do not deliver key callbacks
    // reliably. The edge latch prevents key repeat from toggling every frame.
    bool fullscreen_key_down =
        tt_action_pressed(platform, TT_ACTION_FULLSCREEN);
    bool toggle_fullscreen = platform->fullscreen_toggle_requested ||
        (fullscreen_key_down && !platform->fullscreen_key_was_down);
    platform->fullscreen_key_was_down = fullscreen_key_down;
    if (toggle_fullscreen) {
        platform->fullscreen_toggle_requested = false;
        if (!tt_platform_toggle_borderless_fullscreen(platform)) return false;
        printf("Borderless fullscreen: %s.\n",
               platform->borderless_fullscreen ? "enabled" : "disabled");
        fflush(stdout);
    }
    bool fps_key_down = tt_action_pressed(platform, TT_ACTION_FPS);
    bool toggle_fps = platform->fps_toggle_requested ||
        (fps_key_down && !platform->fps_key_was_down);
    platform->fps_key_was_down = fps_key_down;
    if (toggle_fps) {
        platform->fps_toggle_requested = false;
        platform->fps_visible = !platform->fps_visible;
    }
    if (!tt_draw_frame(platform)) return false;

    double now = glfwGetTime();
    int display_refresh_rate = 0;
    if (platform->fps_limit == -1) {
        GLFWmonitor *monitor = tt_monitor_for_window(platform->window);
        const GLFWvidmode *mode = monitor ? glfwGetVideoMode(monitor) : NULL;
        display_refresh_rate = mode ? mode->refreshRate : 0;
    }
    int target_frame_rate = tt_target_frame_rate(platform->fps_limit,
                                                  display_refresh_rate);
    if (target_frame_rate > 0) {
        double interval = 1.0 / (double)target_frame_rate;
        if (platform->next_frame_deadline <= 0.0 ||
            platform->next_frame_deadline < now - interval)
            platform->next_frame_deadline = now + interval;
        double remaining = platform->next_frame_deadline - now;
        if (remaining > 0.0) glfwWaitEventsTimeout(remaining);
        platform->next_frame_deadline += interval;
        now = glfwGetTime();
    } else {
        platform->next_frame_deadline = 0.0;
    }
    if (platform->fps_sample_time <= 0.0)
        platform->fps_sample_time = now;
    platform->fps_sample_frames++;
    double elapsed = now - platform->fps_sample_time;
    if (elapsed >= 0.5) {
        platform->display_fps = (int)llround((double)platform->fps_sample_frames / elapsed);
        platform->fps_sample_frames = 0;
        platform->fps_sample_time = now;
    }
    return true;
}

static bool tt_instance_uses_opacity(float kind) {
    if (kind >= 64.0f && kind < 80.0f) {
        int index = (int)roundf(kind - 64.0f);
        return index >= 0 && index <= 10;
    }
    return (kind >= 1.0f && kind < 5.5f) ||
           (kind >= 7.0f && kind < 62.5f && !(kind >= 19.5f && kind < 30.0f));
}

static void tt_platform_set_bullets(TTPlatform *platform, const void *positions,
                                    uint32_t count) {
    if (!platform) return;
    if (count > TT_MAX_RENDER_INSTANCES) count = TT_MAX_RENDER_INSTANCES;
    if (!tt_prepare_frame_upload(platform) ||
        !tt_upload_mapped_buffer(&platform->bullet_buffer, platform->frame_index,
                                 positions,
                                 count * sizeof(float) * 16))
        return;
    platform->bullet_count = count;
    platform->multiplier_popup_first = count;
    platform->multiplier_popup_count = 0;
    if (positions) {
        const float *instances = (const float *)positions;
        for (uint32_t i = 0; i < count; ++i)
            platform->bullet_opacity[i] = tt_instance_uses_opacity(instances[i * 16 + 2]);
        while (platform->multiplier_popup_first > 0) {
            uint32_t previous = platform->multiplier_popup_first - 1;
            float kind = instances[previous * 16 + 2];
            if (kind < 19.5f || kind >= 20.5f) break;
            platform->multiplier_popup_first = previous;
            platform->multiplier_popup_count++;
        }
    }
}

static void tt_platform_set_tunnel(TTPlatform *platform, const void *vertices,
                                   uint32_t count) {
    if (!platform) return;
    if (count > TT_MAX_TUNNEL_VERTICES) count = TT_MAX_TUNNEL_VERTICES;
    if (!tt_prepare_frame_upload(platform) ||
        !tt_upload_mapped_buffer(&platform->tunnel_buffer, platform->frame_index,
                                 vertices,
                                 count * sizeof(float) * 4))
        return;
    platform->tunnel_vertex_count = count;
}

static void tt_platform_set_tunnel_fill(TTPlatform *platform, const void *vertices,
                                        uint32_t count) {
    if (!platform) return;
    if (count > TT_MAX_TUNNEL_FILL_VERTICES)
        count = TT_MAX_TUNNEL_FILL_VERTICES;
    if (!tt_prepare_frame_upload(platform) ||
        !tt_upload_mapped_buffer(&platform->tunnel_fill_buffer,
                                 platform->frame_index, vertices,
                                 count * sizeof(float) * 7))
        return;
    platform->tunnel_fill_vertex_count = count;
}

static void tt_platform_set_ship_mesh(TTPlatform *platform, const void *vertices,
                                      uint32_t count) {
    if (!platform) return;
    if (count > TT_MAX_SHIP_VERTICES) count = TT_MAX_SHIP_VERTICES;
    VkDeviceSize offset = TT_MAX_TUNNEL_FILL_VERTICES * sizeof(float) * 7;
    if (!tt_prepare_frame_upload(platform) ||
        !tt_upload_mapped_buffer_at(&platform->tunnel_fill_buffer,
                                    platform->frame_index, offset, vertices,
                                    count * sizeof(float) * 7))
        return;
    platform->ship_vertex_count = count;
}

static void tt_platform_set_ship_material_seed(TTPlatform *platform, uint32_t seed) {
    if (platform) platform->ship_material_seed = seed;
}

static void tt_platform_set_tunnel_color(TTPlatform *platform, float r, float g,
                                         float b) {
    if (!platform) return;
    platform->tunnel_color[0] = r;
    platform->tunnel_color[1] = g;
    platform->tunnel_color[2] = b;
    platform->tunnel_color[3] = 1.0f;
}

static void tt_platform_set_tunnel_scale(TTPlatform *platform, float scale) {
    if (!platform) return;
    platform->tunnel_color[3] = scale < 0.1f ? 0.1f : (scale > 5.0f ? 5.0f : scale);
}

static void tt_platform_set_view_angle(TTPlatform *platform, float angle) {
    if (platform) platform->view_angle = angle;
}

static void tt_platform_set_camera(TTPlatform *platform, float angle,
                                   float depth_offset, float zoom,
                                   float shake_x, float shake_y, bool use_3d,
                                   float eye_height, float look_angle,
                                   float look_depth, float look_height,
                                   float rotation, float ship_surface_radius,
                                   float ship_render_depth) {
    if (!platform) return;
    platform->view_angle = angle;
    platform->camera_depth_offset = depth_offset;
    platform->camera_zoom = zoom > 0.1f ? zoom : 0.1f;
    platform->camera_shake_x = shake_x;
    platform->camera_shake_y = shake_y;
    platform->camera_3d = use_3d ? 1.0f : 0.0f;
    platform->camera_eye_height = eye_height;
    platform->camera_look_angle = look_angle;
    platform->camera_look_depth = look_depth;
    platform->camera_look_height = look_height;
    platform->camera_rotation = rotation;
    platform->ship_surface_radius = ship_surface_radius;
    platform->ship_render_depth = ship_render_depth;
}

static void tt_platform_set_hud_visible(TTPlatform *platform, bool visible) {
    if (platform) platform->hud_visible = visible;
}

static void tt_platform_set_mouse_capture(TTPlatform *platform, bool captured) {
    if (!platform || !platform->window || platform->mouse_captured == captured) return;
    platform->mouse_captured = captured;
    platform->mouse_initialized = false;
    platform->mouse_delta_x = 0.0;
    platform->mouse_delta_y = 0.0;
    platform->calibration_cycle_requested = 0;
    if (glfwRawMouseMotionSupported())
        glfwSetInputMode(platform->window, GLFW_RAW_MOUSE_MOTION,
                         captured ? GLFW_TRUE : GLFW_FALSE);
    glfwSetInputMode(platform->window, GLFW_CURSOR,
                     captured ? GLFW_CURSOR_DISABLED : GLFW_CURSOR_NORMAL);
}

static void tt_platform_take_mouse_delta(TTPlatform *platform, float *x, float *y) {
    if (x) *x = platform ? (float)platform->mouse_delta_x : 0.0f;
    if (y) *y = platform ? (float)platform->mouse_delta_y : 0.0f;
    if (platform) {
        platform->mouse_delta_x = 0.0;
        platform->mouse_delta_y = 0.0;
    }
}

static bool tt_platform_take_calibration_save(TTPlatform *platform) {
    if (!platform || !platform->calibration_save_requested) return false;
    platform->calibration_save_requested = false;
    return true;
}

static bool tt_platform_take_calibration_reload(TTPlatform *platform) {
    if (!platform || !platform->calibration_reload_requested) return false;
    platform->calibration_reload_requested = false;
    return true;
}

static bool tt_platform_take_calibration_reset(TTPlatform *platform) {
    if (!platform || !platform->calibration_reset_requested) return false;
    platform->calibration_reset_requested = false;
    return true;
}

static bool tt_platform_take_calibration_auto_orbit(TTPlatform *platform) {
    if (!platform || !platform->calibration_auto_orbit_requested) return false;
    platform->calibration_auto_orbit_requested = false;
    return true;
}

static int tt_platform_take_calibration_cycle(TTPlatform *platform) {
    if (!platform) return 0;
    int step = platform->calibration_cycle_requested;
    platform->calibration_cycle_requested = 0;
    return step;
}

static void tt_platform_set_window_title(TTPlatform *platform, const char *title) {
    if (platform && platform->window && title) glfwSetWindowTitle(platform->window, title);
}

static void tt_platform_set_transition(TTPlatform *platform, float fade) {
    if (!platform) return;
    platform->transition_fade = fade < 0.0f ? 0.0f : (fade > 1.0f ? 1.0f : fade);
}

static void tt_platform_set_replay_view_ratio(TTPlatform *platform, float ratio) {
    if (!platform) return;
    platform->replay_view_ratio = ratio < 0.0f ? 0.0f : (ratio > 1.0f ? 1.0f : ratio);
}

static void tt_platform_set_display(TTPlatform *platform, float brightness,
                                    float luminosity) {
    if (!platform) return;
    platform->brightness = brightness;
    platform->luminosity = luminosity;
}

static int tt_key_from_name(const char *name) {
    if (!name || !name[0]) return GLFW_KEY_UNKNOWN;
    if (!strcmp(name, "+") || !strcmp(name, "=")) return GLFW_KEY_EQUAL;
    if (!strcmp(name, "-")) return GLFW_KEY_MINUS;
    if (!name[1]) {
        unsigned char character = (unsigned char)name[0];
        if (character >= 'a' && character <= 'z') character -= 'a' - 'A';
        if ((character >= 'A' && character <= 'Z') ||
            (character >= '0' && character <= '9')) return (int)character;
    }
    char normalized[32];
    size_t length = strlen(name);
    if (length >= sizeof(normalized)) return GLFW_KEY_UNKNOWN;
    for (size_t index = 0; index <= length; ++index) {
        unsigned char character = (unsigned char)name[index];
        normalized[index] = (char)(character == '-' || character == ' '
                                      ? '_'
                                      : toupper(character));
    }
    if (normalized[0] == 'F' && normalized[1]) {
        char *end = NULL;
        long number = strtol(normalized + 1, &end, 10);
        if (*end == '\0' && number >= 1 && number <= 25)
            return GLFW_KEY_F1 + (int)number - 1;
    }
	char gamepad_alias[32];
	const char *controller_name = normalized;
	if (!strncmp(normalized, "CONTROLLER_", 11)) {
		snprintf(gamepad_alias, sizeof(gamepad_alias), "GAMEPAD_%s", normalized + 11);
		controller_name = gamepad_alias;
	}
	struct TTControllerName { const char *name; int binding; };
	static const struct TTControllerName controller_names[] = {
		{"GAMEPAD_A", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_A},
		{"GAMEPAD_B", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_B},
		{"GAMEPAD_X", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_X},
		{"GAMEPAD_Y", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_Y},
		{"GAMEPAD_LEFT_BUMPER", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_LEFT_BUMPER},
		{"GAMEPAD_RIGHT_BUMPER", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER},
		{"GAMEPAD_BACK", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_BACK},
		{"GAMEPAD_START", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_START},
		{"GAMEPAD_GUIDE", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_GUIDE},
		{"GAMEPAD_LEFT_THUMB", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_LEFT_THUMB},
		{"GAMEPAD_RIGHT_THUMB", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_RIGHT_THUMB},
		{"GAMEPAD_DPAD_UP", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_DPAD_UP},
		{"GAMEPAD_DPAD_RIGHT", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_DPAD_RIGHT},
		{"GAMEPAD_DPAD_DOWN", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_DPAD_DOWN},
		{"GAMEPAD_DPAD_LEFT", TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_DPAD_LEFT},
		{"GAMEPAD_LEFT_STICK_LEFT", TT_GAMEPAD_AXIS_NEGATIVE_BASE - GLFW_GAMEPAD_AXIS_LEFT_X},
		{"GAMEPAD_LEFT_STICK_RIGHT", TT_GAMEPAD_AXIS_POSITIVE_BASE - GLFW_GAMEPAD_AXIS_LEFT_X},
		{"GAMEPAD_LEFT_STICK_UP", TT_GAMEPAD_AXIS_NEGATIVE_BASE - GLFW_GAMEPAD_AXIS_LEFT_Y},
		{"GAMEPAD_LEFT_STICK_DOWN", TT_GAMEPAD_AXIS_POSITIVE_BASE - GLFW_GAMEPAD_AXIS_LEFT_Y},
		{"GAMEPAD_RIGHT_STICK_LEFT", TT_GAMEPAD_AXIS_NEGATIVE_BASE - GLFW_GAMEPAD_AXIS_RIGHT_X},
		{"GAMEPAD_RIGHT_STICK_RIGHT", TT_GAMEPAD_AXIS_POSITIVE_BASE - GLFW_GAMEPAD_AXIS_RIGHT_X},
		{"GAMEPAD_RIGHT_STICK_UP", TT_GAMEPAD_AXIS_NEGATIVE_BASE - GLFW_GAMEPAD_AXIS_RIGHT_Y},
		{"GAMEPAD_RIGHT_STICK_DOWN", TT_GAMEPAD_AXIS_POSITIVE_BASE - GLFW_GAMEPAD_AXIS_RIGHT_Y},
		{"GAMEPAD_LEFT_TRIGGER", TT_GAMEPAD_AXIS_POSITIVE_BASE - GLFW_GAMEPAD_AXIS_LEFT_TRIGGER},
		{"GAMEPAD_RIGHT_TRIGGER", TT_GAMEPAD_AXIS_POSITIVE_BASE - GLFW_GAMEPAD_AXIS_RIGHT_TRIGGER},
	};
	for (size_t index = 0;
		 index < sizeof(controller_names) / sizeof(controller_names[0]); ++index)
		if (!strcmp(controller_name, controller_names[index].name))
			return controller_names[index].binding;
	for (int button = 1; button <= 16; ++button) {
		char expected[32];
		snprintf(expected, sizeof(expected), "JOYSTICK_BUTTON_%d", button);
		if (!strcmp(normalized, expected)) return TT_JOYSTICK_BUTTON_BASE - (button - 1);
	}
	for (int axis = 1; axis <= 8; ++axis) {
		char expected[40];
		snprintf(expected, sizeof(expected), "JOYSTICK_AXIS_%d_NEGATIVE", axis);
		if (!strcmp(normalized, expected)) return TT_JOYSTICK_AXIS_NEGATIVE_BASE - (axis - 1);
		snprintf(expected, sizeof(expected), "JOYSTICK_AXIS_%d_POSITIVE", axis);
		if (!strcmp(normalized, expected)) return TT_JOYSTICK_AXIS_POSITIVE_BASE - (axis - 1);
	}
    struct TTKeyName { const char *name; int key; };
    static const struct TTKeyName names[] = {
        {"PLUS", GLFW_KEY_EQUAL}, {"EQUAL", GLFW_KEY_EQUAL},
        {"MINUS", GLFW_KEY_MINUS}, {"SPACE", GLFW_KEY_SPACE},
        {"ENTER", GLFW_KEY_ENTER}, {"RETURN", GLFW_KEY_ENTER},
        {"ESCAPE", GLFW_KEY_ESCAPE},
        {"ESC", GLFW_KEY_ESCAPE}, {"TAB", GLFW_KEY_TAB},
        {"BACKSPACE", GLFW_KEY_BACKSPACE},
        {"INSERT", GLFW_KEY_INSERT}, {"DELETE", GLFW_KEY_DELETE},
        {"UP", GLFW_KEY_UP}, {"DOWN", GLFW_KEY_DOWN},
        {"LEFT", GLFW_KEY_LEFT}, {"RIGHT", GLFW_KEY_RIGHT},
        {"PAGE_UP", GLFW_KEY_PAGE_UP}, {"PAGE_DOWN", GLFW_KEY_PAGE_DOWN},
        {"HOME", GLFW_KEY_HOME}, {"END", GLFW_KEY_END},
        {"CAPS_LOCK", GLFW_KEY_CAPS_LOCK}, {"SCROLL_LOCK", GLFW_KEY_SCROLL_LOCK},
        {"NUM_LOCK", GLFW_KEY_NUM_LOCK}, {"PRINT_SCREEN", GLFW_KEY_PRINT_SCREEN},
        {"PAUSE", GLFW_KEY_PAUSE}, {"MENU", GLFW_KEY_MENU},
        {"COMMA", GLFW_KEY_COMMA}, {"PERIOD", GLFW_KEY_PERIOD},
        {"SLASH", GLFW_KEY_SLASH}, {"SEMICOLON", GLFW_KEY_SEMICOLON},
        {"APOSTROPHE", GLFW_KEY_APOSTROPHE},
        {"LEFT_BRACKET", GLFW_KEY_LEFT_BRACKET},
        {"RIGHT_BRACKET", GLFW_KEY_RIGHT_BRACKET},
        {"BACKSLASH", GLFW_KEY_BACKSLASH}, {"GRAVE", GLFW_KEY_GRAVE_ACCENT},
        {"SHIFT", GLFW_KEY_LEFT_SHIFT}, {"LEFT_SHIFT", GLFW_KEY_LEFT_SHIFT},
        {"RIGHT_SHIFT", GLFW_KEY_RIGHT_SHIFT}, {"CTRL", GLFW_KEY_LEFT_CONTROL},
        {"CONTROL", GLFW_KEY_LEFT_CONTROL}, {"LEFT_CONTROL", GLFW_KEY_LEFT_CONTROL},
        {"RIGHT_CONTROL", GLFW_KEY_RIGHT_CONTROL}, {"ALT", GLFW_KEY_LEFT_ALT},
        {"LEFT_ALT", GLFW_KEY_LEFT_ALT}, {"RIGHT_ALT", GLFW_KEY_RIGHT_ALT},
        {"SUPER", GLFW_KEY_LEFT_SUPER}, {"LEFT_SUPER", GLFW_KEY_LEFT_SUPER},
        {"RIGHT_SUPER", GLFW_KEY_RIGHT_SUPER},
        {"KP_ADD", GLFW_KEY_KP_ADD}, {"KP_SUBTRACT", GLFW_KEY_KP_SUBTRACT},
        {"KP_DIVIDE", GLFW_KEY_KP_DIVIDE}, {"KP_MULTIPLY", GLFW_KEY_KP_MULTIPLY},
        {"KP_EQUAL", GLFW_KEY_KP_EQUAL},
        {"KP_DECIMAL", GLFW_KEY_KP_DECIMAL}, {"KP_ENTER", GLFW_KEY_KP_ENTER},
        {"KP_0", GLFW_KEY_KP_0}, {"KP_1", GLFW_KEY_KP_1},
        {"KP_2", GLFW_KEY_KP_2}, {"KP_3", GLFW_KEY_KP_3},
        {"KP_4", GLFW_KEY_KP_4}, {"KP_5", GLFW_KEY_KP_5},
        {"KP_6", GLFW_KEY_KP_6}, {"KP_7", GLFW_KEY_KP_7},
        {"KP_8", GLFW_KEY_KP_8}, {"KP_9", GLFW_KEY_KP_9},
    };
    for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); ++index)
        if (!strcmp(normalized, names[index].name)) return names[index].key;
    return GLFW_KEY_UNKNOWN;
}

static bool tt_parse_key_list(const char *list, int *keys, int *count) {
    if (!list || !list[0]) return false;
    char copy[256];
    size_t length = strlen(list);
    if (length >= sizeof(copy)) return false;
    memcpy(copy, list, length + 1);
    *count = 0;
    char *context = NULL;
#if defined(_MSC_VER)
    for (char *name = strtok_s(copy, ",", &context); name;
         name = strtok_s(NULL, ",", &context)) {
#elif defined(_WIN32)
    (void)context;
    for (char *name = strtok(copy, ","); name;
         name = strtok(NULL, ",")) {
#else
    for (char *name = strtok_r(copy, ",", &context); name;
         name = strtok_r(NULL, ",", &context)) {
#endif
        if (*count >= TT_MAX_ACTION_KEYS) return false;
        int key = tt_key_from_name(name);
        if (key == GLFW_KEY_UNKNOWN) return false;
        keys[(*count)++] = key;
    }
    return *count > 0;
}

static bool tt_platform_set_bindings(TTPlatform *platform,
                                     const char *left, const char *right,
                                     const char *up, const char *down,
                                     const char *fire, const char *charge,
                                     const char *pause, const char *restart,
                                     const char *back, const char *volume_down,
                                     const char *volume_up,
                                     const char *fullscreen,
                                     const char *fps) {
    if (!platform) return false;
    const char *lists[TT_INPUT_ACTION_COUNT] = {
        left, right, up, down, fire, charge, pause, restart, back,
        volume_down, volume_up, fullscreen, fps,
    };
    int keys[TT_INPUT_ACTION_COUNT][TT_MAX_ACTION_KEYS] = {{0}};
    int counts[TT_INPUT_ACTION_COUNT] = {0};
    for (int action = 0; action < TT_INPUT_ACTION_COUNT; ++action) {
        if (!tt_parse_key_list(lists[action], keys[action], &counts[action])) {
            snprintf(tt_platform_error, sizeof(tt_platform_error),
                     "invalid key binding list: %s", lists[action] ? lists[action] : "");
            return false;
        }
    }
    memcpy(platform->action_keys, keys, sizeof(keys));
    memcpy(platform->action_key_counts, counts, sizeof(counts));
    return true;
}

static bool tt_binding_pressed(TTPlatform *platform, int key) {
		if (key <= TT_GAMEPAD_BUTTON_BASE && key > TT_GAMEPAD_AXIS_NEGATIVE_BASE) {
			GLFWgamepadstate state;
			int button = TT_GAMEPAD_BUTTON_BASE - key;
			if (glfwGetGamepadState(GLFW_JOYSTICK_1, &state) &&
				button >= 0 && button <= GLFW_GAMEPAD_BUTTON_LAST &&
				state.buttons[button] == GLFW_PRESS) return true;
			return false;
		}
		if (key <= TT_GAMEPAD_AXIS_NEGATIVE_BASE && key > TT_GAMEPAD_AXIS_POSITIVE_BASE) {
			GLFWgamepadstate state;
			int axis = TT_GAMEPAD_AXIS_NEGATIVE_BASE - key;
			if (glfwGetGamepadState(GLFW_JOYSTICK_1, &state) &&
				axis >= 0 && axis <= GLFW_GAMEPAD_AXIS_LAST && state.axes[axis] < -0.5f)
				return true;
			return false;
		}
		if (key <= TT_GAMEPAD_AXIS_POSITIVE_BASE && key > TT_JOYSTICK_BUTTON_BASE) {
			GLFWgamepadstate state;
			int axis = TT_GAMEPAD_AXIS_POSITIVE_BASE - key;
			if (glfwGetGamepadState(GLFW_JOYSTICK_1, &state) &&
				axis >= 0 && axis <= GLFW_GAMEPAD_AXIS_LAST && state.axes[axis] > 0.5f)
				return true;
			return false;
		}
		if (key <= TT_JOYSTICK_BUTTON_BASE && key > TT_JOYSTICK_AXIS_NEGATIVE_BASE) {
			int count = 0;
			int button = TT_JOYSTICK_BUTTON_BASE - key;
			const unsigned char *buttons = glfwGetJoystickButtons(GLFW_JOYSTICK_1, &count);
			if (buttons && button >= 0 && button < count && buttons[button] == GLFW_PRESS)
				return true;
			return false;
		}
		if (key <= TT_JOYSTICK_AXIS_NEGATIVE_BASE && key > TT_JOYSTICK_AXIS_POSITIVE_BASE) {
			int count = 0;
			int axis = TT_JOYSTICK_AXIS_NEGATIVE_BASE - key;
			const float *axes = glfwGetJoystickAxes(GLFW_JOYSTICK_1, &count);
			if (axes && axis >= 0 && axis < count && axes[axis] < -0.5f) return true;
			return false;
		}
		if (key <= TT_JOYSTICK_AXIS_POSITIVE_BASE) {
			int count = 0;
			int axis = TT_JOYSTICK_AXIS_POSITIVE_BASE - key;
			const float *axes = glfwGetJoystickAxes(GLFW_JOYSTICK_1, &count);
			if (axes && axis >= 0 && axis < count && axes[axis] > 0.5f) return true;
			return false;
		}
	bool typed_letter = key >= GLFW_KEY_A && key <= GLFW_KEY_Z &&
		(platform->typed_letter_mask & (1u << (key - GLFW_KEY_A))) != 0;
	return !typed_letter && glfwGetKey(platform->window, key) == GLFW_PRESS;
}

static bool tt_platform_controller_back_pressed(TTPlatform *platform) {
    if (!platform) return false;
    int key = glfwJoystickIsGamepad(GLFW_JOYSTICK_1)
        ? TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_B
        : TT_JOYSTICK_BUTTON_BASE - 1;
    return tt_binding_pressed(platform, key);
}

static bool tt_platform_controller_start_pressed(TTPlatform *platform) {
    if (!platform) return false;
    int key = glfwJoystickIsGamepad(GLFW_JOYSTICK_1)
        ? TT_GAMEPAD_BUTTON_BASE - GLFW_GAMEPAD_BUTTON_START
        : TT_JOYSTICK_BUTTON_BASE - 7;
    return tt_binding_pressed(platform, key);
}

static bool tt_action_pressed(TTPlatform *platform, int action) {
    for (int index = 0; index < platform->action_key_counts[action]; ++index) {
		if (tt_binding_pressed(platform, platform->action_keys[action][index])) return true;
    }
    return false;
}

static bool tt_action_pressed_except_shifts(TTPlatform *platform, int action) {
    for (int index = 0; index < platform->action_key_counts[action]; ++index) {
		int key = platform->action_keys[action][index];
		if (key == GLFW_KEY_LEFT_SHIFT || key == GLFW_KEY_RIGHT_SHIFT) continue;
		if (tt_binding_pressed(platform, key)) return true;
    }
    return false;
}

static bool tt_platform_take_god_mode_toggle(TTPlatform *platform) {
    if (!platform || !platform->god_mode_toggle_requested) return false;
    platform->god_mode_toggle_requested = false;
    return true;
}

static uint32_t tt_platform_input(TTPlatform *platform) {
    if (!platform || !platform->window) return 0;
    for (int key = GLFW_KEY_A; key <= GLFW_KEY_Z; ++key)
        if (glfwGetKey(platform->window, key) != GLFW_PRESS)
            platform->typed_letter_mask &= ~(1u << (key - GLFW_KEY_A));
    if (platform->replay_library_open) {
        const int actions[7] = {TT_ACTION_UP, TT_ACTION_DOWN, TT_ACTION_LEFT,
            TT_ACTION_RIGHT, TT_ACTION_FIRE, TT_ACTION_CHARGE, TT_ACTION_BACK};
        const int events[7] = {-GLFW_KEY_UP, -GLFW_KEY_DOWN, -GLFW_KEY_LEFT,
            -GLFW_KEY_RIGHT, -GLFW_KEY_ENTER, -GLFW_KEY_ESCAPE, -GLFW_KEY_ESCAPE};
        uint32_t held = 0;
        bool controller_back = tt_platform_controller_back_pressed(platform);
        if (controller_back) held |= 1u << 6;
        for (int action = 0; action < 7; ++action) {
            if ((platform->replay_text_edit && action != 6) ||
                (controller_back && action == 5)) continue;
            for (int binding = 0; binding < platform->action_key_counts[actions[action]]; ++binding) {
                int key = platform->action_keys[actions[action]][binding];
                if (key < 0 && tt_binding_pressed(platform, key)) held |= 1u << action;
            }
            if ((held & (1u << action)) && !(platform->replay_gamepad_latch & (1u << action)))
                tt_replay_event(platform, events[action]);
        }
        platform->replay_gamepad_latch = held;
    } else {
        platform->replay_gamepad_latch = 0;
    }
    uint32_t input = 0;
    bool volume_down = tt_action_pressed(platform, TT_ACTION_VOLUME_DOWN);
    bool volume_up = tt_action_pressed(platform, TT_ACTION_VOLUME_UP);
    if (tt_action_pressed(platform, TT_ACTION_BACK)) input |= 1u << TT_ACTION_BACK;
    if (volume_down) input |= 1u << TT_ACTION_VOLUME_DOWN;
    if (volume_up) input |= 1u << TT_ACTION_VOLUME_UP;
    if (tt_action_pressed(platform, TT_ACTION_LEFT)) input |= 1u << TT_ACTION_LEFT;
    if (tt_action_pressed(platform, TT_ACTION_RIGHT)) input |= 1u << TT_ACTION_RIGHT;
    if (tt_action_pressed(platform, TT_ACTION_UP)) input |= 1u << TT_ACTION_UP;
    if (tt_action_pressed(platform, TT_ACTION_DOWN)) input |= 1u << TT_ACTION_DOWN;
    if (tt_action_pressed(platform, TT_ACTION_FIRE)) input |= 1u << TT_ACTION_FIRE;
    bool charge = tt_action_pressed(platform, TT_ACTION_CHARGE);
    if (volume_up && !tt_action_pressed_except_shifts(platform, TT_ACTION_CHARGE))
        charge = false;
    if (charge) input |= 1u << TT_ACTION_CHARGE;
    if (tt_action_pressed(platform, TT_ACTION_PAUSE)) input |= 1u << TT_ACTION_PAUSE;
    if (tt_action_pressed(platform, TT_ACTION_RESTART)) input |= 1u << TT_ACTION_RESTART;
    return input;
}

static void tt_platform_set_paused(TTPlatform *platform, bool paused) {
    if (!platform || platform->paused == paused)
        return;
    double now = glfwGetTime();
    if (paused) {
        platform->paused_time = now;
    } else {
        platform->start_time += now - platform->paused_time;
    }
    platform->paused = paused;
}

static bool tt_platform_should_close(TTPlatform *platform) {
    return glfwWindowShouldClose(platform->window) == GLFW_TRUE;
}

static void tt_platform_request_close(TTPlatform *platform) {
    if (platform && platform->window)
        glfwSetWindowShouldClose(platform->window, GLFW_TRUE);
}

static int tt_platform_device_count(TTPlatform *platform) {
    return platform ? platform->device_count : 0;
}

static TTDeviceInfo tt_platform_device_info(TTPlatform *platform, int index) {
    TTDeviceInfo empty = {0};
    if (!platform || index < 0 || index >= platform->device_count) return empty;
    return platform->devices[index];
}

static const char *tt_platform_device_name(TTPlatform *platform, int index) {
    if (!platform || index < 0 || index >= platform->device_count) return "unknown";
    return platform->devices[index].name;
}

static uint32_t tt_platform_device_api_version(TTPlatform *platform, int index) {
    return tt_platform_device_info(platform, index).api_version;
}

static uint32_t tt_platform_device_driver_version(TTPlatform *platform, int index) {
    return tt_platform_device_info(platform, index).driver_version;
}

static int tt_platform_device_graphics_queue(TTPlatform *platform, int index) {
    return tt_platform_device_info(platform, index).graphics_queue_family;
}

static int tt_platform_device_present_queue(TTPlatform *platform, int index) {
    return tt_platform_device_info(platform, index).present_queue_family;
}

#endif
