/*
 * mini_shell.c
 * A Unix-like shell supporting:
 *  - Command execution (foreground & background)
 *  - I/O Redirection (>, <, >>)
 *  - Piping (cmd1 | cmd2 | cmd3 ...)
 *  - Built-in commands: cd, exit, help, jobs, kill
 *  - Signal handling (Ctrl+C, Ctrl+Z)
 *  - Background job tracking
 */

#include "shell.h"

/* ─────────────────────────── Globals ─────────────────────────── */
Job      job_list[MAX_JOBS];
int      job_count = 0;
volatile sig_atomic_t sigchld_received = 0;

/* ─────────────────────────── Signal Handlers ─────────────────── */

/* SIGCHLD: reap background children without blocking */
void sigchld_handler(int sig) {
    (void)sig;
    sigchld_received = 1;

    int   status;
    pid_t pid;
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        for (int i = 0; i < job_count; i++) {
            if (job_list[i].pid == pid) {
                job_list[i].status = JOB_DONE;
                printf("\n[%d] Done\t\t%s\n", job_list[i].job_id,
                       job_list[i].command);
                fflush(stdout);
                break;
            }
        }
    }
}

/* SIGINT (Ctrl+C): shell itself ignores; children receive it */
void sigint_handler(int sig) {
    (void)sig;
    printf("\n");
    fflush(stdout);
}

/* SIGTSTP (Ctrl+Z): shell ignores */
void sigtstp_handler(int sig) {
    (void)sig;
    printf("\n");
    fflush(stdout);
}

/* ─────────────────────────── Signal Setup ────────────────────── */
void setup_signal_handlers(void) {
    struct sigaction sa_chld = {0};
    sa_chld.sa_handler = sigchld_handler;
    sa_chld.sa_flags   = SA_RESTART | SA_NOCLDSTOP;
    sigemptyset(&sa_chld.sa_mask);
    sigaction(SIGCHLD, &sa_chld, NULL);

    struct sigaction sa_int = {0};
    sa_int.sa_handler = sigint_handler;
    sa_int.sa_flags   = SA_RESTART;
    sigemptyset(&sa_int.sa_mask);
    sigaction(SIGINT, &sa_int, NULL);

    struct sigaction sa_tstp = {0};
    sa_tstp.sa_handler = sigtstp_handler;
    sa_tstp.sa_flags   = SA_RESTART;
    sigemptyset(&sa_tstp.sa_mask);
    sigaction(SIGTSTP, &sa_tstp, NULL);
}

/* ─────────────────────────── Job Management ──────────────────── */
int add_job(pid_t pid, const char *command) {
    if (job_count >= MAX_JOBS) {
        fprintf(stderr, "shell: job list full\n");
        return -1;
    }
    job_list[job_count].pid     = pid;
    job_list[job_count].job_id  = job_count + 1;
    job_list[job_count].status  = JOB_RUNNING;
    strncpy(job_list[job_count].command, command, MAX_CMD_LEN - 1);
    return job_count++;
}

void remove_done_jobs(void) {
    int new_count = 0;
    for (int i = 0; i < job_count; i++) {
        if (job_list[i].status != JOB_DONE)
            job_list[new_count++] = job_list[i];
    }
    job_count = new_count;
}

/* ─────────────────────────── Prompt ─────────────────────────── */
void print_prompt(void) {
    char  cwd[MAX_PATH];
    char *home = getenv("HOME");

    if (getcwd(cwd, sizeof(cwd)) == NULL)
        strcpy(cwd, "?");

    /* Replace home prefix with '~' */
    char display[MAX_PATH];
    if (home && strncmp(cwd, home, strlen(home)) == 0)
        snprintf(display, sizeof(display), "~%s", cwd + strlen(home));
    else
        strncpy(display, cwd, sizeof(display));

    printf(COLOR_CYAN "minish" COLOR_RESET ":"
           COLOR_BLUE "%s" COLOR_RESET "$ ",
           display);
    fflush(stdout);
}

/* ─────────────────────────── Input Reading ──────────────────── */
char *read_line(void) {
    static char buf[MAX_INPUT];
    if (fgets(buf, sizeof(buf), stdin) == NULL)
        return NULL;
    buf[strcspn(buf, "\n")] = '\0';   /* strip newline */
    return buf;
}

/* ─────────────────────────── Tokeniser ─────────────────────── */
/*
 * Split input on whitespace, respecting single/double quotes.
 * Returns number of tokens placed in tokens[].
 */
int tokenise(char *input, char **tokens, int max_tokens) {
    int   count = 0;
    char *p     = input;

    while (*p && count < max_tokens - 1) {
        /* skip whitespace */
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;

        if (*p == '"' || *p == '\'') {
            /* quoted token */
            char  quote = *p++;
            char *start = p;
            while (*p && *p != quote) p++;
            if (*p) *p++ = '\0';
            tokens[count++] = start;
        } else {
            /* unquoted token */
            tokens[count++] = p;
            while (*p && *p != ' ' && *p != '\t') p++;
            if (*p) *p++ = '\0';
        }
    }
    tokens[count] = NULL;
    return count;
}

/* ─────────────────────────── Command Parsing ────────────────── */
/*
 * Parse a single command segment (no pipes) into a Command struct.
 * Handles: input redirect (<), output redirect (> and >>), background (&).
 */
Command parse_command(char **tokens, int ntok) {
    Command cmd = {0};
    cmd.argc = 0;
    cmd.input_file  = NULL;
    cmd.output_file = NULL;
    cmd.append      = 0;
    cmd.background  = 0;

    for (int i = 0; i < ntok; i++) {
        if (strcmp(tokens[i], "<") == 0) {
            if (i + 1 < ntok)
                cmd.input_file = tokens[++i];
            else
                fprintf(stderr, "shell: expected filename after '<'\n");
        } else if (strcmp(tokens[i], ">>") == 0) {
            if (i + 1 < ntok) {
                cmd.output_file = tokens[++i];
                cmd.append = 1;
            } else {
                fprintf(stderr, "shell: expected filename after '>>'\n");
            }
        } else if (strcmp(tokens[i], ">") == 0) {
            if (i + 1 < ntok)
                cmd.output_file = tokens[++i];
            else
                fprintf(stderr, "shell: expected filename after '>'\n");
        } else if (strcmp(tokens[i], "&") == 0) {
            cmd.background = 1;
        } else {
            cmd.argv[cmd.argc++] = tokens[i];
        }
    }
    cmd.argv[cmd.argc] = NULL;
    return cmd;
}

/*
 * Split a flat token array on "|" into separate Command structs.
 * Returns number of commands (pipeline length).
 */
int parse_pipeline(char **tokens, int ntok, Command *cmds, int max_cmds) {
    int   cmd_count = 0;
    int   start     = 0;

    for (int i = 0; i <= ntok && cmd_count < max_cmds; i++) {
        if (i == ntok || strcmp(tokens[i], "|") == 0) {
            if (i > start)
                cmds[cmd_count++] = parse_command(tokens + start, i - start);
            start = i + 1;
        }
    }
    return cmd_count;
}

/* ─────────────────────────── I/O Redirect Helper ────────────── */
void apply_redirections(Command *cmd) {
    if (cmd->input_file) {
        int fd = open(cmd->input_file, O_RDONLY);
        if (fd < 0) { perror(cmd->input_file); exit(EXIT_FAILURE); }
        dup2(fd, STDIN_FILENO);
        close(fd);
    }
    if (cmd->output_file) {
        int flags = O_WRONLY | O_CREAT | (cmd->append ? O_APPEND : O_TRUNC);
        int fd    = open(cmd->output_file, flags, 0644);
        if (fd < 0) { perror(cmd->output_file); exit(EXIT_FAILURE); }
        dup2(fd, STDOUT_FILENO);
        close(fd);
    }
}

/* ─────────────────────────── Built-ins ──────────────────────── */
int builtin_cd(char **argv) {
    const char *dir = argv[1] ? argv[1] : getenv("HOME");
    if (!dir) { fprintf(stderr, "cd: HOME not set\n"); return 1; }
    if (chdir(dir) != 0) { perror("cd"); return 1; }
    return 0;
}

int builtin_jobs(void) {
    remove_done_jobs();
    if (job_count == 0) {
        printf("No background jobs.\n");
        return 0;
    }
    for (int i = 0; i < job_count; i++) {
        const char *st = (job_list[i].status == JOB_RUNNING) ? "Running" : "Done";
        printf("[%d] %s\t\t%s\n", job_list[i].job_id, st, job_list[i].command);
    }
    return 0;
}

int builtin_kill_job(char **argv) {
    if (!argv[1]) { fprintf(stderr, "kill: usage: kill <pid>\n"); return 1; }
    pid_t pid = (pid_t)atoi(argv[1]);
    if (kill(pid, SIGTERM) != 0) { perror("kill"); return 1; }
    return 0;
}

void builtin_help(void) {
    printf(COLOR_CYAN
    "╔══════════════════════════════════════════════════╗\n"
    "║              Mini Unix Shell — Help              ║\n"
    "╚══════════════════════════════════════════════════╝\n"
    COLOR_RESET
    "  Built-in commands:\n"
    "    cd [dir]        Change directory (default: HOME)\n"
    "    jobs            List background jobs\n"
    "    kill <pid>      Send SIGTERM to process <pid>\n"
    "    help            Show this help message\n"
    "    exit [code]     Exit shell with optional code\n\n"
    "  Special operators:\n"
    "    cmd &           Run command in background\n"
    "    cmd > file      Redirect stdout to file (truncate)\n"
    "    cmd >> file     Redirect stdout to file (append)\n"
    "    cmd < file      Redirect stdin from file\n"
    "    cmd1 | cmd2     Pipe stdout of cmd1 to stdin of cmd2\n\n"
    "  Signals:\n"
    "    Ctrl+C          SIGINT  — interrupt foreground process\n"
    "    Ctrl+Z          SIGTSTP — suspend foreground process\n\n");
}

/*
 * Returns 1 if argv[0] is a built-in and executes it.
 * Returns 0 if not a built-in.
 */
int try_builtin(char **argv, int *exit_code) {
    if (!argv[0]) return 0;

    if (strcmp(argv[0], "exit") == 0) {
        int code = argv[1] ? atoi(argv[1]) : 0;
        printf("Exiting shell. Bye!\n");
        exit(code);
    }
    if (strcmp(argv[0], "cd") == 0)   { *exit_code = builtin_cd(argv);   return 1; }
    if (strcmp(argv[0], "jobs") == 0) { *exit_code = builtin_jobs();      return 1; }
    if (strcmp(argv[0], "kill") == 0) { *exit_code = builtin_kill_job(argv); return 1; }
    if (strcmp(argv[0], "help") == 0) { builtin_help(); *exit_code = 0;   return 1; }

    return 0;
}

/* ─────────────────────────── Execution ─────────────────────── */

/* Execute a single command (no pipes). */
int exec_single(Command *cmd) {
    int exit_code = 0;

    /* Built-in check (only for foreground, non-piped) */
    if (!cmd->background && try_builtin(cmd->argv, &exit_code))
        return exit_code;

    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }

    if (pid == 0) {
        /* ── Child ── */
        /* Restore default signal handlers in child */
        signal(SIGINT,  SIG_DFL);
        signal(SIGTSTP, SIG_DFL);
        signal(SIGCHLD, SIG_DFL);

        apply_redirections(cmd);

        execvp(cmd->argv[0], cmd->argv);
        /* execvp only returns on error */
        fprintf(stderr, "%s: command not found\n", cmd->argv[0]);
        exit(EXIT_FAILURE);
    }

    /* ── Parent ── */
    if (cmd->background) {
        /* Reconstruct full command string for display */
        char cmdstr[MAX_CMD_LEN] = {0};
        for (int i = 0; i < cmd->argc; i++) {
            strncat(cmdstr, cmd->argv[i], MAX_CMD_LEN - strlen(cmdstr) - 2);
            if (i < cmd->argc - 1)
                strncat(cmdstr, " ", 2);
        }
        int jid = add_job(pid, cmdstr);
        printf("[%d] %d\n", job_list[jid].job_id, pid);
        return 0;
    }

    /* Foreground: wait for child */
    int status;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status))
        return WEXITSTATUS(status);
    if (WIFSIGNALED(status))
        printf("\nKilled by signal %d\n", WTERMSIG(status));
    return 1;
}

/*
 * Execute a pipeline: cmd1 | cmd2 | … | cmdN
 *
 * Strategy:
 *  - Create (N-1) pipes.
 *  - Fork N children; wire up stdin/stdout via dup2.
 *  - Parent waits for all children (unless last cmd is background).
 */
int exec_pipeline(Command *cmds, int ncmds) {
    if (ncmds == 1)
        return exec_single(&cmds[0]);

    /* Create all pipes upfront */
    int pipes[MAX_ARGS][2];
    for (int i = 0; i < ncmds - 1; i++) {
        if (pipe(pipes[i]) < 0) { perror("pipe"); return 1; }
    }

    pid_t pids[MAX_ARGS];

    for (int i = 0; i < ncmds; i++) {
        pids[i] = fork();
        if (pids[i] < 0) { perror("fork"); return 1; }

        if (pids[i] == 0) {
            /* ── Child i ── */
            signal(SIGINT,  SIG_DFL);
            signal(SIGTSTP, SIG_DFL);
            signal(SIGCHLD, SIG_DFL);

            /* Connect stdin from previous pipe */
            if (i > 0) {
                dup2(pipes[i-1][0], STDIN_FILENO);
            }
            /* Connect stdout to next pipe */
            if (i < ncmds - 1) {
                dup2(pipes[i][1], STDOUT_FILENO);
            }

            /* Close all pipe fds in child */
            for (int j = 0; j < ncmds - 1; j++) {
                close(pipes[j][0]);
                close(pipes[j][1]);
            }

            /* Apply per-command redirections (overrides pipe if specified) */
            apply_redirections(&cmds[i]);

            execvp(cmds[i].argv[0], cmds[i].argv);
            fprintf(stderr, "%s: command not found\n", cmds[i].argv[0]);
            exit(EXIT_FAILURE);
        }
    }

    /* Parent: close all pipe fds */
    for (int i = 0; i < ncmds - 1; i++) {
        close(pipes[i][0]);
        close(pipes[i][1]);
    }

    /* Wait for all children */
    int last_status = 0;
    for (int i = 0; i < ncmds; i++) {
        int status;
        waitpid(pids[i], &status, 0);
        if (i == ncmds - 1 && WIFEXITED(status))
            last_status = WEXITSTATUS(status);
    }
    return last_status;
}

/* ─────────────────────────── Main Loop ─────────────────────── */
int main(void) {
    setup_signal_handlers();

    printf(COLOR_CYAN
    "╔══════════════════════════════════╗\n"
    "║   Mini Unix Shell  v1.0          ║\n"
    "║   Type 'help' for usage          ║\n"
    "╚══════════════════════════════════╝\n"
    COLOR_RESET);

    while (1) {
        /* Reap any finished background jobs before printing prompt */
        remove_done_jobs();

        print_prompt();

        char *line = read_line();
        if (!line) {                    /* EOF (Ctrl+D) */
            printf("\nlogout\n");
            break;
        }
        if (line[0] == '\0') continue;  /* empty input */

        /* Tokenise */
        char *tokens[MAX_ARGS];
        int   ntok = tokenise(line, tokens, MAX_ARGS);
        if (ntok == 0) continue;

        /* Parse pipeline */
        Command cmds[MAX_PIPE_CMDS];
        int     ncmds = parse_pipeline(tokens, ntok, cmds, MAX_PIPE_CMDS);
        if (ncmds == 0) continue;

        /* Execute */
        exec_pipeline(cmds, ncmds);
    }

    return 0;
}