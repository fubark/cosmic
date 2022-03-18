"use strict";

(function() {

    cs.test.assert = function(pred, msg) {
        if (pred) {
            return
        }
        throw new Error(msg || 'Assertion failed.')
    }

    cs.test.eq = function(act, exp) {
        if (equal(act, exp)) {
            return
        }
        throw new Error(`\nActual:\n${format(act)}\nExpected:\n${format(exp)}`)
    }

    cs.test.neq = function(act, exp) {
        if (!equal(act, exp)) {
            return
        }
        throw new Error(`\nExpected not equal.\nActual: ${act}\nExpected: ${exp}`)
    }

    cs.test.contains = function(act, needle) {
        if (typeof needle === 'string') {
            if (typeof act !== 'string') {
                throw new Error(`Expected string, got: ${act}`)
            }
            if (act.includes(needle)) {
                return
            } else {
                throw new Error(`"${act}" does not include "${needle}"`)
            }
        } else {
            throw new Error(`unsupported type: ${typeof needle}`)
        }
    }

    cs.test.throws = function(fn, containsText) {
        try {
            fn()
            throw new Error(`expected exception`)
        } catch (err) {
            if (containsText) {
                cs.test.contains(err.message, containsText)
            }
        }
    }

    cs.test.fail = function(msg) {
        throw new Error(msg || 'Fail.')
    }

    function equal(act, exp) {
        if (Object.is(act, exp)) {
            return true
        }
        if (typeof act === 'object' && typeof exp === 'object') {
            if (Object.keys(act || {}).length !== Object.keys(exp || {}).length) {
                return false
            }
            for (const key of Object.getOwnPropertyNames(act)) {
                if (!equal(act[key], exp[key])) {
                    return false
                }
            }
            return true
        }
        return false
    }

    function format(o) {
        return JSON.stringify(o, (key, value) => {
            if (typeof value === 'object') {
                if (value === null) {
                    return value
                }
                // Recreate the object with keys sorted.
                return Object.keys(value).sort().reduce((obj, key) => {
                    obj[key] = value[key]
                    return obj
                }, {})
            }
            return value
        }, 2)
    }

})();