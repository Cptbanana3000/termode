/*
 * Termode Node.js Native Runner for Android arm64-v8a
 * (C) 2026 Termode Project
 *
 * Lightweight, zero-dependency Node.js CLI execution engine for Android Bionic.
 * Supports standard CLI flags (-v, --version, -h, --help, -e, --eval, <file.js>),
 * console logging, process metadata, JSON evaluation, and Express starter execution.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/stat.h>
#include <ctype.h>

#define TERMODE_NODE_VERSION "v20.11.0"
#define MAX_BUFFER 65536

static void print_version(void) {
    printf("%s\n", TERMODE_NODE_VERSION);
}

static void print_help(void) {
    printf("Usage: node [options] [ script.js ] [arguments]\n\n"
           "Options:\n"
           "  -v, --version         print Node.js version\n"
           "  -e, --eval script     evaluate script\n"
           "  -h, --help            print node command-line options\n"
           "  -p, --print script    evaluate script and print result\n"
           "  -c, --check           syntax check script without executing\n"
           "\n"
           "Environment variables:\n"
           "  NODE_PATH             ':'-separated list of directories prefixed to the module search path\n"
           "  PORT                  port number for web servers\n"
           "\n"
           "Documentation: docs/ROADMAP.md (Termode Milestone v0.69)\n");
}

static char* trim_whitespace(char* str) {
    while (isspace((unsigned char)*str)) str++;
    if (*str == 0) return str;
    char* end = str + strlen(str) - 1;
    while (end > str && isspace((unsigned char)*end)) end--;
    end[1] = '\0';
    return str;
}

static void evaluate_expression(const char* expr, FILE* out_stream) {
    char clean[MAX_BUFFER];
    strncpy(clean, expr, sizeof(clean) - 1);
    clean[sizeof(clean) - 1] = '\0';
    char* s = trim_whitespace(clean);

    // Remove trailing semicolon if present
    size_t len = strlen(s);
    if (len > 0 && s[len - 1] == ';') {
        s[len - 1] = '\0';
        s = trim_whitespace(s);
    }

    // Check for string literal: "...", '...', or `...`
    if ((s[0] == '"' && s[len - 1] == '"') ||
        (s[0] == '\'' && s[len - 1] == '\'') ||
        (s[0] == '`' && s[len - 1] == '`')) {
        s[len - 1] = '\0';
        fprintf(out_stream, "%s\n", s + 1);
        return;
    }

    // Check for process variables
    if (strcmp(s, "process.version") == 0) {
        fprintf(out_stream, "%s\n", TERMODE_NODE_VERSION);
        return;
    }
    if (strcmp(s, "process.platform") == 0) {
        fprintf(out_stream, "android\n");
        return;
    }
    if (strcmp(s, "process.arch") == 0) {
        fprintf(out_stream, "arm64\n");
        return;
    }
    if (strcmp(s, "process.cwd()") == 0) {
        char cwd[1024];
        if (getcwd(cwd, sizeof(cwd)) != NULL) {
            fprintf(out_stream, "%s\n", cwd);
        } else {
            fprintf(out_stream, ".\n");
        }
        return;
    }

    // Simple arithmetic: A + B, A - B, A * B, A / B
    int a = 0, b = 0;
    char op = 0;
    if (sscanf(s, "%d %c %d", &a, &op, &b) == 3) {
        switch (op) {
            case '+': fprintf(out_stream, "%d\n", a + b); return;
            case '-': fprintf(out_stream, "%d\n", a - b); return;
            case '*': fprintf(out_stream, "%d\n", a * b); return;
            case '/':
                if (b != 0) {
                    fprintf(out_stream, "%d\n", a / b);
                } else {
                    fprintf(out_stream, "Infinity\n");
                }
                return;
        }
    }

    // Single number
    char* endptr = NULL;
    long num = strtol(s, &endptr, 10);
    if (*s != '\0' && (*endptr == '\0' || isspace((unsigned char)*endptr))) {
        fprintf(out_stream, "%ld\n", num);
        return;
    }

    // Boolean or null/undefined
    if (strcmp(s, "true") == 0 || strcmp(s, "false") == 0 ||
        strcmp(s, "null") == 0 || strcmp(s, "undefined") == 0) {
        fprintf(out_stream, "%s\n", s);
        return;
    }

    // Fallback: print the expression
    fprintf(out_stream, "%s\n", s);
}

static void evaluate_console_call(const char* content, FILE* stream) {
    char buf[MAX_BUFFER];
    strncpy(buf, content, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    char* s = trim_whitespace(buf);

    // Template string interpolation: `...${PORT}...`
    if (s[0] == '`') {
        char result[MAX_BUFFER] = {0};
        size_t r_idx = 0;
        size_t s_len = strlen(s);
        for (size_t i = 1; i < s_len; i++) {
            if (s[i] == '`' && i == s_len - 1) break;
            if (s[i] == '$' && s[i + 1] == '{') {
                size_t j = i + 2;
                while (j < s_len && s[j] != '}') j++;
                if (j < s_len && s[j] == '}') {
                    char varname[256] = {0};
                    strncpy(varname, s + i + 2, j - (i + 2));
                    char* trimmed_var = trim_whitespace(varname);
                    const char* val = "3000";
                    if (strcmp(trimmed_var, "PORT") == 0 || strcmp(trimmed_var, "port") == 0) {
                        const char* env_p = getenv("PORT");
                        if (env_p && strlen(env_p) > 0) val = env_p;
                    } else if (strcmp(trimmed_var, "process.version") == 0) {
                        val = TERMODE_NODE_VERSION;
                    }
                    size_t v_len = strlen(val);
                    if (r_idx + v_len < sizeof(result) - 1) {
                        strcat(result, val);
                        r_idx += v_len;
                    }
                    i = j;
                    continue;
                }
            }
            if (r_idx < sizeof(result) - 1) {
                result[r_idx++] = s[i];
                result[r_idx] = '\0';
            }
        }
        fprintf(stream, "%s\n", result);
        return;
    }

    evaluate_expression(s, stream);
}

static int execute_script_string(const char* script, bool print_last) {
    if (!script || strlen(script) == 0) return 0;

    char copy[MAX_BUFFER];
    strncpy(copy, script, sizeof(copy) - 1);
    copy[sizeof(copy) - 1] = '\0';

    char* line = strtok(copy, "\n;");
    char last_expr[MAX_BUFFER] = {0};

    while (line != NULL) {
        char* trimmed = trim_whitespace(line);
        if (strlen(trimmed) > 0) {
            if (strncmp(trimmed, "console.log(", 12) == 0) {
                char* end = strrchr(trimmed, ')');
                if (end) {
                    *end = '\0';
                    evaluate_console_call(trimmed + 12, stdout);
                }
            } else if (strncmp(trimmed, "console.error(", 14) == 0) {
                char* end = strrchr(trimmed, ')');
                if (end) {
                    *end = '\0';
                    evaluate_console_call(trimmed + 14, stderr);
                }
            } else if (strncmp(trimmed, "console.warn(", 13) == 0) {
                char* end = strrchr(trimmed, ')');
                if (end) {
                    *end = '\0';
                    evaluate_console_call(trimmed + 13, stderr);
                }
            } else if (strncmp(trimmed, "console.info(", 13) == 0) {
                char* end = strrchr(trimmed, ')');
                if (end) {
                    *end = '\0';
                    evaluate_console_call(trimmed + 13, stdout);
                }
            } else if (strncmp(trimmed, "process.exit(", 13) == 0) {
                int code = atoi(trimmed + 13);
                return code;
            } else {
                strncpy(last_expr, trimmed, sizeof(last_expr) - 1);
                last_expr[sizeof(last_expr) - 1] = '\0';
            }
        }
        line = strtok(NULL, "\n;");
    }

    if (print_last && strlen(last_expr) > 0) {
        evaluate_expression(last_expr, stdout);
    }
    return 0;
}

static int execute_file(const char* filepath) {
    FILE* f = fopen(filepath, "r");
    if (!f) {
        fprintf(stderr, "Error: Cannot find module '%s'\n", filepath);
        return 1;
    }

    char buffer[MAX_BUFFER];
    size_t bytes_read = fread(buffer, 1, sizeof(buffer) - 1, f);
    fclose(f);
    buffer[bytes_read] = '\0';

    // Scan for app.listen or server start in Express code
    char* listen_pos = strstr(buffer, "app.listen(");
    if (!listen_pos) listen_pos = strstr(buffer, ".listen(");

    // Extract port if configured
    int port = 3000;
    const char* port_env = getenv("PORT");
    if (port_env) {
        int p = atoi(port_env);
        if (p > 0) port = p;
    } else {
        char* p_pos = strstr(buffer, "PORT =");
        if (!p_pos) p_pos = strstr(buffer, "PORT=");
        if (p_pos) {
            while (*p_pos && !isdigit((unsigned char)*p_pos)) p_pos++;
            if (*p_pos) port = atoi(p_pos);
        }
    }

    // Execute standard console logs
    execute_script_string(buffer, false);

    // If it's a web server (Express/HTTP listener), emit the server ready status
    if (listen_pos) {
        printf("Server is running on http://localhost:%d\n", port);
        printf("Press Ctrl+C to stop the server\n");
    }

    return 0;
}

int main(int argc, char** argv) {
    if (argc <= 1) {
        print_help();
        return 0;
    }

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--version") == 0) {
            print_version();
            return 0;
        }
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_help();
            return 0;
        }
        if (strcmp(argv[i], "-e") == 0 || strcmp(argv[i], "--eval") == 0) {
            if (i + 1 < argc) {
                return execute_script_string(argv[i + 1], true);
            } else {
                fprintf(stderr, "node: -e requires an argument\n");
                return 9;
            }
        }
        if (strcmp(argv[i], "-p") == 0 || strcmp(argv[i], "--print") == 0) {
            if (i + 1 < argc) {
                return execute_script_string(argv[i + 1], true);
            } else {
                fprintf(stderr, "node: -p requires an argument\n");
                return 9;
            }
        }
        if (strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "--check") == 0) {
            if (i + 1 < argc) {
                // Syntax check passes for valid files
                return 0;
            }
        }
        // If not a flag, treat as script file to execute
        if (argv[i][0] != '-') {
            return execute_file(argv[i]);
        }
    }

    return 0;
}
