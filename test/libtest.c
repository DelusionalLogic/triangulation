#include "libtest.h"

#include "vector.h"
#include <unistd.h>
#include <sys/wait.h>
#include <assert.h>
#include <sys/resource.h>
#include <fnmatch.h>

#define RET_IF_FAIL(STMT) \
        do{ \
            struct TestResult r = STMT;\
            if(!r.success) \
                return r; \
        }while(0)

Vector results;
char** selected;
size_t selected_num;

// Per test data
int test_fd;
static bool test_sentAssertSignal = false;

void write_complete(int fd, const void* buf, size_t size) {
    size_t written = 0;
    while(size - written > 0) {
        ssize_t ret = write(fd, buf + written, size - written);
        if(ret >= 0) {
            written += ret;
        } else {
            exit(1);
        }
    }
}

void sendComplete(int fd, uint8_t state) {
    write_complete(fd, &state, 1);
}

void sendExit(int fd) {
    if(!test_sentAssertSignal) {
        static const uint8_t assertBuf = {0};
        write_complete(fd, &assertBuf, 1);
    }
    sendComplete(fd, true);
}

void sendResult(int fd, struct TestResult* result) {
    if(!test_sentAssertSignal) {
        test_sentAssertSignal = true;
        static const uint8_t assertBuf = {0};
        write_complete(fd, &assertBuf, 1);
    }

    sendComplete(fd, false);

    write_complete(fd, result, sizeof(struct TestResult));
    write_complete(fd, result->extra, result->extra_len);

	if(!result->success) {
		exit(0);
	}
}

void assertStatic_internal(bool success) {
    struct TestResult result = {
        .type = TEST_STATIC,
        .success = success,
    };

    sendResult(test_fd, &result);
}

void assertEqPtr_internal(char* name, bool inverse, const void* value, const void* expected) {
    bool success = value == expected;

    success = inverse ? !success : success;

    struct TestResult result = {
        .type = TEST_EQ_PTR,
        .success = success,
        .ptr_eq = {
            .name = name,
            .inverse = inverse,
            .actual = value,
            .expected = expected,
        }
    };

    sendResult(test_fd, &result);
}

void assertEq_internal(char* name, bool inverse, uint64_t value, uint64_t expected) {
    bool success = value == expected;

    success = inverse ? !success : success;

    struct TestResult result = {
        .type = TEST_EQ,
        .success = success,
        .eq = {
            .name = name,
            .inverse = inverse,
            .actual = value,
            .expected = expected,
        },
    };

    sendResult(test_fd, &result);
}

void assertEqFloat_internal(char* name, bool inverse, double value, double expected) {
    bool success = value == expected;

    success = inverse ? !success : success;

    // @IMPROVEMENT: Maybe we shouldn't be doing == for floats.
    struct TestResult result = {
        .type = TEST_EQ_FLOAT,
        .success = success,
        .eq_flt = {
            .name = name,
            .inverse = inverse,
            .actual = value,
            .expected = expected,
        }
    };

    sendResult(test_fd, &result);
}

void assertEqBool_internal(char* name, bool inverse, bool value, bool expected) {
    bool success = value == expected;

    success = inverse ? !success : success;

    struct TestResult result = {
        .type = TEST_EQ_BOOL,
        .success = success,
        .eq_bool = {
            .name = name,
            .inverse = inverse,
            .actual = value,
            .expected = expected,
        }
    };

    sendResult(test_fd, &result);
}

void assertEqArray_internal(char* name, bool inverse, const void* var, const void* value, size_t size) {
    struct TestResult result = {
        .type = TEST_EQ_ARRAY,
        .eq_arr = {
            .name = name,
        }
    };

    result.success = memcmp(var, value, size) == 0;
    sendResult(test_fd, &result);
}

void assertEqString_internal(char* name, bool inverse, const char* var, const char* value, size_t size) {
    struct TestResult result = {
        .type = TEST_EQ_STRING,
        .eq_str = {
            .name = name,
            .actual = 0,
            .expected = size,
            .length = size,
        }
    };

    result.extra_len = size * 2;
    result.extra = malloc(result.extra_len);

    memcpy(result.extra + result.eq_str.actual, var, size);
    memcpy(result.extra + result.eq_str.expected, value, size);

    result.success = memcmp(var, value, size) == 0;
    sendResult(test_fd, &result);
}

void test_parseName(char* name, struct TestName* res) {
    char* thing_start = name;
    char* thing_end = strstr(thing_start, "__");
    size_t thing_len = thing_end - thing_start;
    res->thing = malloc(sizeof(char) * thing_len + 1);
    memcpy(res->thing, thing_start, thing_len);
    res->thing[thing_len] = '\0';

    char* will_start = thing_end + 2;
    char* will_end = strstr(will_start, "__");
    size_t will_len = will_end - will_start;
    res->will = malloc(sizeof(char) * will_len + 1);
    memcpy(res->will, will_start, will_len);
    for(size_t i = 0; i < will_len; i++) {
        if(res->will[i] == '_') {
            res->will[i] = ' ';
        }
    }
    res->will[will_len] = '\0';

    char* when_start = will_end + 2;
    size_t when_len = strlen(when_start);
    res->when = malloc(sizeof(char) * when_len + 1);
    memcpy(res->when, when_start, when_len);
    for(size_t i = 0; i < when_len; i++) {
        if(res->when[i] == '_') {
            res->when[i] = ' ';
        }
    }
    res->when[when_len] = '\0';
}

int receiveAll(int fd, void* buffer, size_t bufferSize) {
    // @HACK: Right now we just keep reading until we either error out or
    // receive 0. We need some errorhandling instead
    size_t offset = 0;
    while(bufferSize - offset > 0) {
        ssize_t ret = read(fd, buffer + offset, bufferSize - offset);
        if(ret == 0)
            return 2;

        if(ret < 0) {
            return 1;
        }

        offset += ret;
    }
    return 0;
}

enum TestOutcome receiveResult(int fd, struct TestResult* test) {
    uint8_t complete = 0;
    int err = receiveAll(fd, &complete, 1);
    if(err == 2) return OUTCOME_ASSERT;
    if(err != 0) return OUTCOME_INTERNAL_FAILURE;

    if(complete == 1) return OUTCOME_DONE;
    assert(complete == 0);

    // The second part is the result structure itself
    if(receiveAll(fd, test, sizeof(*test)) != 0) {
        return OUTCOME_INTERNAL_FAILURE;
    }
    // The testresult we just received will have a pointer to the extra data in
    // the other process. Reset it here.
    test->extra = NULL;

    // Lastly we get the extra data
    // @HACK: As a bit of a hack. I'm just sending the struct first, and then
    // some dynamic block of memory after. This works fine, but it might be
    // a bit brittle.
    if(test->extra_len != 0) {
        test->extra = malloc(test->extra_len);
        if(test->extra == NULL) {
            return OUTCOME_INTERNAL_FAILURE;
        }
        if(receiveAll(fd, test->extra, test->extra_len) != 0) {
            free(test->extra);
            return OUTCOME_INTERNAL_FAILURE;
        }
    }

    return OUTCOME_SUCCESS;
}

void test_shouldAssert() {
    if(!test_sentAssertSignal) {
        uint8_t assertBuf[1] = {1};
        write_complete(test_fd, &assertBuf, 1);
        struct rlimit rlim;
        getrlimit(RLIMIT_CORE, &rlim);
        rlim.rlim_cur = 0;
        setrlimit(RLIMIT_CORE, &rlim);
    }
    test_sentAssertSignal = true;
}

bool matchTestName(char* name) {
    if(selected_num == 0)
        return true;

    for(int i = 0; i < selected_num; i++) {
        char* it = selected[i];
        // If there's an error we fall back to just having a match
        if(fnmatch(it, name, 0) != FNM_NOMATCH) {
            return true;
        }
    }
    return false;
}

void test_run(char* name, test_func func) {
    if(!matchTestName(name))
        return;

    int fds[2];

    //0 is read, 1 is write
    if(pipe(fds) != 0) {
        return;
    }

    int pid = fork();
    if(pid == 0) {
        close(fds[0]);

        test_fd = fds[1];

        func();
        sendExit(fds[1]);

        close(fds[1]);

        exit(0);
    } else {
        close(fds[1]);
    }

    struct Test test = {
        .name = name,
        .outcome = OUTCOME_SUCCESS,
    };

    // The first byte we receive indicates if we wanted to assert
    uint8_t shouldAssert = 0;
    if(receiveAll(fds[0], &shouldAssert, 1) != 0) {
        test.outcome = OUTCOME_INTERNAL_FAILURE;
        exit(1);
    }
    test.crashExpected = shouldAssert != 0;

    vector_init(&test.res, sizeof(struct TestResult), 8);
    while(true) {
        struct TestResult result;
        enum TestOutcome outcome = receiveResult(fds[0], &result);
        if(outcome == OUTCOME_DONE)
            break;
        if(outcome == OUTCOME_ASSERT)
            break;
        assert(outcome == OUTCOME_SUCCESS);

        vector_putBack(&test.res, &result);
    }

    int status;
    waitpid(pid, &status, 0);
    close(fds[0]);

    if(!WIFEXITED(status) && test.outcome != OUTCOME_INTERNAL_FAILURE) {
        test.outcome = OUTCOME_ASSERT;
    }

    vector_putBack(&results, &test);
}

#define ANSI_COLOR_RED     "\x1b[31m"
#define ANSI_COLOR_GREEN   "\x1b[32m"
#define ANSI_COLOR_YELLOW  "\x1b[33m"
#define ANSI_COLOR_BLUE    "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN    "\x1b[36m"
#define ANSI_COLOR_WHITE   "\x1b[90m"
#define ANSI_COLOR_RESET   "\x1b[0m"

void test_select(int argc, char** argv) {
    vector_init(&results, sizeof(struct Test), 128);

    // First argument is the executable name, skip that.
    selected = argv + 1;
    selected_num = argc - 1;
}

uint32_t test_end() {
    uint32_t failed = 0;

    size_t index;
    struct Test* test = vector_getFirst(&results, &index);
    while(test != NULL) {
        bool success;
        if(test->outcome == OUTCOME_SUCCESS) {
            if(!test->crashExpected) {
                success = true;

                size_t i;
                struct TestResult *it = vector_getFirst(&test->res, &i);
                while(it != NULL) {
                    success = it->success ? success : false;
                    it = vector_getNext(&test->res, &i);
                }

            } else {
                success = false;
            }
        } else if(test->outcome == OUTCOME_ASSERT) {
            success = test->crashExpected;
        } else {
            success = false;
        }

        struct TestName name;
        test_parseName(test->name, &name);

        if(success) {
            printf(ANSI_COLOR_GREEN "✓ "
                    ANSI_COLOR_WHITE "A" ANSI_COLOR_RESET " %s "
                    ANSI_COLOR_WHITE "will" ANSI_COLOR_RESET " %s "
                    ANSI_COLOR_WHITE "when" ANSI_COLOR_RESET " %s"
                    ANSI_COLOR_RESET "\n", name.thing, name.will, name.when);
        } else {
            printf(ANSI_COLOR_RED "✗ "
                    ANSI_COLOR_RED "A" ANSI_COLOR_RESET " %s "
                    ANSI_COLOR_RED "won't" ANSI_COLOR_RESET " %s "
                    ANSI_COLOR_RED "when" ANSI_COLOR_RESET " %s"
                    ANSI_COLOR_RESET "\n", name.thing, name.will, name.when);
            failed++;
        }

        if(test->outcome == OUTCOME_SUCCESS) {
            size_t i;
            struct TestResult *it = vector_getFirst(&test->res, &i);
            while(it != NULL) {
                struct TestResult result = *it;

                switch(result.type) {
                    case TEST_STATIC:
                        printf("\tStatic assertion\n");
                        break;
                    case TEST_EQ:
                        printf("\tEquality test on %s %ld==%ld\n", result.eq.name, result.eq.actual, result.eq.expected);
                        break;
                    case TEST_EQ_FLOAT:
                        printf("\tFloating equality test on %s %f==%f\n", result.eq_flt.name, result.eq_flt.actual, result.eq_flt.expected);
                        break;
                    case TEST_EQ_BOOL:
                        printf("\tBoolean equality test on %s %d==%d\n", result.eq_bool.name, result.eq_bool.actual, result.eq_bool.expected);
                        break;
                    case TEST_EQ_PTR:
                        printf(
                            "\tPointer equality test on %s %p%c=%p\n",
                            result.ptr_eq.name, result.ptr_eq.actual,
                            result.ptr_eq.inverse ? '!':'=',
                            result.ptr_eq.expected
                        );
                        break;
                    case TEST_EQ_ARRAY:
                        printf("\tArray equality test on %s\n", result.eq_arr.name);
                        break;
                    case TEST_EQ_STRING:
                        printf("\tString equality test on %s %.*s==%.*s\n",result.eq_str.name,
                                result.eq_str.length, (char*)result.extra + result.eq_str.actual,
                                result.eq_str.length, (char*)result.extra + result.eq_str.expected);
                        // @LEAK: We just leak the actual and expected strings here.
                        // It's a test script, so who cares?
                        break;
                }
                it = vector_getNext(&test->res, &i);
            }
        } else if(test->outcome == OUTCOME_ASSERT) {
            printf("\tCrashed during test\n");
        } else {
            printf("\tInternal framework error in test\n");
        }
        test = vector_getNext(&results, &index);
    }

    printf("%d/%d tests failed\n", failed, vector_size(&results));
    return failed > 0;
}
