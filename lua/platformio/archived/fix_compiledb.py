import json
import os

# Grab the environment from PlatformIO
Import("env")

def get_toolchain_metadata():
    """Detects active toolchain and returns (cc_path, sysroot, target_triplet)."""
    platform = env.PioPlatform()
    
    # List of known Espressif toolchains and their internal triplets
    toolchains = [
        ("toolchain-riscv32-esp", "riscv32-esp-elf"),
        ("toolchain-xtensa-esp32", "xtensa-esp32-elf"),
        ("toolchain-xtensa-esp32s2", "xtensa-esp32s2-elf"),
        ("toolchain-xtensa-esp32s3", "xtensa-esp32s3-elf"),
    ]

    for pkg_name, triplet in toolchains:
        pkg_dir = platform.get_package_dir(pkg_name)
        if pkg_dir:
            # Construct paths
            cc_name = f"{triplet}-gcc"
            cc_path = os.path.join(pkg_dir, "bin", cc_name)
            if os.name == "nt":
                cc_path += ".exe"
            
            sysroot = os.path.join(pkg_dir, triplet)
            
            # Return cleaned forward-slash paths for clangd compatibility
            return cc_path.replace("\\", "/"), sysroot.replace("\\", "/"), triplet

    return None, None, None

def update_compilation_db(source, target, env_inner):
    """Callback to fix the JSON file after generation."""
    db_path = str(target)
    cc_path, sysroot, triplet = get_toolchain_metadata()

    if not cc_path or not os.path.exists(db_path):
        print(f"-- [FixDB] Toolchain not detected or {db_path} missing.")
        return

    with open(db_path, "r") as f:
        db = json.load(f)

    for entry in db:
        # Inject the correct target and sysroot
        extra_flags = f" --target={triplet} --sysroot=\"{sysroot}\""
        
        if "--target=" not in entry["command"]:
            # Replace relative compiler name with absolute path
            entry["command"] = entry["command"].replace(f"{triplet}-gcc", f"\"{cc_path}\"")
            entry["command"] += extra_flags

    with open(db_path, "w") as f:
        json.dump(db, f, indent=2)
    
    print(f"\n-- [FixDB] Auto-detected {triplet}")
    print(f"-- [FixDB] Injected sysroot: {sysroot}")

# Register the hook
env.AddPostAction("$PROJECT_DIR/compile_commands.json", update_compilation_db)
