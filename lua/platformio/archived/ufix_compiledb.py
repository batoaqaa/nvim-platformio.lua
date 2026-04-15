import glob
import json
import os

Import("env")


def get_dynamic_toolchain():
    """Scans all installed packages to find the active toolchain and triplet."""
    platform = env.PioPlatform()
    # Get the directory where all packages for this platform are stored
    packages_dir = platform.get_package_dir("") or ""

    # Scan for any toolchain packages currently in use
    for pkg_name in platform.packages.keys():
        if not pkg_name.startswith("toolchain-"):
            continue

        pkg_dir = platform.get_package_dir(pkg_name)
        if not pkg_dir:
            continue

        # Logic: The triplet is usually the name of the folder inside /bin
        # before the '-gcc' suffix. e.g., 'riscv32-esp-elf-gcc' -> 'riscv32-esp-elf'
        bin_dir = os.path.join(pkg_dir, "bin")
        gcc_files = glob.glob(os.path.join(bin_dir, "*-gcc*"))

        if gcc_files:
            # Extract triplet from the first gcc binary found
            # e.g., C:/.../bin/xtensa-esp32-elf-gcc.exe -> xtensa-esp32-elf
            filename = os.path.basename(gcc_files[0])
            triplet = filename.split("-gcc")[0]

            cc_path = gcc_files[0].replace("\\", "/")
            sysroot = os.path.join(pkg_dir, triplet).replace("\\", "/")

            if os.path.isdir(sysroot):
                return cc_path, sysroot, triplet

    return None, None, None


def update_compilation_db(source, target, env_inner):
    db_path = str(target)
    cc_path, sysroot, triplet = get_dynamic_toolchain()

    if not cc_path or not os.path.exists(db_path):
        print("-- [UniversalFix] Toolchain not found via dynamic scan.")
        return

    with open(db_path, "r") as f:
        db = json.load(f)

    for entry in db:
        extra_flags = f' --target={triplet} --sysroot="{sysroot}"'
        # Replace the compiler command if it's just the binary name
        if triplet in entry["command"] and "--target=" not in entry["command"]:
            # This regex-like replacement ensures we don't break existing flags
            entry["command"] = entry["command"].replace(
                f"{triplet}-gcc", f'"{cc_path}"'
            )
            entry["command"] += extra_flags

    with open(db_path, "w") as f:
        json.dump(db, f, indent=2)

    print(f"\n-- [UniversalFix] Detected: {triplet}")
    print(f"-- [UniversalFix] Sysroot: {sysroot}")


# Hook into the compilation database generation
env.AddPostAction("$PROJECT_DIR/compile_commands.json", update_compilation_db)
