#!/usr/bin/env python3
"""
Script to generate Android launcher icons and Windows ICO from platform-specific PNG files
"""
import os
import sys
from PIL import Image

def generate_android_icons():
    """Generate Android launcher icons in different densities"""
    logo_path = "assets/logo/agenix-android.png"
    
    if not os.path.exists(logo_path):
        print(f"Error: {logo_path} not found!")
        return False
    
    # Android icon sizes for different densities
    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    
    try:
        # Open the source logo
        img = Image.open(logo_path)
        
        # Generate icons for each density
        for folder, size in sizes.items():
            # Resize image maintaining aspect ratio, then crop to square if needed
            img_resized = img.resize((size, size), Image.Resampling.LANCZOS)
            
            # Save to Android mipmap folder
            output_path = f"android/app/src/main/res/{folder}/ic_launcher.png"
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            img_resized.save(output_path, "PNG")
            print(f"Generated: {output_path} ({size}x{size})")
        
        return True
    except Exception as e:
        print(f"Error generating Android icons: {e}")
        return False

def generate_android_adaptive_icons():
    """Generate Android adaptive icon foregrounds in different densities"""
    logo_path = "assets/logo/agenix-android.png"
    
    if not os.path.exists(logo_path):
        print(f"Error: {logo_path} not found!")
        return False
    
    # Android adaptive icon foreground sizes for different densities
    # These sizes correspond to the safe zone (432dp) scaled for each density
    sizes = {
        "mipmap-mdpi": 108,      # 432dp / 4
        "mipmap-hdpi": 162,      # 432dp / 2.67
        "mipmap-xhdpi": 216,     # 432dp / 2
        "mipmap-xxhdpi": 324,    # 432dp / 1.33
        "mipmap-xxxhdpi": 432,   # 432dp (1:1)
    }
    
    try:
        # Open the source logo
        img = Image.open(logo_path)
        
        # Generate foreground icons for each density
        for folder, size in sizes.items():
            # Resize image maintaining aspect ratio
            img_resized = img.resize((size, size), Image.Resampling.LANCZOS)
            
            # Save to Android mipmap folder as foreground
            output_path = f"android/app/src/main/res/{folder}/ic_launcher_foreground.png"
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            img_resized.save(output_path, "PNG")
            print(f"Generated: {output_path} ({size}x{size})")
        
        return True
    except Exception as e:
        print(f"Error generating Android adaptive icons: {e}")
        import traceback
        traceback.print_exc()
        return False

def generate_windows_ico():
    """Generate Windows ICO file from agenix-windows.png"""
    logo_path = "assets/logo/agenix-windows.png"
    
    if not os.path.exists(logo_path):
        print(f"Error: {logo_path} not found!")
        return False
    
    try:
        # Open the source logo
        img = Image.open(logo_path)
        
        # Windows ICO typically needs multiple sizes: 16, 32, 48, 64, 128, 256
        sizes = [16, 32, 48, 64, 128, 256]
        icons = []
        
        for size in sizes:
            img_resized = img.resize((size, size), Image.Resampling.LANCZOS)
            # Convert to RGBA if not already (ICO format requires it)
            if img_resized.mode != 'RGBA':
                img_resized = img_resized.convert('RGBA')
            icons.append(img_resized)
        
        # Save as ICO with multiple sizes
        # PIL's ICO format properly supports multiple images when using append_images
        output_path = "windows/runner/resources/app_icon.ico"
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        # Delete old ICO file if it exists to ensure clean generation
        if os.path.exists(output_path):
            os.remove(output_path)
        
        # Create ICO with all sizes
        # PIL's ICO format: The first image is saved, and append_images adds additional resolutions
        # However, PIL might not properly create multi-resolution ICO files
        # So we'll save each size individually and combine them
        
        # Try using PIL's built-in ICO support first
        try:
            icons[0].save(
                output_path,
                format='ICO',
                append_images=icons[1:] if len(icons) > 1 else []
            )
            
            file_size = os.path.getsize(output_path)
            print(f"Generated: {output_path} with sizes {sizes}")
            print(f"  File size: {file_size:,} bytes")
            
            # If file is too small, PIL didn't create proper multi-resolution ICO
            # In this case, we'll use the largest icon (256x256) which Windows will scale
            if file_size < 5000:
                print(f"  WARNING: ICO file is too small. Using 256x256 icon only.")
                print(f"  Windows will scale this icon as needed.")
                # Use the largest icon (256x256) - Windows will scale it
                os.remove(output_path)
                icons[-1].save(output_path, format='ICO')  # Save the 256x256 icon
                new_size = os.path.getsize(output_path)
                print(f"  New file size: {new_size:,} bytes (256x256 only)")
        except Exception as e2:
            print(f"  Error saving ICO: {e2}")
            # Fallback: save largest icon
            icons[-1].save(output_path, format='ICO')
            print(f"  Saved 256x256 icon as fallback")
        
        if not os.path.exists(output_path):
            print(f"ERROR: ICO file was not created")
            return False
        
        return True
    except Exception as e:
        print(f"Error generating Windows ICO: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("Generating Android launcher icons...")
    android_success = generate_android_icons()
    
    print("\nGenerating Android adaptive icon foregrounds...")
    adaptive_success = generate_android_adaptive_icons()
    
    print("\nGenerating Windows ICO...")
    windows_success = generate_windows_ico()
    
    if android_success and adaptive_success and windows_success:
        print("\n[SUCCESS] All icons generated successfully!")
        sys.exit(0)
    else:
        print("\n[ERROR] Some icons failed to generate")
        sys.exit(1)

