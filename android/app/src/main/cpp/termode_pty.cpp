#include <jni.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <ctype.h>
#include <math.h>
#include <string>
#include <sstream>
#include <vector>

// ---------------------------------------------------------------------------
// Tiny native tool helpers (v0.29). These run entirely inside the bundled
// native library. They spawn no shell, launch no external process, perform no
// network access, and write no files.
// ---------------------------------------------------------------------------

static const char *termode_native_abi() {
#if defined(__aarch64__)
    return "arm64-v8a";
#elif defined(__arm__)
    return "armeabi-v7a";
#elif defined(__x86_64__)
    return "x86_64";
#elif defined(__i386__)
    return "x86";
#else
    return "unknown";
#endif
}

static uint32_t sha256_rotr(uint32_t value, uint32_t shift) {
    return (value >> shift) | (value << (32 - shift));
}

// Self-contained SHA-256 over a byte string, returning lowercase hex.
static std::string termode_sha256_hex(const std::string &input) {
    std::vector<uint8_t> msg(input.begin(), input.end());
    uint64_t bitLength = (uint64_t)msg.size() * 8;
    msg.push_back(0x80);
    while ((msg.size() % 64) != 56) {
        msg.push_back(0x00);
    }
    for (int shift = 56; shift >= 0; shift -= 8) {
        msg.push_back((uint8_t)((bitLength >> shift) & 0xff));
    }

    static const uint32_t k[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
        0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

    uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                     0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};

    for (size_t offset = 0; offset < msg.size(); offset += 64) {
        uint32_t w[64];
        for (int i = 0; i < 16; i++) {
            const size_t j = offset + i * 4;
            w[i] = ((uint32_t)msg[j] << 24) | ((uint32_t)msg[j + 1] << 16) |
                   ((uint32_t)msg[j + 2] << 8) | ((uint32_t)msg[j + 3]);
        }
        for (int i = 16; i < 64; i++) {
            uint32_t s0 = sha256_rotr(w[i - 15], 7) ^ sha256_rotr(w[i - 15], 18) ^
                          (w[i - 15] >> 3);
            uint32_t s1 = sha256_rotr(w[i - 2], 17) ^ sha256_rotr(w[i - 2], 19) ^
                          (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }

        uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
        uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];

        for (int i = 0; i < 64; i++) {
            uint32_t S1 = sha256_rotr(e, 6) ^ sha256_rotr(e, 11) ^ sha256_rotr(e, 25);
            uint32_t ch = (e & f) ^ ((~e) & g);
            uint32_t temp1 = hh + S1 + ch + k[i] + w[i];
            uint32_t S0 = sha256_rotr(a, 2) ^ sha256_rotr(a, 13) ^ sha256_rotr(a, 22);
            uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
            uint32_t temp2 = S0 + maj;
            hh = g; g = f; f = e; e = d + temp1;
            d = c; c = b; b = a; a = temp1 + temp2;
        }

        h[0] += a; h[1] += b; h[2] += c; h[3] += d;
        h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }

    char buf[65];
    for (int i = 0; i < 8; i++) {
        snprintf(buf + i * 8, 9, "%08x", h[i]);
    }
    return std::string(buf, 64);
}

static std::string jsproof_trim(const std::string &input) {
    size_t start = 0;
    while (start < input.size() && isspace((unsigned char)input[start])) start++;
    size_t end = input.size();
    while (end > start && isspace((unsigned char)input[end - 1])) end--;
    return input.substr(start, end - start);
}

static std::string jsproof_format_number(double value) {
    if (!isfinite(value)) {
        return "Error: Unsupported JS proof syntax.";
    }
    if (fabs(value - round(value)) < 0.000000001) {
        char buf[64];
        snprintf(buf, sizeof(buf), "%.0f", value);
        return std::string(buf);
    }
    std::ostringstream out;
    out.precision(12);
    out << value;
    return out.str();
}

class JsProofParser {
public:
    explicit JsProofParser(const std::string &src) : text(src), pos(0), failed(false) {}

    bool parse(double &value) {
        value = parseExpression();
        skipSpaces();
        if (failed || pos != text.size()) {
            return false;
        }
        return true;
    }

private:
    const std::string &text;
    size_t pos;
    bool failed;

    void skipSpaces() {
        while (pos < text.size() && isspace((unsigned char)text[pos])) pos++;
    }

    bool match(char c) {
        skipSpaces();
        if (pos < text.size() && text[pos] == c) {
            pos++;
            return true;
        }
        return false;
    }

    double parseExpression() {
        double value = parseTerm();
        while (!failed) {
            if (match('+')) {
                value += parseTerm();
            } else if (match('-')) {
                value -= parseTerm();
            } else {
                break;
            }
        }
        return value;
    }

    double parseTerm() {
        double value = parseFactor();
        while (!failed) {
            if (match('*')) {
                value *= parseFactor();
            } else if (match('/')) {
                double divisor = parseFactor();
                if (fabs(divisor) < 0.0000000001) {
                    failed = true;
                    return 0.0;
                }
                value /= divisor;
            } else {
                break;
            }
        }
        return value;
    }

    double parseFactor() {
        skipSpaces();
        if (match('+')) return parseFactor();
        if (match('-')) return -parseFactor();
        if (match('(')) {
            double value = parseExpression();
            if (!match(')')) {
                failed = true;
            }
            return value;
        }
        return parseNumber();
    }

    double parseNumber() {
        skipSpaces();
        const size_t start = pos;
        bool hasDigit = false;
        bool hasDot = false;
        while (pos < text.size()) {
            char c = text[pos];
            if (isdigit((unsigned char)c)) {
                hasDigit = true;
                pos++;
            } else if (c == '.' && !hasDot) {
                hasDot = true;
                pos++;
            } else {
                break;
            }
        }
        if (!hasDigit) {
            failed = true;
            return 0.0;
        }
        return strtod(text.substr(start, pos - start).c_str(), nullptr);
    }
};

static std::string termode_jsproof_eval(const std::string &input) {
    std::string code = jsproof_trim(input);
    if (code.empty() || code.size() > 4096) {
        return "ERR:Unsupported JS proof syntax.";
    }
    const std::string lowered = [&code]() {
        std::string out = code;
        for (char &c : out) c = (char)tolower((unsigned char)c);
        return out;
    }();
    const char *blocked[] = {"require", "import", "function", "=>", "process", "global", "fs", "http", "settimeout", "eval", ";"};
    for (const char *token : blocked) {
        if (lowered.find(token) != std::string::npos) {
            return "ERR:Unsupported JS proof syntax.";
        }
    }
    if ((code.size() >= 2 && code.front() == '\'' && code.back() == '\'') ||
        (code.size() >= 2 && code.front() == '"' && code.back() == '"')) {
        return "OK:" + code.substr(1, code.size() - 2);
    }
    if (code == "true" || code == "false") {
        return "OK:" + code;
    }
    JsProofParser parser(code);
    double value = 0.0;
    if (!parser.parse(value)) {
        return "ERR:Unsupported JS proof syntax.";
    }
    return "OK:" + jsproof_format_number(value);
}

extern "C" {

// Bundled runtime proof (v0.28): a tiny, self-contained native bridge proof.
// It executes NO external code and writes NO files. It only proves that
// Termode can call into its own bundled native library and get a result back.

JNIEXPORT jstring JNICALL
Java_com_termode_termode_MainActivity_nativeProofToken(
    JNIEnv *env, jobject thiz) {
    return env->NewStringUTF("termode-native-proof-ok");
}

// --- Tiny native tool proof (v0.29) -------------------------------------

JNIEXPORT jstring JNICALL
Java_com_termode_termode_MainActivity_nativeToolEcho(
    JNIEnv *env, jobject thiz, jstring input) {
    const char *c_input = env->GetStringUTFChars(input, nullptr);
    jstring out = env->NewStringUTF(c_input ? c_input : "");
    if (c_input) {
        env->ReleaseStringUTFChars(input, c_input);
    }
    return out;
}

JNIEXPORT jstring JNICALL
Java_com_termode_termode_MainActivity_nativeToolCwd(
    JNIEnv *env, jobject thiz) {
    char buf[4096];
    if (getcwd(buf, sizeof(buf)) != nullptr) {
        return env->NewStringUTF(buf);
    }
    return env->NewStringUTF("unknown");
}

JNIEXPORT jint JNICALL
Java_com_termode_termode_MainActivity_nativeToolPid(
    JNIEnv *env, jobject thiz) {
    return (jint)getpid();
}

JNIEXPORT jstring JNICALL
Java_com_termode_termode_MainActivity_nativeToolAbi(
    JNIEnv *env, jobject thiz) {
    return env->NewStringUTF(termode_native_abi());
}

JNIEXPORT jstring JNICALL
Java_com_termode_termode_MainActivity_nativeToolHash(
    JNIEnv *env, jobject thiz, jstring input) {
    const char *c_input = env->GetStringUTFChars(input, nullptr);
    std::string text(c_input ? c_input : "");
    if (c_input) {
        env->ReleaseStringUTFChars(input, c_input);
    }
    return env->NewStringUTF(termode_sha256_hex(text).c_str());
}

JNIEXPORT jlong JNICALL
Java_com_termode_termode_MainActivity_nativeToolTime(
    JNIEnv *env, jobject thiz) {
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) != 0) {
        return (jlong)-1;
    }
    return (jlong)ts.tv_sec * 1000 + (jlong)(ts.tv_nsec / 1000000);
}

// Tiny JS proof (v0.31): controlled JS-like evaluator. This is not Node.js
// and not a real JS engine. It supports only arithmetic, simple literals, and
// clean syntax errors. It spawns no shell and launches no external process.
JNIEXPORT jstring JNICALL
Java_com_termode_termode_MainActivity_jsProofEvalNative(
    JNIEnv *env, jobject thiz, jstring input) {
    const char *c_input = env->GetStringUTFChars(input, nullptr);
    std::string code(c_input ? c_input : "");
    if (c_input) {
        env->ReleaseStringUTFChars(input, c_input);
    }
    return env->NewStringUTF(termode_jsproof_eval(code).c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_termode_termode_MainActivity_jsProofDoctorNative(
    JNIEnv *env, jobject thiz) {
    return termode_jsproof_eval("1 + 2 * 3") == "OK:7" &&
           termode_jsproof_eval("require('fs')").rfind("ERR:", 0) == 0
        ? JNI_TRUE
        : JNI_FALSE;
}

// Tiny native-side command dispatcher proof. It only understands a literal
// "echo <text>" and returns "<text>". It does not run a shell or external
// process. Anything else is echoed back unchanged.
JNIEXPORT jstring JNICALL
Java_com_termode_termode_MainActivity_nativeEchoProof(
    JNIEnv *env, jobject thiz, jstring input) {
    const char *c_input = env->GetStringUTFChars(input, nullptr);
    std::string text(c_input ? c_input : "");
    if (c_input) {
        env->ReleaseStringUTFChars(input, c_input);
    }
    const std::string prefix = "echo ";
    std::string out;
    if (text.rfind(prefix, 0) == 0) {
        out = text.substr(prefix.size());
    } else if (text == "echo") {
        out = "";
    } else {
        out = text;
    }
    return env->NewStringUTF(out.c_str());
}

JNIEXPORT jintArray JNICALL
Java_com_termode_termode_MainActivity_nativeStartPty(
    JNIEnv *env, jobject thiz,
    jstring home_dir, jstring working_dir, jstring usr_dir, jstring bin_dir, jstring tmp_dir,
    jstring path_env, jobjectArray env_keys, jobjectArray env_values,
    jint cols, jint rows) {

    // 1. Allocate Master PTY
    int master_fd = open("/dev/ptmx", O_RDWR | O_CLOEXEC);
    if (master_fd < 0) {
        jintArray err = env->NewIntArray(2);
        jint temp[2] = {-1, -1}; // -1 maps to ptmx open failure
        env->SetIntArrayRegion(err, 0, 2, temp);
        return err;
    }

    if (grantpt(master_fd) < 0) {
        close(master_fd);
        jintArray err = env->NewIntArray(2);
        jint temp[2] = {-2, -2}; // -2 maps to grantpt failure
        env->SetIntArrayRegion(err, 0, 2, temp);
        return err;
    }

    if (unlockpt(master_fd) < 0) {
        close(master_fd);
        jintArray err = env->NewIntArray(2);
        jint temp[2] = {-3, -3}; // -3 maps to unlockpt failure
        env->SetIntArrayRegion(err, 0, 2, temp);
        return err;
    }

    char *slave_name = ptsname(master_fd);
    if (!slave_name) {
        close(master_fd);
        jintArray err = env->NewIntArray(2);
        jint temp[2] = {-4, -4}; // -4 maps to ptsname failure
        env->SetIntArrayRegion(err, 0, 2, temp);
        return err;
    }

    // Set initial terminal dimensions
    struct winsize ws;
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    ioctl(master_fd, TIOCSWINSZ, &ws);

    // Convert parameters to UTF-8
    const char *c_home = env->GetStringUTFChars(home_dir, nullptr);
    const char *c_working = env->GetStringUTFChars(working_dir, nullptr);
    const char *c_usr = env->GetStringUTFChars(usr_dir, nullptr);
    const char *c_bin = env->GetStringUTFChars(bin_dir, nullptr);
    const char *c_tmp = env->GetStringUTFChars(tmp_dir, nullptr);
    const char *c_path = env->GetStringUTFChars(path_env, nullptr);

    // Prepare environment array for child
    jsize env_size = env->GetArrayLength(env_keys);
    int custom_env_count = 7 + env_size;
    char **envp = (char **)malloc((custom_env_count + 1) * sizeof(char *));
    
    asprintf(&envp[0], "HOME=%s", c_home);
    asprintf(&envp[1], "TERMODE_HOME=%s", c_home);
    asprintf(&envp[2], "TERMODE_USR=%s", c_usr);
    asprintf(&envp[3], "TERMODE_BIN=%s", c_bin);
    asprintf(&envp[4], "TMPDIR=%s", c_tmp);
    asprintf(&envp[5], "PATH=%s", c_path);
    asprintf(&envp[6], "TERM=xterm-256color");

    for (int i = 0; i < env_size; ++i) {
        jstring key = (jstring)env->GetObjectArrayElement(env_keys, i);
        jstring val = (jstring)env->GetObjectArrayElement(env_values, i);
        const char *c_key = env->GetStringUTFChars(key, nullptr);
        const char *c_val = env->GetStringUTFChars(val, nullptr);
        asprintf(&envp[7 + i], "%s=%s", c_key, c_val);
        env->ReleaseStringUTFChars(key, c_key);
        env->ReleaseStringUTFChars(val, c_val);
    }
    envp[custom_env_count] = nullptr;

    pid_t pid = fork();
    if (pid < 0) {
        // Release environment strings
        for (int i = 0; i < custom_env_count; ++i) {
            free(envp[i]);
        }
        free(envp);
        env->ReleaseStringUTFChars(home_dir, c_home);
        env->ReleaseStringUTFChars(working_dir, c_working);
        env->ReleaseStringUTFChars(usr_dir, c_usr);
        env->ReleaseStringUTFChars(bin_dir, c_bin);
        env->ReleaseStringUTFChars(tmp_dir, c_tmp);
        env->ReleaseStringUTFChars(path_env, c_path);
        close(master_fd);

        jintArray err = env->NewIntArray(2);
        jint temp[2] = {-5, -5}; // -5 maps to fork failure
        env->SetIntArrayRegion(err, 0, 2, temp);
        return err;
    }

    if (pid == 0) {
        // Child Process
        // Establish new session and group
        setsid();

        // Open Slave PTY
        int slave_fd = open(slave_name, O_RDWR);
        if (slave_fd < 0) {
            exit(127);
        }

        // Set controlling tty
#ifdef TIOCSCTTY
        ioctl(slave_fd, TIOCSCTTY, 0);
#endif

        // Duplicate standard streams to Slave PTY
        dup2(slave_fd, 0);
        dup2(slave_fd, 1);
        dup2(slave_fd, 2);

        if (slave_fd > 2) {
            close(slave_fd);
        }
        close(master_fd);

        // Start in requested directory while keeping HOME unchanged.
        chdir(c_working);

        // Execute sh
        char *argv[] = {(char *)"/system/bin/sh", nullptr};
        execve(argv[0], argv, envp);
        
        // If execve fails
        exit(127);
    }

    // Parent Process
    env->ReleaseStringUTFChars(home_dir, c_home);
    env->ReleaseStringUTFChars(working_dir, c_working);
    env->ReleaseStringUTFChars(usr_dir, c_usr);
    env->ReleaseStringUTFChars(bin_dir, c_bin);
    env->ReleaseStringUTFChars(tmp_dir, c_tmp);
    env->ReleaseStringUTFChars(path_env, c_path);
    for (int i = 0; i < custom_env_count; ++i) {
        free(envp[i]);
    }
    free(envp);

    jintArray res = env->NewIntArray(2);
    jint temp[2] = {master_fd, pid};
    env->SetIntArrayRegion(res, 0, 2, temp);
    return res;
}

JNIEXPORT jboolean JNICALL
Java_com_termode_termode_MainActivity_nativeResizePty(
    JNIEnv *env, jobject thiz, jint fd, jint cols, jint rows) {
    struct winsize ws;
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    if (ioctl(fd, TIOCSWINSZ, &ws) < 0) {
        return JNI_FALSE;
    }
    return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_com_termode_termode_MainActivity_nativeKillProcessGroup(
    JNIEnv *env, jobject thiz, jint pid, jint sig) {
    // Sending signal to -pid signals the entire process group
    if (kill(-pid, sig) < 0) {
        // Fallback to single PID
        if (kill(pid, sig) < 0) {
            return JNI_FALSE;
        }
    }
    return JNI_TRUE;
}

JNIEXPORT jint JNICALL
Java_com_termode_termode_MainActivity_nativeWaitPid(
    JNIEnv *env, jobject thiz, jint pid) {
    int status;
    return waitpid(pid, &status, 0);
}

JNIEXPORT jint JNICALL
Java_com_termode_termode_MainActivity_nativeRead(
    JNIEnv *env, jobject thiz, jint fd, jbyteArray buffer) {
    
    jsize len = env->GetArrayLength(buffer);
    jbyte *buf = env->GetByteArrayElements(buffer, nullptr);
    
    int bytes_read = read(fd, buf, len);
    
    env->ReleaseByteArrayElements(buffer, buf, 0);
    return bytes_read;
}

JNIEXPORT jint JNICALL
Java_com_termode_termode_MainActivity_nativeWrite(
    JNIEnv *env, jobject thiz, jint fd, jbyteArray data) {
    
    jsize len = env->GetArrayLength(data);
    jbyte *buf = env->GetByteArrayElements(data, nullptr);
    
    int bytes_written = write(fd, buf, len);
    
    env->ReleaseByteArrayElements(data, buf, JNI_ABORT);
    return bytes_written;
}

JNIEXPORT void JNICALL
Java_com_termode_termode_MainActivity_nativeClose(
    JNIEnv *env, jobject thiz, jint fd) {
    close(fd);
}

}
