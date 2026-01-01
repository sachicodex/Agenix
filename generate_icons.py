#!/usr/bin/env python3
"""
Script to generate Android launcher icons and Windows ICO from logo.png
"""
import os
import sys
from PIL import Image

def generate_android_icons():
    """Generate Android launcher icons in different densities"""
    logo_path = "assets/logo/logo.png"
    
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

def generate_windows_ico():
    """Generate Windows ICO file from logo.png"""
    logo_path = "assets/logo/logo.png"
    
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
            icons.append(img_resized)
        
        # Save as ICO with multiple sizes
        output_path = "windows/runner/resources/app_icon.ico"
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        icons[0].save(
            output_path,
            format='ICO',
            sizes=[(s, s) for s in sizes]
        )
        print(f"Generated: {output_path} with sizes {sizes}")
        return True
    except Exception as e:
        print(f"Error generating Windows ICO: {e}")
        return False

if __name__ == "__main__":
    print("Generating Android launcher icons...")
    android_success = generate_android_icons()
    
    print("\nGenerating Windows ICO...")
    windows_success = generate_windows_ico()
    
    if android_success and windows_success:
        print("\n[SUCCESS] All icons generated successfully!")
        sys.exit(0)
    else:
        print("\n[ERROR] Some icons failed to generate")
        sys.exit(1)

