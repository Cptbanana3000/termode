#include <jni.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <string.h>
#include <signal.h>
#include <string>

extern "C" {

// Bundled runtime proof (v0.28): a tiny, self-contained native bridge proof.
// It executes NO external code and writes NO files. It only proves that
// Termode can call into its own bundled native library and get a result back.

JNIEXPORT jstring JNICALL
Java_com_termode_termode_MainActivity_nativeProofToken(
    JNIEnv *env, jobject thiz) {
    return env->NewStringUTF("termode-native-proof-ok");
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
