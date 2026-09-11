#include <php.h>
#include "extension.h"
#include "extension_arginfo.h"
#include "_cgo_export.h"

PHP_FUNCTION(franken_tiered_get)
{
    zend_string *key;

    ZEND_PARSE_PARAMETERS_START(1, 1)
        Z_PARAM_STR(key)
    ZEND_PARSE_PARAMETERS_END();

    int status = 0;
    zend_string *result = go_franken_tiered_get(key, &status);

    if (status == 1) {
        RETURN_NULL();
    }

    if (status != 0 || result == NULL) {
        RETURN_FALSE;
    }

    RETURN_STR(result);
}

PHP_FUNCTION(franken_tiered_put)
{
    zend_string *key;
    zend_string *value;
    zend_long seconds;

    ZEND_PARSE_PARAMETERS_START(3, 3)
        Z_PARAM_STR(key)
        Z_PARAM_STR(value)
        Z_PARAM_LONG(seconds)
    ZEND_PARSE_PARAMETERS_END();

    RETURN_BOOL(go_franken_tiered_put(key, value, seconds));
}

PHP_FUNCTION(franken_tiered_forget)
{
    zend_string *key;

    ZEND_PARSE_PARAMETERS_START(1, 1)
        Z_PARAM_STR(key)
    ZEND_PARSE_PARAMETERS_END();

    RETURN_BOOL(go_franken_tiered_forget(key));
}

PHP_FUNCTION(franken_tiered_touch)
{
    zend_string *key;
    zend_long seconds;

    ZEND_PARSE_PARAMETERS_START(2, 2)
        Z_PARAM_STR(key)
        Z_PARAM_LONG(seconds)
    ZEND_PARSE_PARAMETERS_END();

    RETURN_BOOL(go_franken_tiered_touch(key, seconds));
}

zend_module_entry franken_tiered_module_entry = {
    STANDARD_MODULE_HEADER,
    "franken_tiered",
    franken_tiered_functions,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    "0.1.0",
    STANDARD_MODULE_PROPERTIES
};
