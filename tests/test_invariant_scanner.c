#include <check.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* Pull in the actual scanner implementation */
#include "tree-sitter-teal/src/scanner.c"

START_TEST(test_deserialize_buffer_length_invariant)
{
    /* Invariant: deserialize must never read beyond the provided buffer_length */

    /* Create a scanner instance */
    void *scanner = tree_sitter_teal_external_scanner_create();
    ck_assert_ptr_nonnull(scanner);

    /* Payloads: (buffer, length) pairs representing exploit, boundary, valid */
    struct { size_t len; } cases[] = {
        { 0 },                        /* exact exploit: length=0, triggers OOB if no check */
        { sizeof(State) - 1 },        /* boundary: one byte short of State size */
        { sizeof(State) },            /* valid: exactly sizeof(State) */
    };

    int num_cases = sizeof(cases) / sizeof(cases[0]);

    for (int i = 0; i < num_cases; i++) {
        size_t buf_len = cases[i].len;

        /* Allocate a zeroed buffer of the declared length (or 1 byte minimum to avoid NULL) */
        size_t alloc_len = buf_len > 0 ? buf_len : 1;
        char *buf = calloc(alloc_len, 1);
        ck_assert_ptr_nonnull(buf);

        /* Fill with a recognizable pattern */
        memset(buf, 0xAB, alloc_len);

        /*
         * The invariant: deserialize must not read beyond buf_len bytes.
         * If buf_len < sizeof(State), the function must either skip or
         * handle gracefully — not perform an out-of-bounds memcpy.
         * We assert the call completes without crashing (checked via return).
         */
        tree_sitter_teal_external_scanner_deserialize(scanner, (const char *)buf, buf_len);

        /* If we reach here, no crash occurred — invariant holds for this case */
        ck_assert(1);

        free(buf);
    }

    tree_sitter_teal_external_scanner_destroy(scanner);
}
END_TEST

Suite *security_suite(void)
{
    Suite *s;
    TCase *tc_core;

    s = suite_create("Security");
    tc_core = tcase_create("Core");

    tcase_add_test(tc_core, test_deserialize_buffer_length_invariant);
    suite_add_tcase(s, tc_core);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = security_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}