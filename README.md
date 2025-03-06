# MP4 Parser in Zig (WebAssembly)

A lightweight MP4 parser written in Zig v0.13 targeting WebAssembly, allowing for browser-based MP4 file parsing and playback.

## Features

- Parse MP4 files directly in the browser using WebAssembly
- Identify MP4 box structures (ftyp, moov, mdat, etc.)
- Display box types and sizes in the console
- Stream video playback of the parsed MP4 file
- Drag-and-drop file upload interface
- Minimal dependencies (pure Zig implementation)

## Getting Started

### Prerequisites

- [Zig 0.13.0](https://ziglang.org/download/) or newer
- PowerShell
- A modern web browser with WebAssembly support

### Initial Setup

1. Clone this repository:
   ```
   git clone https://github.com/haleth-embershield/fun-mp4-parser.git
   cd fun-mp4-parser
   ```

2. Run the setup script to install http-zerver:
   ```
   .\setup_http_server.ps1
   ```
   This script will:
   - Clone the http-zerver repository
   - Build the http-zerver executable
   - Copy the executable to your assets directory
   - Clean up the temporary files

### Building and Running

1. Build the project:
   ```
   zig build
   ```

2. Deploy and run the web server:
   ```
   zig build run
   ```
   This will:
   - Build the WebAssembly module
   - Copy all necessary files to the www directory
   - Start http-zerver on port 8000 serving the www directory

3. Open your browser and navigate to `http://localhost:8000`

### Development Commands

- `zig build` - Build the WebAssembly module
- `zig build deploy` - Build and copy files to the www directory
- `zig build run` - Build, deploy, and start http-zerver

## Server Implementation

This project uses http-zerver, a lightweight HTTP server written in Zig, for development and testing. The server is integrated into the build.zig script and automatically serves files from the www directory when running `zig build run`. This replaces the previous Python-based server implementation with a more efficient, native solution.

## Implementation Details

- Uses a freestanding WebAssembly target
- Implements custom memory management for WebAssembly constraints
- Parses MP4 box structure without external dependencies
- Communicates between Zig and JavaScript via WebAssembly imports/exports

## Future Enhancements

- Extract and display MP4 metadata
- Support for streaming MP4 formats
- Add visual effects based on MP4 byte data
- Implement more sophisticated memory management for larger files

## License

This project is open source and available under the [MIT License](LICENSE).
