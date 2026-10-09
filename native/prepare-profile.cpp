// One-shot profile directory preparation. No browser data is read or modified.
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

static bool directory(const std::string &base, const std::string &child) {
    if (base.empty() || base.front() != '/' || base.size() > 4096
        || (child != "profile" && child != "cache")) return false;
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return false;
    auto descend = [&](const std::string &name, bool privateDirectory) {
        if (name.empty() || name == "." || name == "..") return false;
        if (mkdirat(fd, name.c_str(), 0700) != 0 && errno != EEXIST) return false;
        int next = openat(fd, name.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0) return false;
        struct stat info {};
        if (fstat(next, &info) != 0 || !S_ISDIR(info.st_mode)
            || (privateDirectory && (info.st_uid != getuid() || fchmod(next, 0700) != 0))) {
            close(next);
            return false;
        }
        close(fd);
        fd = next;
        return true;
    };
    bool ok = true;
    for (size_t start = 1; start < base.size();) {
        auto end = base.find('/', start);
        if (end == std::string::npos) end = base.size();
        if (end > start && !descend(base.substr(start, end - start), false)) { ok = false; break; }
        start = end + 1;
    }
    if (ok) ok = descend("omarchy-chatgpt-lite-qt", true) && descend(child, true);
    close(fd);
    return ok;
}

static std::string root(const char *variable, const char *suffix) {
    const char *value = std::getenv(variable);
    if (value && *value) return value;
    const char *home = std::getenv("HOME");
    return home && *home ? std::string(home) + suffix : std::string();
}

int main(int argc, char **argv) {
    umask(0077);
    bool ok = false;
    if (argc == 1) {
        ok = directory(root("XDG_DATA_HOME", "/.local/share"), "profile")
          && directory(root("XDG_CACHE_HOME", "/.cache"), "cache");
    } else if (argc == 4 && std::strcmp(argv[1], "--prepare") == 0) {
        // Fixed child enum; useful for isolated path checks, not arbitrary I/O.
        ok = directory(argv[2], argv[3]);
    }
    if (!ok) std::cerr << "Profile directory preparation refused\n";
    return ok ? 0 : 1;
}
