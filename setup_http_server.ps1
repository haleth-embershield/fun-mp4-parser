# PowerShell script to setup http-zerver
Write-Host "Setting up http-zerver..."

# Step 1: Clone the repository
Write-Host "Cloning http-zerver repository..."
git clone https://github.com/haleth-embershield/http-zerver

# Step 2: Change directory into the repo
Set-Location -Path http-zerver

# Step 3: Run zig build
Write-Host "Building http-zerver..."
zig build

# Step 4: Change back to parent directory
Set-Location -Path ..

# Step 5: Create assets directory if it doesn't exist
if (-not (Test-Path -Path "assets")) {
    New-Item -ItemType Directory -Path "assets"
}

# Step 6: Copy the executable
Write-Host "Copying http-zerver executable to assets directory..."
Copy-Item -Path "http-zerver/zig-out/bin/http-zerver.exe" -Destination "assets/" -Force

# Step 7: Cleanup - remove the cloned repository
Write-Host "Cleaning up..."
Remove-Item -Path "http-zerver" -Recurse -Force

Write-Host "Setup complete! http-zerver.exe has been copied to the assets directory." 