module runtime

import antono2.vkmemalloc as vma
import antono2.vulkan as vk

fn C.volkInitialize() vk.Result

const instance_buffer_slot = 0
const tunnel_buffer_slot = 1
const tunnel_fill_buffer_slot = 2

fn C.tt_platform_physical_device(platform &C.TTPlatform) voidptr

fn C.tt_platform_device(platform &C.TTPlatform) voidptr

fn C.tt_platform_buffer_size(slot int) u64

fn C.tt_platform_buffer_frame_size(slot int) u64

fn C.tt_platform_attach_mapped_buffer(platform &C.TTPlatform, slot int, handle voidptr, mapped voidptr, size u64) bool

fn C.tt_platform_wait_idle(platform &C.TTPlatform)

struct ManagedVertexBuffer {
mut:
	handle     vk.Buffer = unsafe { nil }
	allocation vma.AllocationInfo
	mapped     voidptr = unsafe { nil }
	size       u64
}

struct VulkanMemory {
mut:
	device      vk.Device = unsafe { nil }
	allocator   vma.Allocator
	instances   ManagedVertexBuffer
	tunnel      ManagedVertexBuffer
	tunnel_fill ManagedVertexBuffer
}

fn initialize_vulkan_loader() ! {
	result := $if windows {
		C.volkInitialize()
	} $else {
		vk.initialize_loader()
	}
	if result != .success {
		return error('could not initialize Vulkan loader: ${result}')
	}
}

fn new_vulkan_memory(platform &C.TTPlatform) !&VulkanMemory {
	physical_device := vk.PhysicalDevice(C.tt_platform_physical_device(platform))
	device := vk.Device(C.tt_platform_device(platform))
	if isnil(physical_device) || isnil(device) {
		return error('Vulkan allocator received an incomplete device')
	}
	mut result := &VulkanMemory{
		device: device
		allocator: vma.new(vma.AllocatorCreateInfo{
			physical_device: physical_device
			device: device
			// The three persistently mapped buffers each contain one region per
			// frame in flight. The fill buffer also owns the non-overlapping ship
			// mesh region, so reserve one comfortably sized host-visible block.
			preferred_block_size: 32 * 1024 * 1024
			event_trace_capacity: 32
		})
	}
	result.instances = result.create_vertex_buffer(C.tt_platform_buffer_size(instance_buffer_slot)) or {
		result.destroy()
		return err
	}
	result.tunnel = result.create_vertex_buffer(C.tt_platform_buffer_size(tunnel_buffer_slot)) or {
		result.destroy()
		return err
	}
	result.tunnel_fill = result.create_vertex_buffer(C.tt_platform_buffer_size(tunnel_fill_buffer_slot)) or {
		result.destroy()
		return err
	}
	for slot, buffer in [&result.instances, &result.tunnel, &result.tunnel_fill] {
		if !C.tt_platform_attach_mapped_buffer(platform, slot, voidptr(buffer.handle), buffer.mapped, buffer.size) {
			result.destroy()
			return error('could not attach Vulkan allocator buffer ${slot}')
		}
	}
	return result
}

fn (mut memory VulkanMemory) create_vertex_buffer(size u64) !ManagedVertexBuffer {
	if size == 0 {
		return error('Vulkan vertex-buffer size must be greater than zero')
	}
	buffer_info := vk.BufferCreateInfo{
		size: size
		usage: vk.BufferUsageFlags(vk.BufferUsageFlagBits.vertex_buffer)
		sharingMode: .exclusive
	}
	mut buffer := ManagedVertexBuffer{
		size: size
	}
	result := memory.allocator.create_buffer_with_options(&buffer_info, vma.AllocationOptions{
		usage: .upload
		// The C renderer writes through the persistent pointer, so preserve the
		// old bridge's coherent-memory guarantee rather than requiring flushes.
		required_flags: vk.MemoryPropertyFlags(vk.MemoryPropertyFlagBits.host_coherent)
	}, &buffer.handle, mut buffer.allocation)
	if result != .success {
		return error('could not allocate Vulkan vertex buffer: ${result}')
	}
	map_result := memory.allocator.map(mut buffer.allocation, &buffer.mapped)
	if map_result != .success {
		vk.destroy_buffer(memory.device, buffer.handle, unsafe { nil })
		_ = memory.allocator.release(mut buffer.allocation)
		return error('could not map Vulkan vertex buffer: ${map_result}')
	}
	return buffer
}

fn (memory &VulkanMemory) stats() vma.AllocatorStats {
	return memory.allocator.stats()
}

fn (mut memory VulkanMemory) destroy_buffer(mut buffer ManagedVertexBuffer) {
	if isnil(buffer.handle) {
		return
	}
	vk.destroy_buffer(memory.device, buffer.handle, unsafe { nil })
	_ = memory.allocator.release(mut buffer.allocation)
	buffer.handle = unsafe { nil }
	buffer.mapped = unsafe { nil }
	buffer.size = 0
}

fn (mut memory VulkanMemory) destroy() {
	memory.destroy_buffer(mut memory.instances)
	memory.destroy_buffer(mut memory.tunnel)
	memory.destroy_buffer(mut memory.tunnel_fill)
	memory.allocator.destroy()
}
