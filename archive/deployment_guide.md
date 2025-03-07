# MP4 Parser Deployment Guide

This guide explains how to deploy and use the Zig-based MP4 parser that targets WebAssembly.

## Project Structure

The project is organized as follows:

```
fun-mp4-parser/
├── src/
│   └── mp4_parser.zig     # Zig source code for the MP4 parser
├── www/                   # Web application directory (generated at build time)
│   ├── index.html         # HTML/JS interface (copied from root)
│   ├── mp4_parser.wasm    # Compiled WebAssembly module (generated)
│   └── ...                # Other assets copied from /assets
├── assets/                # Static assets for the web application
│   ├── favicon.ico        # Favicon
│   └── ...                # Other static files
├── build.zig              # Zig build script
├── index.html             # Source HTML file
├── README.md              # Project documentation
└── deployment_guide.md    # This guide
```

## Automated Deployment

The project includes an automated build and deployment process using Zig's build system.

### Building the WebAssembly Module

To build the WebAssembly module:

```bash
zig build
```

This compiles the Zig code to WebAssembly and places the output in the `zig-out/bin` directory.

### Deploying to the Web Directory

To build and copy all necessary files to the `www` directory:

```bash
zig build deploy
```

This command:
1. Clears the `www` directory (or creates it if it doesn't exist)
2. Builds the WebAssembly module
3. Copies the WebAssembly module to the `www` directory
4. Copies the `index.html` file to the `www` directory
5. Copies all files from the `assets` directory to the `www` directory

### Running the Web Server

To build, deploy, and start a Python HTTP server:

```bash
zig build run
```

This command performs all the deployment steps and starts a Python HTTP server on port 8000.
Then open your browser and navigate to `http://localhost:8000`.

## Manual Deployment

If you prefer to deploy manually, follow these steps:

1. Build the WebAssembly module:
   ```bash
   zig build
   ```

2. Create a `www` directory if it doesn't exist:
   ```bash
   mkdir -p www
   ```

3. Copy the necessary files:
   ```bash
   cp zig-out/bin/mp4_parser.wasm www/
   cp index.html www/
   ```

4. Start a web server:
   ```bash
   cd www
   python -m http.server 8000
   ```

## Technical Implementation

### WebAssembly Integration

The MP4 parser is implemented in Zig and compiled to WebAssembly. Key aspects of the implementation:

1. **Memory Management**: 
   - Uses a fixed-size buffer (1MB) for storing MP4 data
   - Implements custom memory operations to work within WebAssembly constraints
   - Avoids standard library functions that aren't compatible with the freestanding target

2. **Function Exports**:
   - `addData`: Adds a chunk of MP4 data to the internal buffer
   - `parseMP4`: Parses the buffered MP4 data and identifies box structures
   - `logBytes`: Logs a specified number of bytes to the console
   - `resetBuffer`: Clears the internal buffer
   - `getBufferUsed`: Returns the number of bytes in the buffer

3. **Function Imports**:
   - `consoleLog`: For logging messages to the browser console
   - `createVideoElement`: For creating a video element with the processed data

### MP4 Format Parsing

The parser handles the basic MP4 container format by:
- Identifying box headers (size and type)
- Logging box information to the console
- Passing the complete MP4 data to the browser for playback

## Troubleshooting

- **CORS Issues**: If loading local files, you may encounter CORS errors. Make sure to serve your files from a proper web server.
- **Large Files**: The current implementation uses a fixed buffer size (1MB). For larger files, you may need to increase the buffer size in `mp4_parser.zig`.
- **Python Command**: If you have Python installed as `py` instead of `python`, the build script will attempt to use both commands.