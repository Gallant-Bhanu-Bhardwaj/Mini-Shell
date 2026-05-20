/*
 * shell.h  —  Mini Unix Shell header
 */

#ifndef SHELL_H
#define SHELL_H

/* Enable POSIX.1-2008 + BSD extensions (sigaction, kill, SA_* flags) */
#define _POSIX_C_SOURCE 200809L
#define _BSD_SOURCE
#define _DARWIN_C_SOURCE

/* ── Standard headers ── */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>

/* ── Limits ── */
#define MAX_INPUT      1024   /* max chars per input line          */
#define MAX_ARGS       128    /* max tokens per line               */
#define MAX_PATH       512    /* max path length                   */
#define MAX_CMD_LEN    256    /* max length stored per job entry   */
#define MAX_JOBS       64     /* max concurrent background jobs    */
#define MAX_PIPE_CMDS  16     /* max stages in a pipeline          */

/* ── Terminal colours (ANSI escapes) ── */
#define COLOR_RESET  "\033[0m"
#define COLOR_CYAN   "\033[1;36m"
#define COLOR_BLUE   "\033[1;34m"
#define COLOR_GREEN  "\033[1;32m"
#define COLOR_RED    "\033[1;31m"
#define COLOR_YELLOW "\033[1;33m"

/* ── Job status ── */
typedef enum { JOB_RUNNING, JOB_STOPPED, JOB_DONE } JobStatus;

/* ── Job entry ── */
typedef struct {
    pid_t     pid;
    int       job_id;
    JobStatus status;
    char      command[MAX_CMD_LEN];
} Job;

/* ── Parsed command ── */
typedef struct {
    char *argv[MAX_ARGS];   /* argument vector (NULL-terminated)  */
    int   argc;             /* argument count                     */
    char *input_file;       /* < redirect source, or NULL         */
    char *output_file;      /* > / >> redirect target, or NULL    */
    int   append;           /* 1 = append (>>), 0 = truncate (>)  */
    int   background;       /* 1 = run in background (&)          */
} Command;

/* ── Globals (defined in shell.c) ── */
extern Job      job_list[MAX_JOBS];
extern int      job_count;
extern volatile sig_atomic_t sigchld_received;

/* ── Function prototypes ── */

/* Signal handlers */
void sigchld_handler(int sig);
void sigint_handler(int sig);
void sigtstp_handler(int sig);
void setup_signal_handlers(void);

/* Job management */
int  add_job(pid_t pid, const char *command);
void remove_done_jobs(void);

/* Prompt & I/O */
void  print_prompt(void);
char *read_line(void);

/* Parsing */
int     tokenise(char *input, char **tokens, int max_tokens);
Command parse_command(char **tokens, int ntok);
int     parse_pipeline(char **tokens, int ntok, Command *cmds, int max_cmds);

/* Redirections */
void apply_redirections(Command *cmd);

/* Built-ins */
int  builtin_cd(char **argv);
int  builtin_jobs(void);
int  builtin_kill_job(char **argv);
void builtin_help(void);
int  try_builtin(char **argv, int *exit_code);

/* Execution */
int exec_single(Command *cmd);
int exec_pipeline(Command *cmds, int ncmds);

#endif /* SHELL_H */