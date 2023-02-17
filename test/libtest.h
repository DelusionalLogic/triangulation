#pragma once

#include "vector.h"

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>

struct TestResultEq {
    char* name;
    bool inverse;
    const uint64_t actual;
    const uint64_t expected;
};

struct TestResultEqFlt {
    char* name;
    bool inverse;
    const double actual;
    const double expected;
};

struct TestResultEqBool {
    char* name;
    bool inverse;
    const bool actual;
    const bool expected;
};

struct TestResultEqPtr {
    char* name;
    bool inverse;
    const void* actual;
    const void* expected;
};

struct TestResultEqArr {
    char* name;
};

struct TestResultEqStr {
    char* name;
    const size_t actual;
    const size_t expected;
    int length;
};

struct TestResultAssert {
};

enum TestResultType {
    TEST_STATIC,
    TEST_EQ,
    TEST_EQ_FLOAT,
    TEST_EQ_BOOL,
    TEST_EQ_PTR,
    TEST_EQ_ARRAY,
    TEST_EQ_STRING,
};

struct TestResult {
    void* extra;
    size_t extra_len;
    bool success;

    enum TestResultType type;
    union {
        struct TestResultAssert assert;
        struct TestResultEq eq;
        struct TestResultEqFlt eq_flt;
        struct TestResultEqBool eq_bool;
        struct TestResultEqPtr ptr_eq;
        struct TestResultEqArr eq_arr;
        struct TestResultEqStr eq_str;
    };
};

enum TestOutcome {
    OUTCOME_SUCCESS,
    OUTCOME_ASSERT,
    OUTCOME_INTERNAL_FAILURE,

    // Used by the test framework internally
    OUTCOME_DONE,
};

struct Test {
    char* name;
    bool crashExpected;
    enum TestOutcome outcome;
    Vector res;
};

void assertStatic_internal(bool result);
void assertEqPtr_internal(char* name, bool inverse, const void* value, const void* expected);
void assertEq_internal(char* name, bool inverse, uint64_t value, uint64_t expected);
void assertEqBool_internal(char* name, bool inverse, bool value, bool expected);
void assertEqFloat_internal(char* name, bool inverse, double value, double expected);
void assertEqArray_internal(char* name, bool inverse, const void* var, const void* value, size_t size);
void assertEqString_internal(char* name, bool inverse, const char* var, const char* value, size_t size);

#define GET_ASSERT_FUNCTION(var)                  \
    _Generic((var),                               \
            void*: assertEqPtr_internal,          \
            char*: assertEqPtr_internal,          \
            bool: assertEqBool_internal,          \
            uint64_t: assertEq_internal,          \
            uint8_t: assertEq_internal,           \
            int8_t: assertEq_internal,            \
            int: assertEq_internal,               \
            char: assertEq_internal,              \
            long: assertEq_internal,              \
            float: assertEqFloat_internal,        \
            double: assertEqFloat_internal        \
            )

#define assertEq(var, val)                  \
    GET_ASSERT_FUNCTION(var)(#var, false, var, val)

#define assertNotEq(var, val)               \
    GET_ASSERT_FUNCTION(var)(#var, true, var, val)

#define assertEqArray(var, val, len) \
    assertEqArray_internal(#var, false, var, val, len)

#define assertEqString(var, val, len) \
    assertEqString_internal(#var, false, var, val, len)

#define assertNo() \
    assertStatic_internal(false)

#define assertYes() \
    assertStatic_internal(true)

#define NUMARGS(...)  (sizeof((int[]){__VA_ARGS__})/sizeof(int))

typedef void (*test_func)();

void test_select(int argc, char** argv);
void test_run(char* name, test_func func);

#define TEST(f)                          \
    test_run(#f, f)

struct TestName {
    char* thing;
    char* will;
    char* when;
};

void test_shouldAssert();

void test_parseName(char* name, struct TestName* res);

uint32_t test_end();
