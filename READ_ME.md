# Mini Unix Shell (`minish`)

A Unix-like shell written in C using low-level Linux system calls.

---

## Project Structure

```
mini_shell/
├── shell.h          # All types, constants, prototypes
├── shell.c          # Full implementation (~400 lines)
├── Makefile         # Build, debug, clean targets
├── test_shell.sh    # Automated test suite (10 tests)
└── README.md        # This file
```

---

## Features

| Feature | Details |
|---|---|
| **Command execution** | `fork` + `execvp` + `waitpid` |
| **Foreground / Background** | `cmd &` runs in background; tracked in job list |
| **Output redirect** | `cmd > file` (truncate), `cmd >> file` (append) |
| **Input redirect** | `cmd < file` |
| **Piping** | `cmd1 \| cmd2 \| cmd3` (unlimited stages) |
| **Built-in: cd** | `cd [dir]` — defaults to `$HOME` |
| **Built-in: jobs** | Lists running background jobs |
| **Built-in: kill** | `kill <pid>` — sends `SIGTERM` |
| **Built-in: help** | Prints usage summary |
| **Built-in: exit** | `exit [code]` — exits shell |
| **Signal handling** | `SIGINT` (Ctrl+C), `SIGTSTP` (Ctrl+Z), `SIGCHLD` |
| **Prompt** | Shows `minish:~/current/dir$` with `~` abbreviation |

---

## Build & Run

```bash
# Build
make

# Run the shell
./minish

# Build with AddressSanitizer + UBSan
make debug

# Clean
make clean
```

---

## Usage Examples

```bash
# Basic command
minish:~$ ls -la

# Output redirection
minish:~$ echo "hello" > out.txt
minish:~$ echo "world" >> out.txt

# Input redirection
minish:~$ wc -l < out.txt

# Pipe
minish:~$ cat /etc/passwd | grep root | cut -d: -f1

# Background job
minish:~$ sleep 30 &
[1] 12345

# List jobs
minish:~$ jobs
[1] Running    sleep 30

# Kill a process
minish:~$ kill 12345

# Change directory
minish:~$ cd /tmp
minish:/tmp$

# Exit
minish:~$ exit 0
```

---

## System Calls Used

| Call | Purpose |
|---|---|
| `fork()` | Create child process |
| `execvp()` | Replace child image with command |
| `waitpid()` | Wait for / reap child processes |
| `pipe()` | Create inter-process communication channel |
| `dup2()` | Redirect file descriptors |
| `open()` / `close()` | File I/O for redirections |
| `chdir()` | Implement `cd` built-in |
| `getcwd()` | Read current directory for prompt |
| `kill()` | Send signals to processes |
| `sigaction()` | Register signal handlers |
| `sigemptyset()` | Initialise signal masks |
| `getenv()` | Access environment variables |

---

## Architecture

```
read_line()
    │
    ▼
tokenise()          ← splits on whitespace, respects quotes
    │
    ▼
parse_pipeline()    ← splits tokens on '|' into Command structs
    │   └── parse_command()  ← extracts argv, redirects, & flag
    ▼
exec_pipeline()
    ├── [1 cmd]  → exec_single()
    │                 ├── try_builtin()   (cd, exit, jobs, ...)
    │                 └── fork + execvp + waitpid
    └── [N cmds] → fork N children
                   ├── wire pipes via dup2()
                   ├── apply per-cmd redirections
                   ├── execvp each child
                   └── parent waits for all children
```

---

## Running the Test Suite

```bash
bash test_shell.sh
```

Tests cover: echo, cd/pwd, `>`, `>>`, `<`, single pipe, 3-stage pipe,
background job + jobs, help, and unknown-command error handling.

---

## Concepts Demonstrated

- **fork–exec model**: child process image replacement
- **File descriptors & dup2**: stdin/stdout redirection
- **Pipe chaining**: `pipe()` array connecting N processes
- **Process groups & signals**: `SIGCHLD` reaping, `SIGINT`/`SIGTSTP` handling
- **Job control**: background process tracking without a full TTY layer
- **Wait mechanisms**: `waitpid(WNOHANG)` for non-blocking background reap

---

## Limitations & Possible Extensions

- No `fg`/`bg` commands (would require `tcsetpgrp` + process groups)
- No command history or line editing (add `readline` library for that)
- No glob expansion (`*.c` etc.) — add `glob()` call in executor
- No here-documents (`<<`)
- Single-level variable expansion only (no `$()` subshells)