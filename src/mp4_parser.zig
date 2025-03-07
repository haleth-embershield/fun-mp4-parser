// MP4 Parser in Zig v0.13
// Build target: WebAssembly
// Simple MP4 parser that logs bytes to browser console and uses browser's native decoder

// WASM imports for browser interaction
extern "env" fn consoleLog(ptr: [*]const u8, len: usize) void;
extern "env" fn createMediaUrl(ptr: [*]const u8, len: usize) void;
extern "env" fn updateMetadata(codec_ptr: [*]const u8, codec_len: usize, bitrate: u32, size: u32, sample_rate: u32, sample_size: u32, samples: u32) void;

// Box types for MP4 format
const BoxType = struct {
    type_code: [4]u8,

    fn init(code: []const u8) BoxType {
        var result = BoxType{ .type_code = undefined };
        // Manual copy instead of std.mem.copy
        for (code, 0..) |byte, i| {
            if (i < 4) result.type_code[i] = byte;
        }
        return result;
    }

    fn eql(self: BoxType, other: []const u8) bool {
        // Manual comparison instead of std.mem.eql
        if (other.len < 4) return false;
        for (0..4) |i| {
            if (self.type_code[i] != other[i]) return false;
        }
        return true;
    }
};

// MP4 Box header structure
const BoxHeader = struct {
    size: u32,
    type_code: BoxType,
    extended_size: ?u64,

    fn totalSize(self: BoxHeader) u64 {
        return if (self.size == 1) self.extended_size.? else self.size;
    }
};

// MP4 Metadata structure
const MP4Metadata = struct {
    codec: [32]u8,
    codec_len: usize,
    bitrate: u32,
    size: u32,
    sample_rate: u32,
    sample_size: u32,
    samples: u32,

    fn init() MP4Metadata {
        return MP4Metadata{
            .codec = undefined,
            .codec_len = 0,
            .bitrate = 0,
            .size = 0,
            .sample_rate = 0,
            .sample_size = 0,
            .samples = 0,
        };
    }

    fn setCodec(self: *MP4Metadata, codec: []const u8) void {
        self.codec_len = 0;
        for (codec, 0..) |byte, i| {
            if (i < self.codec.len) {
                self.codec[i] = byte;
                self.codec_len += 1;
            }
        }
    }
};

// Simple memory buffer for processing data
var buffer: [100 * 1024 * 1024]u8 = undefined; // 100MB buffer
var buffer_used: usize = 0;

// Metadata storage
var metadata = MP4Metadata.init();

// Add data to our buffer
export fn addData(ptr: [*]const u8, len: usize) void {
    if (buffer_used + len <= buffer.len) {
        // Manual copy instead of std.mem.copy
        for (0..len) |i| {
            buffer[buffer_used + i] = ptr[i];
        }
        buffer_used += len;
        logString("Added data chunk to buffer");
    } else {
        logString("Buffer overflow, can't add more data");
    }
}

// Parse the MP4 file and extract basic information
export fn parseMP4() void {
    var offset: usize = 0;

    logString("Starting MP4 parsing");

    // Set file size in metadata
    metadata.size = @intCast(buffer_used);

    while (offset + 8 <= buffer_used) {
        const header = parseBoxHeader(buffer[offset..], &offset);
        const box_size = header.totalSize();

        // Log the box type
        var msg_buf: [64]u8 = undefined;
        const msg = formatBoxMessage(&msg_buf, header.type_code.type_code, box_size);

        logString(msg);

        // Process specific box types to extract metadata
        if (header.type_code.eql("moov")) {
            processMoovBox(buffer[offset..], box_size, offset);
        } else if (header.type_code.eql("mdat")) {
            // Media data box - could calculate bitrate based on size and duration
            if (metadata.samples > 0 and metadata.sample_rate > 0) {
                const duration_seconds = @as(f32, @floatFromInt(metadata.samples)) / @as(f32, @floatFromInt(metadata.sample_rate));
                if (duration_seconds > 0) {
                    metadata.bitrate = @intCast(@as(u32, @intFromFloat((@as(f32, @floatFromInt(box_size)) * 8.0) / duration_seconds)));
                }
            }
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= buffer_used) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            // If we can't determine size or it's beyond our buffer, stop
            break;
        }
    }

    // Create media URL for browser playback
    createMediaUrl(@ptrCast(&buffer[0]), buffer_used);

    // Send metadata to JavaScript
    updateMetadataInBrowser();
}

// Process moov box to extract metadata
fn processMoovBox(data: []u8, size: u64, _: usize) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("mvhd")) {
            // Movie header box - contains duration and timescale
            processMvhdBox(data[offset..], box_size);
        } else if (header.type_code.eql("trak")) {
            // Track box - contains media information
            processTrakBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process mvhd box to extract duration and timescale
fn processMvhdBox(data: []u8, _: u64) void {
    if (data.len < 20) return;

    // Version and flags
    const version = data[0];

    // Different offsets based on version
    var timescale_offset: usize = 0;
    var duration_offset: usize = 0;

    if (version == 0) {
        // 32-bit values
        timescale_offset = 12;
        duration_offset = 16;

        if (data.len >= duration_offset + 4) {
            const timescale = readU32BE(data, timescale_offset);
            const duration = readU32BE(data, duration_offset);

            // Calculate samples if not already set
            if (metadata.samples == 0) {
                metadata.samples = duration;
                metadata.sample_rate = timescale;
            }
        }
    } else if (version == 1) {
        // 64-bit values
        timescale_offset = 20;
        duration_offset = 24;

        if (data.len >= duration_offset + 8) {
            const timescale = readU32BE(data, timescale_offset);
            const duration = readU64BE(data, duration_offset);

            // Calculate samples if not already set
            if (metadata.samples == 0) {
                metadata.samples = @intCast(duration);
                metadata.sample_rate = timescale;
            }
        }
    }
}

// Process trak box to extract track information
fn processTrakBox(data: []u8, size: u64) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("mdia")) {
            // Media box
            processMdiaBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process mdia box to extract media information
fn processMdiaBox(data: []u8, size: u64) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("minf")) {
            // Media information box
            processMinfBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process minf box to extract media information
fn processMinfBox(data: []u8, size: u64) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("stbl")) {
            // Sample table box
            processStblBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process stbl box to extract sample table information
fn processStblBox(data: []u8, size: u64) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("stsd")) {
            // Sample description box - contains codec information
            processStsdBox(data[offset..], box_size);
        } else if (header.type_code.eql("stsz")) {
            // Sample size box - contains sample size information
            processSampleSizeBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process stsd box to extract codec information
fn processStsdBox(data: []u8, _: u64) void {
    if (data.len < 8) return;

    // Version and flags
    _ = data[0]; // Skip version

    // Entry count
    const entry_count = readU32BE(data, 4);

    if (entry_count > 0 and data.len >= 16) {
        // First entry - contains codec type
        const first_entry_size = readU32BE(data, 8);
        if (data.len >= 16 and first_entry_size >= 8) {
            // Codec type is at offset 12
            const codec_type = data[12..16];

            // Set codec in metadata
            metadata.setCodec(codec_type);

            // Log the codec type for debugging
            var msg_buf: [64]u8 = undefined;
            var pos: usize = 0;
            const prefix = "Found codec: ";
            for (prefix) |c| {
                msg_buf[pos] = c;
                pos += 1;
            }
            for (codec_type) |c| {
                msg_buf[pos] = c;
                pos += 1;
            }
            logString(msg_buf[0..pos]);

            // If it's an audio codec, try to extract sample rate and sample size
            if (codec_type[0] == 'm' and codec_type[1] == 'p' and codec_type[2] == '4' and codec_type[3] == 'a') {
                // MP4A audio codec
                logString("Found MP4A audio codec");

                if (data.len >= 36) {
                    // Sample size is at offset 32
                    metadata.sample_size = readU16BE(data, 32);

                    // Sample rate is at offset 34, but it's a fixed-point number
                    const sample_rate_fixed = readU32BE(data, 34);
                    metadata.sample_rate = sample_rate_fixed >> 16;

                    // Log the extracted values
                    var info_buf: [128]u8 = undefined;
                    var info_pos: usize = 0;
                    const info_prefix = "MP4A details: sample_size=";
                    for (info_prefix) |c| {
                        info_buf[info_pos] = c;
                        info_pos += 1;
                    }
                    info_pos += formatNumber(info_buf[info_pos..], metadata.sample_size);
                    const rate_str = ", sample_rate=";
                    for (rate_str) |c| {
                        info_buf[info_pos] = c;
                        info_pos += 1;
                    }
                    info_pos += formatNumber(info_buf[info_pos..], metadata.sample_rate);
                    logString(info_buf[0..info_pos]);

                    // Validate the values and set defaults if they seem wrong
                    if (metadata.sample_rate < 8000 or metadata.sample_rate > 96000) {
                        logString("Invalid sample rate, using default 44100Hz");
                        metadata.sample_rate = 44100;
                    }

                    if (metadata.sample_size != 8 and metadata.sample_size != 16 and metadata.sample_size != 24 and metadata.sample_size != 32) {
                        logString("Invalid sample size, using default 16-bit");
                        metadata.sample_size = 16;
                    }
                }

                // Look for esds box which contains more detailed codec info
                var offset: usize = 16;
                while (offset + 8 <= data.len) {
                    if (offset + 4 <= data.len and
                        data[offset] == 'e' and
                        data[offset + 1] == 's' and
                        data[offset + 2] == 'd' and
                        data[offset + 3] == 's')
                    {
                        logString("Found esds box with detailed codec info");
                        // esds box contains detailed codec parameters
                        // This is where we would extract AAC specific config
                        break;
                    }
                    offset += 1;
                }
            }
        }
    }
}

// Process sample size box to extract sample size information
fn processSampleSizeBox(data: []u8, _: u64) void {
    if (data.len < 12) return;

    // Version and flags
    _ = data[0]; // Skip version

    // Default sample size
    const default_sample_size = readU32BE(data, 4);

    // Sample count
    const sample_count = readU32BE(data, 8);

    // Update metadata
    if (metadata.samples == 0) {
        metadata.samples = sample_count;
    }

    if (metadata.sample_size == 0 and default_sample_size > 0) {
        metadata.sample_size = default_sample_size;
    }
}

// Read a big-endian u16
fn readU16BE(data: []u8, offset: usize) u16 {
    return @as(u16, data[offset]) << 8 |
        @as(u16, data[offset + 1]);
}

// Update metadata in browser
fn updateMetadataInBrowser() void {
    updateMetadata(&metadata.codec, metadata.codec_len, metadata.bitrate, metadata.size, metadata.sample_rate, metadata.sample_size, metadata.samples);
}

// Format a message about a box (simplified version without std.fmt)
fn formatBoxMessage(buf: []u8, type_code: [4]u8, size: u64) []u8 {
    const prefix = "Found box: ";
    var pos: usize = 0;

    // Copy prefix
    for (prefix) |c| {
        buf[pos] = c;
        pos += 1;
    }

    // Copy type code
    for (type_code) |c| {
        buf[pos] = c;
        pos += 1;
    }

    // Add separator
    const separator = ", size: ";
    for (separator) |c| {
        buf[pos] = c;
        pos += 1;
    }

    // Convert size to string (simple implementation)
    var size_copy = size;
    var digits: [20]u8 = undefined; // Max 20 digits for u64
    var digit_count: usize = 0;

    // Handle zero case
    if (size == 0) {
        buf[pos] = '0';
        pos += 1;
    } else {
        // Extract digits in reverse order
        while (size_copy > 0) {
            digits[digit_count] = @intCast((size_copy % 10) + '0');
            size_copy /= 10;
            digit_count += 1;
        }

        // Copy digits in correct order
        var i: usize = digit_count;
        while (i > 0) {
            i -= 1;
            buf[pos] = digits[i];
            pos += 1;
        }
    }

    // Add " bytes" suffix
    const suffix = " bytes";
    for (suffix) |c| {
        buf[pos] = c;
        pos += 1;
    }

    return buf[0..pos];
}

// Log bytes at a specific position (for streaming during playback)
export fn logBytesAtPosition(position: usize, count: usize) void {
    if (position >= buffer_used) return;

    const bytes_to_log = min(count, buffer_used - position);
    var i: usize = position;
    const end_pos = position + bytes_to_log;

    while (i < end_pos) {
        var log_buf: [128]u8 = undefined;
        const end = min(i + 16, end_pos);
        var log_pos: usize = 0;

        // Format position (simplified hex formatting)
        log_pos += formatHex(log_buf[log_pos..], i, 8);
        log_buf[log_pos] = ':';
        log_pos += 1;
        log_buf[log_pos] = ' ';
        log_pos += 1;

        // Format hex values
        var j: usize = i;
        while (j < end) : (j += 1) {
            log_pos += formatHex(log_buf[log_pos..], buffer[j], 2);
            log_buf[log_pos] = ' ';
            log_pos += 1;
        }

        logString(log_buf[0..log_pos]);
        i = end;
    }
}

// Simple min function
fn min(a: usize, b: usize) usize {
    return if (a < b) a else b;
}

// Format a number as hex
fn formatHex(buf: []u8, value: usize, width: usize) usize {
    const hex_chars = "0123456789ABCDEF";
    var pos: usize = 0;

    // Add "0x" prefix
    buf[pos] = '0';
    pos += 1;
    buf[pos] = 'x';
    pos += 1;

    // Convert to hex
    var shift: usize = width * 4;
    while (shift > 0) {
        shift -= 4;
        const digit = (value >> @intCast(shift)) & 0xF;
        buf[pos] = hex_chars[digit];
        pos += 1;
    }

    return pos;
}

// Parse an MP4 box header
fn parseBoxHeader(data: []u8, offset: *usize) BoxHeader {
    // Read size (big-endian u32)
    const size = readU32BE(data, 0);

    // Read type code
    const type_code = BoxType.init(data[4..8]);

    var header = BoxHeader{
        .size = size,
        .type_code = type_code,
        .extended_size = null,
    };

    // Update offset, accounting for the header we just read
    offset.* += 8;

    // If this is a large box, read the extended size (8 more bytes)
    if (header.size == 1 and offset.* + 8 <= data.len) {
        header.extended_size = readU64BE(data, 8);
        offset.* += 8;
    }

    return header;
}

// Read a big-endian u32
fn readU32BE(data: []u8, offset: usize) u32 {
    return @as(u32, data[offset]) << 24 |
        @as(u32, data[offset + 1]) << 16 |
        @as(u32, data[offset + 2]) << 8 |
        @as(u32, data[offset + 3]);
}

// Read a big-endian u64
fn readU64BE(data: []u8, offset: usize) u64 {
    return @as(u64, data[offset]) << 56 |
        @as(u64, data[offset + 1]) << 48 |
        @as(u64, data[offset + 2]) << 40 |
        @as(u64, data[offset + 3]) << 32 |
        @as(u64, data[offset + 4]) << 24 |
        @as(u64, data[offset + 5]) << 16 |
        @as(u64, data[offset + 6]) << 8 |
        @as(u64, data[offset + 7]);
}

// Helper to log strings to browser console
fn logString(msg: []const u8) void {
    consoleLog(msg.ptr, msg.len);
}

// Reset the buffer and prepare for new data
export fn resetBuffer() void {
    buffer_used = 0;
    logString("Buffer reset");
}

// Return the number of bytes currently in the buffer
export fn getBufferUsed() usize {
    return buffer_used;
}

// Helper function to format numbers (since we avoid std.fmt)
fn formatNumber(buf: []u8, value: u32) usize {
    var digits: [10]u8 = undefined;
    var count: usize = 0;
    var val = value;
    if (val == 0) {
        buf[0] = '0';
        return 1;
    }
    while (val > 0) {
        digits[count] = @intCast((val % 10) + '0');
        val /= 10;
        count += 1;
    }
    var pos: usize = 0;
    while (count > 0) {
        count -= 1;
        buf[pos] = digits[count];
        pos += 1;
    }
    return pos;
}
