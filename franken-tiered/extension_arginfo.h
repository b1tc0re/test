#ifndef FRANKEN_TIERED_ARGINFO_H
#define FRANKEN_TIERED_ARGINFO_H

ZEND_BEGIN_ARG_WITH_RETURN_TYPE_MASK_EX(arginfo_franken_tiered_get, 0, 1, MAY_BE_STRING|MAY_BE_NULL|MAY_BE_FALSE)
    ZEND_ARG_TYPE_INFO(0, key, IS_STRING, 0)
ZEND_END_ARG_INFO()

ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_franken_tiered_put, 0, 3, _IS_BOOL, 0)
    ZEND_ARG_TYPE_INFO(0, key, IS_STRING, 0)
    ZEND_ARG_TYPE_INFO(0, value, IS_STRING, 0)
    ZEND_ARG_TYPE_INFO(0, seconds, IS_LONG, 0)
ZEND_END_ARG_INFO()

ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_franken_tiered_forget, 0, 1, _IS_BOOL, 0)
    ZEND_ARG_TYPE_INFO(0, key, IS_STRING, 0)
ZEND_END_ARG_INFO()

ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_franken_tiered_touch, 0, 2, _IS_BOOL, 0)
    ZEND_ARG_TYPE_INFO(0, key, IS_STRING, 0)
    ZEND_ARG_TYPE_INFO(0, seconds, IS_LONG, 0)
ZEND_END_ARG_INFO()

ZEND_FUNCTION(franken_tiered_get);
ZEND_FUNCTION(franken_tiered_put);
ZEND_FUNCTION(franken_tiered_forget);
ZEND_FUNCTION(franken_tiered_touch);

static const zend_function_entry franken_tiered_functions[] = {
    ZEND_FE(franken_tiered_get, arginfo_franken_tiered_get)
    ZEND_FE(franken_tiered_put, arginfo_franken_tiered_put)
    ZEND_FE(franken_tiered_forget, arginfo_franken_tiered_forget)
    ZEND_FE(franken_tiered_touch, arginfo_franken_tiered_touch)
    ZEND_FE_END
};

#endif
